import Foundation
import Network

/// A client connection that has opened a socket but not yet sent `client.intro`.
struct PartialConnection: Sendable {
  let id: Int
  let address: String
}

/// NWListener-backed WebSocket server implementing the Reactotron wire protocol.
///
/// Port of `reactotron-core-server.ts`. Connection bookkeeping, message
/// handling, and sends all happen on `queue`; events are invoked on that
/// same queue (callers hop to MainActor as needed).
final class ReactotronServer: @unchecked Sendable {
  struct Events {
    var started: @Sendable () -> Void = {}
    var stopped: @Sendable () -> Void = {}
    var connect: @Sendable (PartialConnection) -> Void = { _ in }
    var connectionEstablished: @Sendable (Connection) -> Void = { _ in }
    var command: @Sendable (Command) -> Void = { _ in }
    var disconnect: @Sendable (Connection) -> Void = { _ in }
    var portUnavailable: @Sendable (UInt16) -> Void = { _ in }
  }

  var events = Events()

  private let queue = DispatchQueue(label: "com.reactotron.server")

  private var listener: NWListener?
  private var keepAliveTimer: DispatchSourceTimer?

  // MARK: - Connection state (queue-confined)

  private var connectionId = 0
  private var messageId = 0

  private var partialConnections: [Int: PartialConnection] = [:]
  private var sockets: [Int: NWConnection] = [:]
  private var clientIds: [Int: String] = [:]
  private var connections: [Int: Connection] = [:]
  private var customCommands: [String: [CustomCommand]] = [:]

  private(set) var subscriptions: [String] = []

  // MARK: - Lifecycle

  func start(port: UInt16) {
    let params = NWParameters.tcp
    let wsOptions = NWProtocolWebSocket.Options()
    wsOptions.autoReplyPing = true
    params.allowLocalEndpointReuse = true
    params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
    let listener = try! NWListener(using: params, on: nwPort)
    self.listener = listener
    listener.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        self?.events.started()
      case .failed(let error):
        if case .posix(.EADDRINUSE) = error {
          self?.events.portUnavailable(port)
        } else {
          NSLog("Reactotron server failed: \(error)")
        }
      default:
        break
      }
    }
    listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
    listener.start(queue: queue)
    startKeepAlive()
  }

  func stop() {
    queue.sync {
      keepAliveTimer?.cancel()
      keepAliveTimer = nil
      for (_, sock) in sockets { sock.cancel() }
      listener?.cancel()
      listener = nil
      partialConnections.removeAll()
      sockets.removeAll()
      clientIds.removeAll()
      connections.removeAll()
      customCommands.removeAll()
      subscriptions.removeAll()
      connectionId = 0
      messageId = 0
      events.stopped()
    }
  }

  // MARK: - Accept

  private func accept(_ conn: NWConnection) {
    let id = connectionId
    connectionId += 1

    var address = ""
    if case .hostPort(let host, _) = conn.endpoint {
      let full = "\(host)"
      address = full.split(separator: "%", maxSplits: 1).first.map(String.init) ?? full
    }

    let partial = PartialConnection(id: id, address: address)
    partialConnections[id] = partial
    sockets[id] = conn

    events.connect(partial)

    conn.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.handleClose(connectionId: id)
      default:
        break
      }
    }

    conn.start(queue: queue)
    receiveLoop(conn, id: id)

    // Resend the current subscriptions to everyone upon connecting, matching
    // reactotron-core-server.ts's unconditional `stateValuesSendSubscriptions()`
    // call at the end of its "connection" handler (a plain broadcast, not
    // targeted at just the new socket).
    sendSubscriptions()
  }

  // MARK: - Close

  private func handleClose(connectionId id: Int) {
    partialConnections.removeValue(forKey: id)
    if let connection = connections.removeValue(forKey: id) {
      customCommands.removeValue(forKey: connection.clientId)
      events.disconnect(connection)
    }
    clientIds.removeValue(forKey: id)
    sockets.removeValue(forKey: id)
  }

  // MARK: - Receive

  private func receiveLoop(_ conn: NWConnection, id: Int) {
    conn.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }
      if let data, error == nil {
        self.handleMessage(data: data, connectionId: id)
        self.receiveLoop(conn, id: id)
      } else {
        conn.cancel()
      }
    }
  }

  // MARK: - Message processing

  private func handleMessage(data: Data, connectionId id: Int) {
    guard let message = try? JSONDecoder().decode(WireMessage.self, from: data) else { return }

    let payload = SerializationRepair.repair(message.payload ?? .null)
    let diff = message.diff.map { SerializationRepair.repair($0) }

    messageId += 1

    var command = Command(
      type: message.type,
      connectionId: id,
      messageId: messageId,
      date: parseCommandDate(message.date),
      deltaTime: message.deltaTime ?? 0,
      important: message.important?.isTruthy ?? false,
      payload: payload,
      clientId: clientIds[id],
      diff: diff
    )

    if message.type == "client.intro" {
      let address = partialConnections[id]?.address ?? ""

      var introPayload = payload
      if case .object(var obj) = introPayload {
        obj["address"] = .string(address)
        introPayload = .object(obj)
      }

      partialConnections.removeValue(forKey: id)
      command.payload = introPayload  // JS mutates the shared payload object in-place with .address

      var connectionClientId = introPayload["clientId"]?.stringValue

      if connectionClientId == nil {
        let guid = Self.createGuid()
        connectionClientId = guid
        sendRaw(type: "setClientId", payload: .string(guid), toConnectionId: id)
      } else {
        let dupClientId = connectionClientId!
        let staleConnectionIds = sockets.keys.filter { $0 != id && clientIds[$0] == dupClientId }
        for staleId in staleConnectionIds {
          if let staleSocket = sockets[staleId] {
            queue.asyncAfter(deadline: .now() + 0.5) { [weak staleSocket] in
              staleSocket?.cancel()
            }
          }
          connections.removeValue(forKey: staleId)
        }
      }

      let clientId = connectionClientId!
      clientIds[id] = clientId
      command.clientId = clientId

      let connection = Connection(id: id, clientId: clientId, address: address, intro: introPayload)
      connections[id] = connection
      events.connectionEstablished(connection)
    }

    if message.type == "state.values.change" {
      let changes = payload["changes"]?.arrayValue ?? []
      subscriptions = changes.compactMap { $0["path"]?.stringValue }
    }

    if message.type == "customCommand.register", let clientId = command.clientId {
      let args = (payload["args"]?.arrayValue ?? []).compactMap { arg -> CustomCommandArg? in
        guard let name = arg["name"]?.stringValue, let type = arg["type"]?.stringValue else { return nil }
        return CustomCommandArg(name: name, type: type)
      }
      let custom = CustomCommand(
        id: Int(payload["id"]?.numberValue ?? 0),
        clientId: clientId,
        command: payload["command"]?.stringValue ?? "",
        title: payload["title"]?.stringValue,
        description: payload["description"]?.stringValue,
        args: args
      )
      customCommands[clientId, default: []].append(custom)
    }

    if message.type == "customCommand.unregister", let clientId = command.clientId {
      let removeId = Int(payload["id"]?.numberValue ?? 0)
      customCommands[clientId]?.removeAll { $0.id == removeId }
    }

    // Assign a name to the backups since the client doesn't pass one. Without
    // it, downstream consumers have to special-case a missing key instead of
    // a standard assignment.
    if message.type == "state.backup.response" {
      if case .object(var obj) = command.payload {
        obj["name"] = .null
        command.payload = .object(obj)
      } else {
        command.payload = .object(["name": .null])
      }
    }

    events.command(command)
  }

  // MARK: - Send

  func send(type: String, payload: JSONValue, clientId: String? = nil) {
    queue.async { [self] in
      let text = JSONValue.object(["type": .string(type), "payload": payload]).encodedString() ?? "{}"
      let meta = NWProtocolWebSocket.Metadata(opcode: .text)
      let ctx = NWConnection.ContentContext(identifier: "send", metadata: [meta])
      for (connId, sock) in sockets {
        if let clientId, clientIds[connId] != clientId { continue }
        sock.send(content: Data(text.utf8), contentContext: ctx, isComplete: true, completion: .idempotent)
      }
    }
  }

  /// Sends to exactly one connection by connection id (used for setClientId, before a clientId is assigned).
  private func sendRaw(type: String, payload: JSONValue, toConnectionId id: Int) {
    guard let sock = sockets[id] else { return }
    let text = JSONValue.object(["type": .string(type), "payload": payload]).encodedString() ?? "{}"
    let meta = NWProtocolWebSocket.Metadata(opcode: .text)
    let ctx = NWConnection.ContentContext(identifier: "send", metadata: [meta])
    sock.send(content: Data(text.utf8), contentContext: ctx, isComplete: true, completion: .idempotent)
  }

  // MARK: - State subscriptions

  func stateValuesSubscribe(path: String) {
    queue.async { [self] in
      guard !subscriptions.contains(path) else { return }
      subscriptions.append(path == "*" ? "" : path)
      sendSubscriptions()
    }
  }

  func stateValuesUnsubscribe(path: String) {
    queue.async { [self] in
      guard subscriptions.contains(path) else { return }
      subscriptions.removeAll { $0 == path }
      sendSubscriptions()
    }
  }

  func stateValuesClearSubscriptions() {
    queue.async { [self] in
      subscriptions.removeAll()
      sendSubscriptions()
    }
  }

  private func sendSubscriptions() {
    let paths = subscriptions.map { JSONValue.string($0) }
    send(type: "state.values.subscribe", payload: .object(["paths": .array(paths)]))
  }

  // MARK: - Keepalive

  private func startKeepAlive() {
    keepAliveTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 30, repeating: 30)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let meta = NWProtocolWebSocket.Metadata(opcode: .ping)
      let ctx = NWConnection.ContentContext(identifier: "ping", metadata: [meta])
      for (_, sock) in self.sockets {
        sock.send(content: nil, contentContext: ctx, isComplete: true, completion: .idempotent)
      }
    }
    timer.resume()
    keepAliveTimer = timer
  }

  // MARK: - GUID

  private static func createGuid() -> String {
    func s4() -> String {
      String(format: "%04x", UInt16.random(in: 0...0xFFFF))
    }
    return "\(s4())\(s4())-\(s4())-\(s4())-\(s4())-\(s4())\(s4())\(s4())"
  }
}
