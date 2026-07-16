import XCTest
@testable import Reactotron

@MainActor
final class SessionStoreTests: XCTestCase {
  func conn(_ clientId: String, id: Int = 1) -> Connection {
    Connection(id: id, clientId: clientId, address: "127.0.0.1",
               intro: .object(["platform": .string("ios")]))
  }
  func cmd(_ type: String, clientId: String?, connectionId: Int = 1, msgId: Int = .random(in: 1...99999)) -> Command {
    Command(type: type, connectionId: connectionId, messageId: msgId, date: Date(),
            deltaTime: 0, important: false, payload: .object([:]), clientId: clientId, diff: nil)
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
}
