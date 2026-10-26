import XCTest
import Network
@testable import Reactotron

/// Raw NWConnection WebSocket client for tests that need to emit control frames
/// (e.g. a `.pong`) that URLSessionWebSocketTask hides. Used to reproduce the
/// keepalive-pong drop bug faithfully.
final class RawWSClient: @unchecked Sendable {
  private let conn: NWConnection

  init(port: UInt16) {
    let params = NWParameters.tcp
    let ws = NWProtocolWebSocket.Options()
    ws.autoReplyPing = true
    params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
    conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: params)
  }

  func connect() async {
    await withCheckedContinuation { cont in
      conn.stateUpdateHandler = { [weak conn] state in
        if case .ready = state {
          conn?.stateUpdateHandler = nil  // resume exactly once
          cont.resume()
        }
      }
      conn.start(queue: .global())
    }
  }

  private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
    let meta = NWProtocolWebSocket.Metadata(opcode: opcode)
    let ctx = NWConnection.ContentContext(identifier: "send", metadata: [meta])
    conn.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
  }

  func sendText(_ text: String) { send(Data(text.utf8), opcode: .text) }
  func sendPong() { send(Data(), opcode: .pong) }
  func close() { conn.cancel() }
}

/// Test helper: connect, optionally intro, collect received messages.
final class TestClient {
  let task: URLSessionWebSocketTask
  init(port: UInt16) {
    task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
    task.resume()
  }
  func send(_ json: String) async throws { try await task.send(.string(json)) }
  func receive() async throws -> String {
    if case .string(let s) = try await task.receive() { return s }
    throw URLError(.badServerResponse)
  }
  func close() { task.cancel(with: .normalClosure, reason: nil) }
}

/// Mutable box for pulling a value out of an `@Sendable` event closure into
/// the test body. The closures below are only ever written before, and read
/// after, their paired `fulfillment(of:)` await, so this is safe in practice;
/// `@unchecked Sendable` is needed only because the compiler can't see that
/// happens-before relationship through an XCTestExpectation.
private final class Box<T>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}

final class ReactotronServerTests: XCTestCase {
  var server: ReactotronServer!
  var port: UInt16!

  override func setUp() {
    server = ReactotronServer()
    port = UInt16.random(in: 20_000...40_000)
  }
  override func tearDown() { server.stop() }

  func start() async {
    await start(on: port)
  }

  func start(on testPort: UInt16) async {
    await withCheckedContinuation { cont in
      server.events.started = { cont.resume() }
      server.start(port: testPort)
    }
  }

  func testIntroWithoutClientIdGetsSetClientId() async throws {
    await start()
    let established = expectation(description: "established")
    server.events.connectionEstablished = { conn in
      XCTAssertEqual(conn.intro["name"]?.stringValue, "TestApp")
      XCTAssertFalse(conn.clientId.isEmpty)
      established.fulfill()
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"name":"TestApp","platform":"ios"}}"#)
    var reply = try await client.receive()
    // A newly-accepted connection also gets a `state.values.subscribe` broadcast
    // (current subscriptions, possibly empty) as soon as it's accepted, matching
    // reactotron-core-server.ts's unconditional stateValuesSendSubscriptions()
    // call on every "connection" event — it can race ahead of setClientId.
    if !reply.contains("setClientId") {
      reply = try await client.receive()
    }
    XCTAssertTrue(reply.contains("setClientId"))
    await fulfillment(of: [established], timeout: 5)
    client.close()
  }

  func testCommandEventCarriesRepairedPayloadAndIds() async throws {
    await start()
    let got = expectation(description: "log command")
    server.events.command = { cmd in
      guard cmd.type == "log" else { return }  // client.intro fires first
      XCTAssertEqual(cmd.payload["message"], .null)  // "~~~ null ~~~" repaired
      XCTAssertEqual(cmd.clientId, "fixed-client-id")
      XCTAssertTrue(cmd.important)
      got.fulfill()
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"fixed-client-id"}}"#)
    try await client.send(#"{"type":"log","important":true,"payload":{"message":"~~~ null ~~~"}}"#)
    await fulfillment(of: [got], timeout: 5)
    client.close()
  }

  func testDuplicateClientIdClosesOldSocket() async throws {
    await start()
    let c1 = TestClient(port: port)
    try await c1.send(#"{"type":"client.intro","payload":{"clientId":"dup"}}"#)
    try await Task.sleep(for: .milliseconds(200))
    let c2 = TestClient(port: port)
    try await c2.send(#"{"type":"client.intro","payload":{"clientId":"dup"}}"#)
    try await Task.sleep(for: .seconds(1))  // old socket closed after the 500 ms defer
    do {
      try await c1.send(#"{"type":"log","payload":{}}"#)
      // c1 has buffered `state.values.subscribe` broadcasts from its own
      // accept and from c2's accept (see accept()'s sendSubscriptions() call)
      // — drain those before the real closure surfaces as an error.
      for _ in 0..<5 {
        _ = try await c1.receive()
      }
      XCTFail("old socket should be closed")
    } catch { /* expected */ }
    c2.close()
  }

  func testBroadcastAndTargetedSend() async throws {
    await start()
    let c1 = TestClient(port: port)
    try await c1.send(#"{"type":"client.intro","payload":{"clientId":"one"}}"#)
    try await Task.sleep(for: .milliseconds(300))
    server.send(type: "state.values.subscribe", payload: .object(["paths": .array([])]), clientId: "one")
    let msg = try await c1.receive()
    XCTAssertTrue(msg.contains("state.values.subscribe"))
    c1.close()
  }

  func testPortUnavailable() async throws {
    await start()
    let second = ReactotronServer()
    let unavailable = expectation(description: "portUnavailable")
    let expectedPort = port!
    second.events.portUnavailable = { p in
      XCTAssertEqual(p, expectedPort); unavailable.fulfill()
    }
    second.start(port: port)
    await fulfillment(of: [unavailable], timeout: 5)
    second.stop()
  }

  func testCustomCommandRegistration() async throws {
    await start()
    let registered = expectation(description: "register")
    server.events.command = { cmd in
      if cmd.type == "customCommand.register" { registered.fulfill() }
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"cc"}}"#)
    try await client.send(#"{"type":"customCommand.register","payload":{"id":1,"command":"go_home","title":"Go Home"}}"#)
    await fulfillment(of: [registered], timeout: 5)
    client.close()
  }

  /// Regression: a client's pong (its automatic reply to the server's keepalive
  /// ping) must NOT tear down the connection. A pong arrives at the server's
  /// receive loop as a control frame with data == nil; an earlier bug treated
  /// that as a disconnect and cancelled the socket, dropping every connected
  /// client roughly once per keepalive interval.
  ///
  /// URLSessionWebSocketTask never surfaces this path, so this uses a raw
  /// NWConnection client that sends an explicit `.pong` frame — exactly what a
  /// browser / React Native client emits in response to the server's ping.
  func testPongFrameDoesNotDropConnection() async throws {
    await start()
    let logReceived = expectation(description: "log received after a pong frame")
    server.events.command = { cmd in
      if cmd.type == "log" { logReceived.fulfill() }
    }

    let client = RawWSClient(port: port)
    await client.connect()
    client.sendText(#"{"type":"client.intro","payload":{"clientId":"pong-test"}}"#)
    // Emulate the client's automatic pong reply to the server's keepalive ping.
    client.sendPong()
    // If the pong dropped the connection, this log never reaches the server.
    client.sendText(#"{"type":"log","payload":{"level":"debug","message":"alive after pong"}}"#)

    await fulfillment(of: [logReceived], timeout: 5)
    client.close()
  }

  func testNewConnectionReceivesCurrentSubscriptions() async throws {
    await start()
    let c1 = TestClient(port: port)
    try await c1.send(#"{"type":"client.intro","payload":{"clientId":"sub-origin"}}"#)
    try await c1.send(#"{"type":"state.values.change","payload":{"changes":[{"path":"foo"},{"path":"bar"}]}}"#)
    try await Task.sleep(for: .milliseconds(300))  // let the server update subscriptions
    let c2 = TestClient(port: port)
    // The new connection is broadcast the current subscriptions immediately upon accept.
    let msg = try await c2.receive()
    XCTAssertTrue(msg.contains("state.values.subscribe"))
    XCTAssertTrue(msg.contains("foo"))
    XCTAssertTrue(msg.contains("bar"))
    c1.close()
    c2.close()
  }

  func testStateBackupResponseSetsNameToNull() async throws {
    await start()
    let got = expectation(description: "backup response command")
    server.events.command = { cmd in
      guard cmd.type == "state.backup.response" else { return }
      XCTAssertEqual(cmd.payload["name"], .null)
      got.fulfill()
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"backup-test"}}"#)
    try await client.send(#"{"type":"state.backup.response","payload":{"state":{"foo":"bar"}}}"#)
    await fulfillment(of: [got], timeout: 5)
    client.close()
  }

  func testConnectionIdsNotReusedAcrossRestart() async throws {
    await start()

    let firstId = Box<Int?>(nil)
    let firstConnected = expectation(description: "first connect")
    server.events.connect = { partial in
      firstId.value = partial.id
      firstConnected.fulfill()
    }
    let c1 = TestClient(port: port)
    await fulfillment(of: [firstConnected], timeout: 5)
    c1.close()

    server.stop()
    // Restart on a fresh port rather than the same one: rebinding the exact
    // same port immediately after stop() races the OS's own socket teardown
    // (even with allowLocalEndpointReuse) and can hang the listener in
    // `.waiting` indefinitely — that's a kernel-timing flake unrelated to
    // what this test is verifying (that connectionId survives stop()). A
    // distinct port sidesteps that race entirely.
    var restartPort = UInt16.random(in: 20_000...40_000)
    while restartPort == port { restartPort = UInt16.random(in: 20_000...40_000) }
    await start(on: restartPort)

    let secondId = Box<Int?>(nil)
    let secondConnected = expectation(description: "second connect")
    server.events.connect = { partial in
      secondId.value = partial.id
      secondConnected.fulfill()
    }
    let c2 = TestClient(port: restartPort)
    await fulfillment(of: [secondConnected], timeout: 5)
    c2.close()

    let unwrappedFirst = try XCTUnwrap(firstId.value)
    let unwrappedSecond = try XCTUnwrap(secondId.value)
    XCTAssertGreaterThan(unwrappedSecond, unwrappedFirst)
  }
}
