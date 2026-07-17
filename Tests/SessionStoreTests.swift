import XCTest
@testable import Reactotron

@MainActor
final class SessionStoreTests: XCTestCase {
  func conn(_ clientId: String, id: Int = 1) -> Connection {
    Connection(id: id, clientId: clientId, address: "127.0.0.1",
               intro: .object(["platform": .string("ios")]))
  }
  func cmd(
    _ type: String, clientId: String?, connectionId: Int = 1,
    msgId: Int = .random(in: 1...99999), payload: JSONValue = .object([:])
  ) -> Command {
    Command(type: type, connectionId: connectionId, messageId: msgId, date: Date(),
            deltaTime: 0, important: false, payload: payload, clientId: clientId, diff: nil)
  }

  /// Builds a `customCommand.register` payload matching
  /// `reactotron-core-contract`'s `CustomCommandRegisterPayload`.
  func registerPayload(
    id: Int, command: String, title: String? = nil, description: String? = nil,
    args: [(name: String, type: String)] = []
  ) -> JSONValue {
    var obj: [String: JSONValue] = ["id": .number(Double(id)), "command": .string(command)]
    if let title { obj["title"] = .string(title) }
    if let description { obj["description"] = .string(description) }
    if !args.isEmpty {
      obj["args"] = .array(args.map { .object(["name": .string($0.name), "type": .string($0.type)]) })
    }
    return .object(obj)
  }

  func testAutoSelectsSingleConnection() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    XCTAssertEqual(s.selectedClientId, "a")
    XCTAssertEqual(s.serverStatus, .started)
    s.connectionEstablished(conn("b", id: 2))
    XCTAssertEqual(s.selectedClientId, "a")  // stays — auto-select only when exactly 1
  }

  func testReconnectMarksConnected() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    s.connectionDisconnected(conn("a"))
    XCTAssertEqual(s.connections.first?.connected, false)
    XCTAssertNil(s.selectedClientId)
    s.connectionEstablished(conn("a", id: 3))
    XCTAssertEqual(s.connections.count, 1)
    XCTAssertEqual(s.connections.first?.connected, true)
    XCTAssertEqual(s.selectedClientId, "a")
  }

  func testOrphanedCommandsAttachOnEstablish() {
    let s = SessionStore()
    s.commandReceived(cmd("log", clientId: nil, connectionId: 7))
    s.connectionEstablished(conn("a", id: 7))
    XCTAssertEqual(s.connections.first?.commands.count, 1)
  }

  func testCommandsPrependAndTrim() {
    let s = SessionStore()
    s.commandHistoryLimit = 3
    s.connectionEstablished(conn("a"))
    for i in 1...5 { s.commandReceived(cmd("log", clientId: "a", msgId: i)) }
    let cmds = s.connections.first!.commands
    XCTAssertEqual(cmds.count, 3)
    XCTAssertEqual(cmds.map(\.messageId), [5, 4, 3])  // newest first
  }

  func testClearOnlySelected() {
    let s = SessionStore()
    s.connectionEstablished(conn("a", id: 1))
    s.connectionEstablished(conn("b", id: 2))
    s.commandReceived(cmd("log", clientId: "a", connectionId: 1))
    s.commandReceived(cmd("log", clientId: "b", connectionId: 2))
    s.selectConnection("a")
    s.clearSelectedConnectionCommands()
    XCTAssertEqual(s.connections.first { $0.clientId == "a" }!.commands.count, 0)
    XCTAssertEqual(s.connections.first { $0.clientId == "b" }!.commands.count, 1)
  }

  func testDisconnectSelectedFallsBackToFirstConnected() {
    let s = SessionStore()
    s.connectionEstablished(conn("a", id: 1))
    s.connectionEstablished(conn("b", id: 2))
    s.selectConnection("b")
    s.connectionDisconnected(conn("b", id: 2))
    XCTAssertEqual(s.selectedClientId, "a")
  }

  // MARK: - Custom command registry

  func testCustomCommandRegisterAppendsToSelectedConnection() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    let payload = registerPayload(
      id: 1, command: "doThing", title: "Do Thing", description: "does a thing",
      args: [(name: "arg1", type: "string")]
    )
    s.commandReceived(cmd("customCommand.register", clientId: "a", payload: payload))

    let ccs = s.selectedConnection?.customCommands
    XCTAssertEqual(ccs?.count, 1)
    XCTAssertEqual(ccs?.first?.id, 1)
    XCTAssertEqual(ccs?.first?.command, "doThing")
    XCTAssertEqual(ccs?.first?.title, "Do Thing")
    XCTAssertEqual(ccs?.first?.description, "does a thing")
    XCTAssertEqual(ccs?.first?.args, [CustomCommandArg(name: "arg1", type: "string")])

    // Existing prepend/trim logic is untouched — the register command also
    // lands in the ordinary command timeline.
    XCTAssertEqual(s.selectedConnection?.commands.count, 1)
    XCTAssertEqual(s.selectedConnection?.commands.first?.type, "customCommand.register")
  }

  func testCustomCommandUnregisterRemovesById() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    s.commandReceived(cmd("customCommand.register", clientId: "a", payload: registerPayload(id: 1, command: "a")))
    s.commandReceived(cmd("customCommand.register", clientId: "a", payload: registerPayload(id: 2, command: "b")))
    XCTAssertEqual(s.selectedConnection?.customCommands.count, 2)

    s.commandReceived(cmd(
      "customCommand.unregister", clientId: "a",
      payload: .object(["id": .number(1), "command": .string("a")])
    ))
    XCTAssertEqual(s.selectedConnection?.customCommands.map(\.id), [2])
  }

  /// `reactotron-core-server.ts`'s `customCommand.register` handler does an
  /// unconditional `list.push(...)` — no id-based dedup — so re-registering
  /// the same id produces two entries. Source governs over the shorthand
  /// "dedupe by id" phrasing in the task brief.
  func testDuplicateCustomCommandRegisterAppendsPerSource() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    let payload = registerPayload(id: 1, command: "dup")
    s.commandReceived(cmd("customCommand.register", clientId: "a", payload: payload))
    s.commandReceived(cmd("customCommand.register", clientId: "a", payload: payload))
    XCTAssertEqual(s.selectedConnection?.customCommands.count, 2)
  }

  /// Mirrors the server's `socket.on("close", ...)` handler, which does
  /// `this.customCommands.delete(clientId)` — the registry (not the command
  /// timeline, which is deliberately kept) is cleared on disconnect.
  func testDisconnectClearsCustomCommandsButKeepsTimeline() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    s.commandReceived(cmd("customCommand.register", clientId: "a", payload: registerPayload(id: 1, command: "a")))
    XCTAssertEqual(s.connections.first?.customCommands.count, 1)

    s.connectionDisconnected(conn("a"))
    XCTAssertEqual(s.connections.first?.customCommands.count, 0)
    XCTAssertEqual(s.connections.first?.commands.count, 1)
  }

  func testCustomCommandRegisterWithUnknownClientIdIsDropped() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    s.commandReceived(cmd("customCommand.register", clientId: "unknown", payload: registerPayload(id: 1, command: "a")))
    XCTAssertEqual(s.selectedConnection?.customCommands.count, 0)
  }
}
