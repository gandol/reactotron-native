import Foundation
import ImageIO
import Observation

/// Port of `reactotron-mcp/src/mcp-server.ts` + `tools.ts` + `resources.ts` +
/// `serialization.ts`. Serves the MCP "streamable HTTP" JSON-RPC protocol over
/// `MinimalHTTPServer`, executing tools/resources against a `ReactotronServer`
/// and redacting all returned data through `Redaction`.
///
/// The observable surface (`running`, `port`, `rules`) lives on `@MainActor`
/// for SwiftUI; the request handling itself runs off-main on the HTTP server's
/// queue, against a lock-guarded `McpCore` that owns the command ring buffer,
/// the live redaction rules, and the `ReactotronServer` reference.
@MainActor @Observable
final class McpServer {
  private(set) var running = false
  private(set) var port: Int?

  /// Live-updatable redaction rules (from the settings modal). Applied to every
  /// tool/resource result.
  var rules: Redaction.Rules {
    didSet { core.setRules(rules) }
  }

  /// Whether any redaction rule is active — drives the footer's
  /// "redaction-enforced" indicator. (This port always enforces the server
  /// rules; it does not parse a per-client `mcpRedaction` opt-out off the wire.)
  var redactionEnforced: Bool {
    !rules.sensitiveKeys.isEmpty || !rules.valuePatterns.isEmpty || !rules.statePathPatterns.isEmpty
  }

  /// The lock-guarded, `Sendable` core. Exposed `nonisolated` so the server
  /// queue can buffer commands into it directly, without hopping to the main
  /// actor and contending with MCP request handlers for its lock.
  nonisolated let core = McpCore()
  private var http: MinimalHTTPServer?

  init(rules: Redaction.Rules = .defaults) {
    self.rules = rules
    core.setRules(rules)
  }

  /// Wire the `ReactotronServer` the tools act on. Call once before `start`.
  func attach(server: ReactotronServer) {
    core.setServer(server)
  }

  /// Feed a command into the ring buffer. No-op unless the server is running
  /// (mirrors `mcp-server.ts` only buffering between `startBuffering`/`stop`).
  func buffer(_ command: Command) {
    core.buffer(command)
  }

  func start(port: Int) {
    guard !running else { return }
    let core = self.core
    let server = MinimalHTTPServer { method, path, headers, body in
      core.handle(method: method, path: path, headers: headers, body: body)
    }
    do {
      try server.start(port: UInt16(port))
      core.setBuffering(true)
      http = server
      running = true
      self.port = port
    } catch {
      core.setBuffering(false)
      http = nil
      running = false
      self.port = nil
      NSLog("[reactotron-mcp] failed to start on port \(port): \(error)")
    }
  }

  func stop() {
    guard running else { return }
    http?.stop()
    http = nil
    core.setBuffering(false)  // also clears the buffer, matching stopBuffering()
    running = false
    port = nil
  }
}

// MARK: - Core (off-main, lock-guarded)

/// Owns the command buffer, live rules, and `ReactotronServer` reference, and
/// implements the JSON-RPC dispatch. All mutable state is guarded by `lock`;
/// the HTTP handler runs on the server's (background) queue while `buffer` is
/// fed from the main actor.
final class McpCore: @unchecked Sendable {
  static let bufferSize = 500  // BUFFER_SIZE in mcp-server.ts
  static let responseTimeout: TimeInterval = 1.5  // 1500ms poll window in tools.ts
  static let pollInterval: TimeInterval = 0.1  // 100ms between polls in tools.ts

  private let lock = NSLock()
  private var commandBuffer: [Command] = []
  private var rules: Redaction.Rules = .defaults
  private var buffering = false
  private var server: ReactotronServer?

  // MARK: State access

  func setServer(_ s: ReactotronServer) { lock.lock(); server = s; lock.unlock() }
  private func currentServer() -> ReactotronServer? { lock.lock(); defer { lock.unlock() }; return server }

  func setRules(_ r: Redaction.Rules) { lock.lock(); rules = r; lock.unlock() }
  private func currentRules() -> Redaction.Rules { lock.lock(); defer { lock.unlock() }; return rules }

  func setBuffering(_ on: Bool) {
    lock.lock()
    buffering = on
    if !on { commandBuffer.removeAll() }
    lock.unlock()
  }

  func buffer(_ command: Command) {
    lock.lock(); defer { lock.unlock() }
    guard buffering else { return }
    commandBuffer.append(command)
    if commandBuffer.count > Self.bufferSize { commandBuffer.removeFirst() }
  }

  private func snapshot() -> [Command] { lock.lock(); defer { lock.unlock() }; return commandBuffer }

  private func clearBufferReturningCount() -> Int {
    lock.lock(); defer { lock.unlock() }
    let count = commandBuffer.count
    commandBuffer.removeAll()
    return count
  }

  private func maxMessageId() -> Int {
    lock.lock(); defer { lock.unlock() }
    return commandBuffer.map(\.messageId).max() ?? 0
  }

  private func findResponse(type: String, clientId: String?, since: Int) -> Command? {
    lock.lock(); defer { lock.unlock() }
    return commandBuffer.first { $0.messageId > since && $0.type == type && $0.clientId == clientId }
  }

  private func redact(_ value: JSONValue, statePath: String = "") -> JSONValue {
    Redaction.redact(value, rules: currentRules(), currentPath: statePath)
  }

  // MARK: - HTTP entry

  func handle(method httpMethod: String, path: String, headers: [String: String], body: Data)
    -> (Int, [String: String], Data) {
    let cors = [
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Accept, mcp-session-id, mcp-protocol-version",
    ]
    func withCORS(_ base: [String: String]) -> [String: String] { base.merging(cors) { a, _ in a } }
    let jsonHeaders = ["Content-Type": "application/json"]

    let cleanPath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    guard cleanPath == "/mcp" else {
      return (404, withCORS([:]), Data("Not found".utf8))
    }

    switch httpMethod.uppercased() {
    case "OPTIONS":
      return (204, withCORS([:]), Data())
    case "GET":
      return (405, withCORS(jsonHeaders), errorEnvelope(code: -32000, message: "Method not allowed.", id: .null))
    case "DELETE":
      return (200, withCORS(jsonHeaders), Data())
    case "POST":
      let (status, data) = handlePost(body)
      return (status, withCORS(jsonHeaders), data)
    default:
      return (405, withCORS(jsonHeaders), errorEnvelope(code: -32000, message: "Method not allowed.", id: .null))
    }
  }

  private enum Outcome {
    case result(JSONValue)
    case failure(Int, String)
  }

  private func handlePost(_ body: Data) -> (Int, Data) {
    guard let json = JSONValue.parse(body), case .object(let obj) = json else {
      return (200, errorEnvelope(code: -32700, message: "Parse error", id: .null))
    }
    // No id → JSON-RPC notification (e.g. notifications/initialized) → 202.
    guard let id = obj["id"] else {
      return (202, Data())
    }
    guard let method = obj["method"]?.stringValue else {
      return (200, errorEnvelope(code: -32600, message: "Invalid Request", id: id))
    }
    let params = obj["params"]?.objectValue ?? [:]

    let outcome: Outcome
    switch method {
    case "initialize": outcome = .result(initializeResult(params))
    case "ping": outcome = .result(.object([:]))
    case "tools/list": outcome = .result(toolsList())
    case "tools/call": outcome = toolsCall(params)
    case "resources/list": outcome = .result(resourcesList())
    case "resources/templates/list": outcome = .result(resourcesTemplatesList())
    case "resources/read": outcome = resourcesRead(params)
    default: outcome = .failure(-32601, "Method not found")
    }

    switch outcome {
    case .result(let r): return (200, resultEnvelope(result: r, id: id))
    case .failure(let code, let message): return (200, errorEnvelope(code: code, message: message, id: id))
    }
  }

  private func resultEnvelope(result: JSONValue, id: JSONValue) -> Data {
    let env = JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    return Data((env.encodedString() ?? "{}").utf8)
  }

  private func errorEnvelope(code: Int, message: String, id: JSONValue) -> Data {
    let env = JSONValue.object([
      "jsonrpc": .string("2.0"), "id": id,
      "error": .object(["code": .number(Double(code)), "message": .string(message)]),
    ])
    return Data((env.encodedString() ?? "{}").utf8)
  }

  // MARK: - initialize

  // Port of `@modelcontextprotocol/sdk` Server._oninitialize (the SDK version
  // pinned by reactotron-mcp's package.json/yarn.lock, 1.27.1): echo the
  // client's requested protocolVersion only if it's one this server supports,
  // otherwise (unsupported or missing) respond with the latest version.
  private static let latestProtocolVersion = "2025-11-25"
  private static let supportedProtocolVersions: Set<String> = [
    "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07",
  ]

  private func initializeResult(_ params: [String: JSONValue]) -> JSONValue {
    let requested = params["protocolVersion"]?.stringValue
    let protocolVersion = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
      ?? Self.latestProtocolVersion
    // serverInfo mirrors mcp-server.ts's McpServer constructor.
    return .object([
      "protocolVersion": .string(protocolVersion),
      "capabilities": .object(["tools": .object([:]), "resources": .object([:])]),
      "serverInfo": .object(["name": .string("reactotron"), "version": .string("0.1.0")]),
    ])
  }

  // MARK: - tools/list

  private func toolsList() -> JSONValue {
    let clientIdDesc = "Target app clientId (required when multiple apps connected)."

    let tools: [JSONValue] = [
      tool(
        name: "dispatch_action",
        description: "Dispatch a Redux action to the connected app. Requires the Reactotron Redux plugin to be configured in the app. Example: { type: 'user/setName', payload: { name: 'Alice' } }",
        properties: [
          "actionType": strSchema("Action type, e.g. 'counter/increment' or 'RESET'"),
          "actionPayload": anySchema("Optional action payload, e.g. { name: 'Alice' }"),
          "clientId": strSchema("Target app clientId (required when multiple apps connected). Get from the apps resource."),
        ],
        required: ["actionType"]
      ),
      tool(
        name: "request_state",
        description: "Request a fresh state snapshot from the connected app. Requires Redux or MST plugin configured in the app. IMPORTANT: Always specify a path to avoid oversized responses. The full state tree can be millions of characters. Use request_state_keys first to explore the state shape, then request specific slices. Example path: 'user.profile' to get just that slice.",
        properties: [
          "path": strSchema("Dot-separated state path, e.g. 'user.profile'. STRONGLY RECOMMENDED — omitting this returns the full state tree which may be too large."),
          "clientId": strSchema(clientIdDesc),
        ],
        required: []
      ),
      tool(
        name: "request_state_keys",
        description: "List the keys at a state path without fetching values. Use this to explore the state tree structure before requesting specific slices with request_state. Returns an array of key names at the given path. Example: path='' returns root keys, path='user' returns keys under user.",
        properties: [
          "path": strSchema("Dot-separated state path. Omit or pass empty string for root keys."),
          "clientId": strSchema(clientIdDesc),
        ],
        required: []
      ),
      tool(
        name: "swap_state",
        description: "Replace the entire app state tree. WARNING: this is destructive and cannot be undone. Requires the Reactotron state plugin (Redux or MST). Use request_state first to get the current state, modify it, then swap.",
        properties: [
          "state": objectSchema(properties: [:], required: [], description: "The complete replacement state tree as a JSON object."),
          "clientId": strSchema(clientIdDesc),
        ],
        required: ["state"]
      ),
      tool(
        name: "send_custom_command",
        description: "Send a named custom command to the app. The app must have registered a handler for this command name. Use list_custom_commands first to see what commands are available. Example: command='showDebugOverlay', args={ enabled: true }",
        properties: [
          "command": strSchema("The custom command name, e.g. 'ping' or 'showDebugOverlay'"),
          "args": anySchema("Optional arguments to pass to the command handler"),
          "clientId": strSchema(clientIdDesc),
        ],
        required: ["command"]
      ),
      tool(
        name: "list_custom_commands",
        description: "List all custom commands registered by the connected app. These are commands the app has set up handlers for. Use this before send_custom_command to see what's available.",
        properties: ["clientId": strSchema(clientIdDesc)],
        required: []
      ),
      tool(
        name: "show_overlay",
        description: "Show an image overlay on top of the running app. Useful for comparing a design mockup against the actual UI. The app must have the overlay plugin enabled (it is by default in React Native). Pass uri=null or opacity=0 to hide the overlay.",
        properties: [
          "uri": nullableStrSchema("Image to display. Accepts a local file path (/path/to/image.png), file:// URI, http/https URL, or data: URI. Local files are automatically converted to base64. Pass null to clear the overlay."),
          "opacity": numSchema("Overlay opacity from 0 to 1 (default: 0.5)"),
          "growToWindow": boolSchema("Scale image to fill the entire window (default: false)"),
          "resizeMode": enumSchema(["cover", "contain", "stretch", "center"], "How to resize the image when growToWindow is true (default: cover)"),
          "width": numSchema("Image width in pixels (ignored if growToWindow is true)"),
          "height": numSchema("Image height in pixels (ignored if growToWindow is true)"),
          "marginTop": numSchema("Top margin offset in pixels"),
          "marginBottom": numSchema("Bottom margin offset in pixels"),
          "marginLeft": numSchema("Left margin offset in pixels"),
          "marginRight": numSchema("Right margin offset in pixels"),
          "justifyContent": enumSchema(["flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly"], "Vertical alignment of the overlay image (default: center)"),
          "alignItems": enumSchema(["flex-start", "flex-end", "center", "stretch", "baseline"], "Horizontal alignment of the overlay image (default: center)"),
          "showDebug": boolSchema("Show debug info overlay with current overlay settings (useful for positioning)"),
          "clientId": strSchema(clientIdDesc),
        ],
        required: ["uri"]
      ),
      tool(
        name: "clear_timeline",
        description: "Clear the MCP event buffer. This only affects what you see via MCP resources — the Reactotron desktop app's timeline is not affected. Useful to discard old events and focus on what happens next.",
        properties: [:],
        required: []
      ),
      tool(
        name: "subscribe_state",
        description: "Subscribe to a state path. The app will send state.values.change events whenever the value at this path changes. Read the state/subscriptions resource to see changes. Requires Redux or MST plugin. Example path: 'user.profile.name'",
        properties: ["path": strSchema("Dot-separated state path to subscribe to, e.g. 'user.profile' or 'cart.items'")],
        required: ["path"]
      ),
      tool(
        name: "unsubscribe_state",
        description: "Unsubscribe from a state path. Stops receiving change events for this path.",
        properties: ["path": strSchema("State path to unsubscribe from")],
        required: ["path"]
      ),
    ]
    return .object(["tools": .array(tools)])
  }

  private func tool(name: String, description: String, properties: [String: JSONValue], required: [String]) -> JSONValue {
    .object([
      "name": .string(name),
      "description": .string(description),
      "inputSchema": objectSchema(properties: properties, required: required),
    ])
  }

  // MARK: - tools/call

  private func toolsCall(_ params: [String: JSONValue]) -> Outcome {
    let name = params["name"]?.stringValue ?? ""
    let args = params["arguments"]?.objectValue ?? [:]
    switch name {
    case "dispatch_action": return .result(dispatchAction(args))
    case "request_state": return .result(requestState(args))
    case "request_state_keys": return .result(requestStateKeys(args))
    case "swap_state": return .result(swapState(args))
    case "send_custom_command": return .result(sendCustomCommand(args))
    case "list_custom_commands": return .result(listCustomCommands(args))
    case "show_overlay": return .result(showOverlay(args))
    case "clear_timeline": return .result(clearTimeline())
    case "subscribe_state": return .result(subscribeState(args))
    case "unsubscribe_state": return .result(unsubscribeState(args))
    default: return .failure(-32602, "Unknown tool: \(name)")
    }
  }

  /// Port of tools.ts `resolveClientId`.
  private func resolveClientId(_ requested: String?) -> (clientId: String?, error: String?) {
    guard let server = currentServer() else { return (nil, "No apps connected to Reactotron.") }
    let connections = server.connectionList
    if connections.isEmpty {
      return (nil, "No apps connected to Reactotron.")
    }
    if connections.count > 1, requested == nil {
      let apps = connections.map { "\($0.name ?? "") (\($0.platform)): \($0.clientId)" }.joined(separator: ", ")
      return (nil, "Multiple apps connected. Specify clientId. Available: \(apps)")
    }
    return (requested ?? connections.first?.clientId, nil)
  }

  /// Poll the buffer for a response command, matching tools.ts's 1500ms/100ms loop.
  private func waitForResponse(type: String, clientId: String?, since: Int) -> Command? {
    let deadline = Date().addingTimeInterval(Self.responseTimeout)
    while Date() < deadline {
      Thread.sleep(forTimeInterval: Self.pollInterval)
      if let cmd = findResponse(type: type, clientId: clientId, since: since) {
        return cmd
      }
    }
    return nil
  }

  private func dispatchAction(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("No apps connected to Reactotron.")])) }

    var actionObj: [String: JSONValue] = ["type": args["actionType"] ?? .string("")]
    if let payload = args["actionPayload"] { actionObj["payload"] = payload }
    let action = JSONValue.object(actionObj)

    let since = maxMessageId()
    server.send(type: "state.action.dispatch", payload: .object(["action": action]), clientId: clientId)

    if waitForResponse(type: "state.action.complete", clientId: clientId, since: since) != nil {
      return textResult(.object(["status": .string("dispatched"), "action": redact(action), "confirmed": .bool(true)]))
    }
    return textResult(.object([
      "status": .string("dispatched"),
      "action": redact(action),
      "confirmed": .bool(false),
      "note": .string("Action was sent but no confirmation received. The app may not have the Redux plugin configured."),
    ]))
  }

  private func requestState(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("No apps connected to Reactotron.")])) }

    let path = args["path"]?.stringValue ?? ""
    let since = maxMessageId()
    server.send(type: "state.values.request", payload: .object(["path": .string(path)]), clientId: clientId)

    if let cmd = waitForResponse(type: "state.values.response", clientId: clientId, since: since) {
      let stateValue = cmd.payload["value"] ?? cmd.payload
      let redactedState = redact(stateValue, statePath: path)
      return textResult(
        .object(["status": .string("success"), "state": redactedState]),
        guidance: "State response is too large. Use request_state with a more specific path (e.g. 'user.profile') to narrow the response. Use request_state_keys to explore the state shape."
      )
    }
    return textResult(.object([
      "status": .string("no_response"),
      "message": .string("The app did not respond to the state request. It likely doesn't have a state management plugin (Redux or MST) configured in Reactotron."),
    ]))
  }

  private func requestStateKeys(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("No apps connected to Reactotron.")])) }

    let path = args["path"]?.stringValue ?? ""
    let since = maxMessageId()
    server.send(type: "state.keys.request", payload: .object(["path": .string(path)]), clientId: clientId)

    if let cmd = waitForResponse(type: "state.keys.response", clientId: clientId, since: since) {
      return textResult(.object([
        "status": .string("success"),
        "path": cmd.payload["path"] ?? .string(path),
        "keys": cmd.payload["keys"] ?? .array([]),
        "valid": cmd.payload["valid"] ?? .bool(true),
      ]))
    }
    return textResult(.object([
      "status": .string("no_response"),
      "message": .string("The app did not respond to the keys request. It likely doesn't have a state management plugin (Redux or MST) configured in Reactotron."),
    ]))
  }

  private func swapState(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("No apps connected to Reactotron.")])) }

    server.send(type: "state.restore.request", payload: .object(["state": args["state"] ?? .object([:])]), clientId: clientId)
    return textResult(.object(["status": .string("swapped"), "message": .string("State replacement sent to app.")]))
  }

  private func sendCustomCommand(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("No apps connected to Reactotron.")])) }

    let command = args["command"]?.stringValue ?? ""
    var payload: [String: JSONValue] = ["command": .string(command)]
    if let a = args["args"] { payload["args"] = a }
    server.send(type: "custom", payload: .object(payload), clientId: clientId)
    return textResult(.object(["status": .string("sent"), "command": .string(command)]))
  }

  private func listCustomCommands(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer(), let clientId else {
      return textResult(.object(["status": .string("none"), "message": .string("No custom commands registered by the app.")]))
    }

    let commands = server.customCommandList(for: clientId).map { cc in
      JSONValue.object([
        "id": .number(Double(cc.id)),
        "command": .string(cc.command),
        "title": cc.title.map(JSONValue.string) ?? .null,
        "description": cc.description.map(JSONValue.string) ?? .null,
      ])
    }
    if commands.isEmpty {
      return textResult(.object(["status": .string("none"), "message": .string("No custom commands registered by the app.")]))
    }
    return textResult(.object(["status": .string("success"), "commands": .array(commands)]))
  }

  private func showOverlay(_ args: [String: JSONValue]) -> JSONValue {
    let (clientId, error) = resolveClientId(args["clientId"]?.stringValue)
    if let error { return textResult(.object(["status": .string("error"), "message": .string(error)])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("No apps connected to Reactotron.")])) }

    var payload = args
    payload.removeValue(forKey: "clientId")

    // Convert local file paths to data: URIs.
    if let uri = payload["uri"]?.stringValue, !uri.hasPrefix("data:"), !uri.hasPrefix("http") {
      let filePath = uri.hasPrefix("file://") ? String(uri.dropFirst("file://".count)) : uri
      let ext = (filePath as NSString).pathExtension.lowercased()
      let mimes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif"]
      guard let mime = mimes[ext] else {
        return textResult(.object(["status": .string("error"), "message": .string("Unsupported image format: .\(ext). Use PNG, JPEG, or GIF.")]))
      }
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
        return textResult(.object(["status": .string("error"), "message": .string("Could not read file: \(filePath)")]))
      }
      let maxSize = 2 * 1024 * 1024
      if data.count > maxSize {
        let mb = String(format: "%.1f", Double(data.count) / 1024 / 1024)
        return textResult(.object(["status": .string("error"), "message": .string("Image too large (\(mb)MB). Maximum is 2MB. Resize or compress the image first.")]))
      }
      payload["uri"] = .string("data:\(mime);base64,\(data.base64EncodedString())")
      if payload["width"] == nil || payload["height"] == nil, let size = imageSize(data) {
        if payload["width"] == nil { payload["width"] = .number(Double(size.width)) }
        if payload["height"] == nil { payload["height"] = .number(Double(size.height)) }
      }
    }

    // Defaults matching the desktop app's behavior.
    payload["opacity"] = payload["opacity"] ?? .number(0.5)
    payload["marginTop"] = payload["marginTop"] ?? .number(0)
    payload["marginRight"] = payload["marginRight"] ?? .number(0)
    payload["marginBottom"] = payload["marginBottom"] ?? .number(0)
    payload["marginLeft"] = payload["marginLeft"] ?? .number(0)
    payload["growToWindow"] = payload["growToWindow"] ?? .bool(false)
    payload["justifyContent"] = payload["justifyContent"] ?? .string("center")
    payload["alignItems"] = payload["alignItems"] ?? .string("center")

    let uriLen = payload["uri"]?.stringValue?.count ?? 0
    server.send(type: "overlay", payload: .object(payload), clientId: clientId)

    var echo = payload
    echo["uri"] = uriLen > 0 ? .string("(\(uriLen) chars)") : .null
    return textResult(.object(["status": .string("sent"), "overlay": .object(echo)]))
  }

  private func clearTimeline() -> JSONValue {
    let count = clearBufferReturningCount()
    return textResult(.object(["status": .string("cleared"), "eventsRemoved": .number(Double(count))]))
  }

  private func subscribeState(_ args: [String: JSONValue]) -> JSONValue {
    let path = args["path"]?.stringValue ?? ""
    if path.isEmpty { return textResult(.object(["status": .string("error"), "message": .string("path is required")])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("path is required")])) }

    server.stateValuesSubscribe(path: path)
    let active = server.subscriptions.map(JSONValue.string)
    return textResult(.object(["status": .string("subscribed"), "path": .string(path), "activeSubscriptions": .array(active)]))
  }

  private func unsubscribeState(_ args: [String: JSONValue]) -> JSONValue {
    let path = args["path"]?.stringValue ?? ""
    if path.isEmpty { return textResult(.object(["status": .string("error"), "message": .string("path is required")])) }
    guard let server = currentServer() else { return textResult(.object(["status": .string("error"), "message": .string("path is required")])) }

    server.stateValuesUnsubscribe(path: path)
    let active = server.subscriptions.map(JSONValue.string)
    return textResult(.object(["status": .string("unsubscribed"), "path": .string(path), "activeSubscriptions": .array(active)]))
  }

  // MARK: - resources

  private func resourcesList() -> JSONValue {
    .object(["resources": .array([
      resourceDescriptor(
        name: "timeline", uri: "reactotron://timeline",
        description: "Read this first to understand what's happening in the app. Returns summarized debug events (type, timestamp, and a short preview) newest-first. Payloads are stripped to keep the response small. Use the timeline_by_type resource template to get full event data filtered by type (e.g. reactotron://timeline/api.response)."
      ),
      resourceDescriptor(
        name: "state", uri: "reactotron://state/current",
        description: "Latest cached Redux/MST state snapshot. May be stale — use the request_state tool for a fresh snapshot. Returns no_state_received if the app hasn't sent state yet."
      ),
      resourceDescriptor(
        name: "network", uri: "reactotron://network/log",
        description: "Captured HTTP requests and responses. Each entry shows URL, method, status, duration, headers, and previews of request/response bodies (truncated to 500 chars). Use timeline_by_type with type 'api.response' for full request/response data."
      ),
    ])])
  }

  private func resourcesTemplatesList() -> JSONValue {
    .object(["resourceTemplates": .array([
      .object([
        "uriTemplate": .string("reactotron://timeline/{type}"),
        "name": .string("timeline_by_type"),
        "description": .string("Timeline events filtered by command type, with full payloads. Available types depend on what the app has sent (e.g. api.response, log, state.values.response, benchmark.report). Read the timeline resource first to see which types are present."),
        "mimeType": .string("application/json"),
      ]),
    ])])
  }

  private func resourceDescriptor(name: String, uri: String, description: String) -> JSONValue {
    .object([
      "uri": .string(uri),
      "name": .string(name),
      "description": .string(description),
      "mimeType": .string("application/json"),
    ])
  }

  private func resourcesRead(_ params: [String: JSONValue]) -> Outcome {
    guard let uri = params["uri"]?.stringValue else {
      return .failure(-32602, "Missing uri")
    }
    switch uri {
    case "reactotron://timeline":
      return .result(timelineResource(uri: uri))
    case "reactotron://state/current":
      return .result(stateResource(uri: uri))
    case "reactotron://network/log":
      return .result(networkResource(uri: uri))
    default:
      let prefix = "reactotron://timeline/"
      if uri.hasPrefix(prefix) {
        let rawType = String(uri.dropFirst(prefix.count))
        let type = rawType.removingPercentEncoding ?? rawType
        return .result(timelineByTypeResource(uri: uri, type: type))
      }
      return .failure(-32602, "Unknown resource: \(uri)")
    }
  }

  private func resourceContents(uri: String, data: JSONValue, guidance: String? = nil) -> JSONValue {
    .object(["contents": .array([.object([
      "uri": .string(uri),
      "mimeType": .string("application/json"),
      "text": .string(safeSerialize(data, guidance: guidance)),
    ])])])
  }

  private func timelineResource(uri: String) -> JSONValue {
    let events = filterByClient(snapshot())
    let summarized = events.reversed().map { redact(summarizeCommand($0)) }
    let data = JSONValue.object([
      "_meta": connectionMeta(),
      "eventCount": .number(Double(events.count)),
      "events": .array(summarized),
    ])
    return resourceContents(uri: uri, data: data,
      guidance: "Events are summarized. Use the timeline_by_type resource (e.g. reactotron://timeline/api.response) to get full payloads for a specific event type.")
  }

  private func timelineByTypeResource(uri: String, type: String) -> JSONValue {
    let events = filterByClient(snapshot()).filter { $0.type == type }
    let redactedEvents = events.reversed().map { redact(commandToJSON($0)) }
    let data = JSONValue.object([
      "_meta": connectionMeta(),
      "type": .string(type),
      "eventCount": .number(Double(events.count)),
      "events": .array(redactedEvents),
    ])
    return resourceContents(uri: uri, data: data,
      guidance: "Too many \(type) events to return in full. Try clear_timeline to reset, then reproduce the issue to capture fewer events.")
  }

  private func stateResource(uri: String) -> JSONValue {
    let stateCommands = filterByClient(snapshot().filter { $0.type == "state.values.response" })
    let latest = stateCommands.last
    let stateValue: JSONValue
    if let latest, let value = latest.payload["value"], !value.isNull {
      stateValue = value
    } else {
      stateValue = .object([
        "status": .string("no_state_received"),
        "message": .string("No state snapshot received yet. Use the request_state tool to request one."),
      ])
    }
    let statePath = latest?.payload["path"]?.stringValue ?? ""
    let data = JSONValue.object([
      "_meta": connectionMeta(),
      "state": redact(stateValue, statePath: statePath),
    ])
    return resourceContents(uri: uri, data: data,
      guidance: "State is too large. Use the request_state tool with a path like 'user.profile' to fetch a specific slice. Use request_state_keys to explore the state shape first.")
  }

  private func networkResource(uri: String) -> JSONValue {
    let networkCommands = filterByClient(snapshot().filter { $0.type == "api.response" })
    let entries = networkCommands.map { redact(summarizeNetworkEntry($0)) }
    let data = JSONValue.object([
      "_meta": connectionMeta(),
      "entries": .array(entries),
    ])
    return resourceContents(uri: uri, data: data,
      guidance: "Network log is too large. Use timeline_by_type with type 'api.response' for full data, or clear_timeline to reset and capture fewer events.")
  }

  // MARK: - resource helpers (connection meta / filtering / summarize)

  private func filterByClient(_ commands: [Command]) -> [Command] {
    guard let server = currentServer() else { return commands }
    let apps = server.connectionList
    if apps.count == 1 {
      let cid = apps[0].clientId
      return commands.filter { $0.clientId == cid }
    }
    return commands
  }

  private func connectionMeta() -> JSONValue {
    let apps = currentServer()?.connectionList ?? []
    if apps.isEmpty {
      return .object([
        "connection": .string("no_apps_connected"),
        "hint": .string("No apps are connected to Reactotron. Start your React Native / React app with Reactotron configured."),
      ])
    }
    if apps.count == 1 {
      let a = apps[0]
      return .object([
        "connection": .string("single_app"),
        "app": appInfo(a),
        "hint": .string("Connected to \(a.name ?? "") (\(a.platform)). All data is from this app."),
      ])
    }
    return .object([
      "connection": .string("multiple_apps"),
      "apps": .array(apps.map(appInfo)),
      "hint": .string("Multiple apps are connected. If the user hasn't specified which app, ask them. Then pass clientId to filter data. Check the workspace's package.json name to see if it matches one of these app names."),
    ])
  }

  private func appInfo(_ c: Connection) -> JSONValue {
    .object([
      "id": .number(Double(c.id)),
      "clientId": .string(c.clientId),
      "name": c.name.map(JSONValue.string) ?? .null,
      "platform": .string(c.platform),
      "platformVersion": c.platformVersion.map(JSONValue.string) ?? .null,
    ])
  }

  private func commandToJSON(_ c: Command) -> JSONValue {
    var o: [String: JSONValue] = [
      "type": .string(c.type),
      "connectionId": .number(Double(c.connectionId)),
      "messageId": .number(Double(c.messageId)),
      "date": .string(mcpISOString(c.date)),
      "deltaTime": .number(c.deltaTime),
      "important": .bool(c.important),
      "payload": c.payload,
    ]
    if let cid = c.clientId { o["clientId"] = .string(cid) }
    if let diff = c.diff { o["diff"] = diff }
    return .object(o)
  }

  // MARK: - serialization (serialization.ts)

  private func textResult(_ data: JSONValue, guidance: String? = nil) -> JSONValue {
    .object(["content": .array([.object(["type": .string("text"), "text": .string(safeSerialize(data, guidance: guidance))])])])
  }

  private func safeSerialize(_ data: JSONValue, guidance: String? = nil) -> String {
    truncate(compactJson(data), limit: 800_000, guidance: guidance)
  }

  private func truncate(_ text: String, limit: Int, guidance: String?) -> String {
    if text.count <= limit { return text }
    let k = Int((Double(text.count) / 1000).rounded())
    let suffix = guidance != nil
      ? "\n\n[TRUNCATED — response was ~\(k)K chars. \(guidance!)]"
      : "\n\n[TRUNCATED — response was ~\(k)K chars.]"
    return String(text.prefix(limit - suffix.count)) + suffix
  }

  private func compactJson(_ v: JSONValue) -> String { v.encodedString() ?? "" }

  private func numberString(_ d: Double) -> String {
    if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
    return String(d)
  }

  private func scalarString(_ v: JSONValue?) -> String? {
    switch v {
    case .string(let s): return s
    case .number(let n): return numberString(n)
    case .bool(let b): return b ? "true" : "false"
    default: return nil
    }
  }

  private func summarizeCommand(_ cmd: Command) -> JSONValue {
    let preview: String
    switch cmd.type {
    case "api.response": preview = apiResponsePreview(cmd.payload)
    case "log": preview = logPreview(cmd.payload)
    case "state.values.response": preview = "path: \(cmd.payload["path"]?.stringValue ?? "(root)")"
    case "state.values.change": preview = "\(cmd.payload["changes"]?.arrayValue?.count ?? 0) change(s)"
    case "state.action.complete": preview = cmd.payload["type"]?.stringValue ?? genericPreview(cmd.payload)
    case "benchmark.report": preview = cmd.payload["title"]?.stringValue ?? "benchmark"
    default: preview = genericPreview(cmd.payload)
    }
    return .object([
      "type": .string(cmd.type),
      "date": .string(mcpISOString(cmd.date)),
      "clientId": cmd.clientId.map(JSONValue.string) ?? .null,
      "messageId": .number(Double(cmd.messageId)),
      "deltaTime": .number(cmd.deltaTime),
      "important": .bool(cmd.important),
      "payloadPreview": .string(preview),
    ])
  }

  private func apiResponsePreview(_ payload: JSONValue) -> String {
    let method = payload["request"]?["method"]?.stringValue ?? "?"
    let url = payload["request"]?["url"]?.stringValue ?? "?"
    let status = scalarString(payload["response"]?["status"]) ?? "?"
    let duration: String
    if let d = payload["duration"], !d.isNull { duration = " (\(scalarString(d) ?? "")ms)" } else { duration = "" }
    return "\(method) \(url) -> \(status)\(duration)"
  }

  private func logPreview(_ payload: JSONValue) -> String {
    let level = payload["level"]?.stringValue ?? "log"
    var msg: String
    if let m = payload["message"]?.stringValue { msg = m } else { msg = compactJson(payload["message"] ?? .null) }
    if msg.count > 200 { msg = String(msg.prefix(200)) + "..." }
    return "[\(level)] \(msg)"
  }

  private func genericPreview(_ payload: JSONValue) -> String {
    if payload.isNull { return "" }
    let text = compactJson(payload)
    return text.count <= 200 ? text : String(text.prefix(200)) + "..."
  }

  private func summarizeNetworkEntry(_ cmd: Command) -> JSONValue {
    let p = cmd.payload
    let requestData: JSONValue
    if let d = p["request"]?["data"], !d.isNull { requestData = .string(truncateValue(d, 500)) } else { requestData = .null }

    let responseBody: JSONValue
    if let b = p["response"]?["body"] {
      if case .string(let s) = b {
        responseBody = .string(s.count > 500 ? String(s.prefix(500)) + "..." : s)
      } else if !b.isNull {
        responseBody = .string(truncateValue(b, 500))
      } else {
        responseBody = .null
      }
    } else {
      responseBody = .null
    }

    return .object([
      "messageId": .number(Double(cmd.messageId)),
      "clientId": cmd.clientId.map(JSONValue.string) ?? .null,
      "date": .string(mcpISOString(cmd.date)),
      "duration": p["duration"] ?? .null,
      "request": .object([
        "method": p["request"]?["method"] ?? .null,
        "url": p["request"]?["url"] ?? .null,
        "headers": p["request"]?["headers"] ?? .null,
        "data": requestData,
      ]),
      "response": .object([
        "status": p["response"]?["status"] ?? .null,
        "headers": p["response"]?["headers"] ?? .null,
        "body": responseBody,
      ]),
    ])
  }

  private func truncateValue(_ v: JSONValue, _ limit: Int) -> String {
    let text: String
    if case .string(let s) = v { text = s } else { text = compactJson(v) }
    return text.count <= limit ? text : String(text.prefix(limit)) + "..."
  }

  // MARK: - JSON Schema builders

  private func strSchema(_ desc: String) -> JSONValue { .object(["type": .string("string"), "description": .string(desc)]) }
  private func numSchema(_ desc: String) -> JSONValue { .object(["type": .string("number"), "description": .string(desc)]) }
  private func boolSchema(_ desc: String) -> JSONValue { .object(["type": .string("boolean"), "description": .string(desc)]) }
  private func anySchema(_ desc: String) -> JSONValue { .object(["description": .string(desc)]) }

  private func enumSchema(_ values: [String], _ desc: String) -> JSONValue {
    .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string)), "description": .string(desc)])
  }

  private func nullableStrSchema(_ desc: String) -> JSONValue {
    .object(["type": .array([.string("string"), .string("null")]), "description": .string(desc)])
  }

  private func objectSchema(properties: [String: JSONValue], required: [String], description: String? = nil) -> JSONValue {
    var o: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
    if !required.isEmpty { o["required"] = .array(required.map(JSONValue.string)) }
    if let description { o["description"] = .string(description) }
    return .object(o)
  }

  private func imageSize(_ data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = props[kCGImagePropertyPixelWidth] as? Int,
      let height = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
  }
}

/// ISO-8601 with fractional seconds — matches `JSON.stringify(new Date())`.
nonisolated(unsafe) private let mcpISOFormatter: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}()

private func mcpISOString(_ date: Date) -> String { mcpISOFormatter.string(from: date) }
