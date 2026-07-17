import XCTest
@testable import Reactotron

/// Integration tests against the real HTTP surface: a `McpServer` bound to
/// `127.0.0.1:<random port>` via `MinimalHTTPServer`, driven with
/// `URLSession` exactly as an MCP client would. Port of the JSON-RPC dispatch
/// tests specified by Task 15 (protocol handshake, tools/list, tools/call,
/// resources/read, and the JSON-RPC error paths).
final class McpServerTests: XCTestCase {
  var mcp: McpServer!
  var reactotronServer: ReactotronServer!
  var port: UInt16!

  override func setUp() async throws {
    let server = ReactotronServer()
    let testPort = UInt16.random(in: 20_000...40_000)
    reactotronServer = server
    port = testPort
    mcp = await MainActor.run {
      let m = McpServer()
      m.attach(server: server)
      m.start(port: Int(testPort))
      return m
    }
  }

  override func tearDown() async throws {
    let m = mcp!
    let server = reactotronServer!
    await MainActor.run { m.stop() }
    server.stop()
  }

  // MARK: - HTTP helpers

  private func postMcp(_ body: JSONValue) async throws -> (status: Int, json: JSONValue) {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port!)/mcp")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data((body.encodedString() ?? "{}").utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = response as! HTTPURLResponse
    return (http.statusCode, JSONValue.parse(data) ?? .null)
  }

  private func rpc(id: Int = 1, method: String, params: JSONValue = .object([:])) -> JSONValue {
    .object(["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method), "params": params])
  }

  /// Unwraps a `tools/call`/`resources/read` text payload (itself a
  /// JSON-encoded string, per `safeSerialize`) into a `JSONValue`.
  private func toolText(_ json: JSONValue) -> JSONValue? {
    guard let text = json["result"]?["content"]?[0]?["text"]?.stringValue else { return nil }
    return JSONValue.parse(Data(text.utf8))
  }

  private func resourceText(_ json: JSONValue) -> JSONValue? {
    guard let text = json["result"]?["contents"]?[0]?["text"]?.stringValue else { return nil }
    return JSONValue.parse(Data(text.utf8))
  }

  // MARK: - initialize

  func testInitializeReturnsProtocolVersionAndServerInfo() async throws {
    let (status, json) = try await postMcp(rpc(method: "initialize", params: .object([
      "protocolVersion": .string("2025-06-18"),
      "capabilities": .object([:]),
      "clientInfo": .object(["name": .string("xctest"), "version": .string("1.0")]),
    ])))
    XCTAssertEqual(status, 200)
    // A supported version is echoed back verbatim (matches the pinned SDK's
    // Server._oninitialize negotiation).
    XCTAssertEqual(json["result"]?["protocolVersion"]?.stringValue, "2025-06-18")
    XCTAssertEqual(json["result"]?["serverInfo"]?["name"]?.stringValue, "reactotron")
    XCTAssertEqual(json["result"]?["serverInfo"]?["version"]?.stringValue, "0.1.0")
    XCTAssertNotNil(json["result"]?["capabilities"]?["tools"])
    XCTAssertNotNil(json["result"]?["capabilities"]?["resources"])
  }

  func testInitializeWithUnsupportedVersionReturnsLatestSupported() async throws {
    let (_, json) = try await postMcp(rpc(method: "initialize", params: .object([
      "protocolVersion": .string("1999-01-01"),
    ])))
    XCTAssertEqual(json["result"]?["protocolVersion"]?.stringValue, "2025-11-25")
  }

  // MARK: - tools/list

  func testToolsListReturns10Tools() async throws {
    let (status, json) = try await postMcp(rpc(method: "tools/list"))
    XCTAssertEqual(status, 200)
    let tools = json["result"]?["tools"]?.arrayValue ?? []
    XCTAssertEqual(tools.count, 10)
    let names = Set(tools.compactMap { $0["name"]?.stringValue })
    XCTAssertEqual(names, [
      "dispatch_action", "request_state", "request_state_keys", "swap_state",
      "send_custom_command", "list_custom_commands", "show_overlay",
      "clear_timeline", "subscribe_state", "unsubscribe_state",
    ])
  }

  // MARK: - tools/call

  func testToolsCallClearTimelineSucceeds() async throws {
    let (status, json) = try await postMcp(rpc(method: "tools/call", params: .object([
      "name": .string("clear_timeline"), "arguments": .object([:]),
    ])))
    XCTAssertEqual(status, 200)
    XCTAssertEqual(toolText(json)?["status"]?.stringValue, "cleared")
  }

  func testToolsCallListCustomCommandsReturnsRegisteredCommands() async throws {
    let wsPort = UInt16.random(in: 40_001...50_000)
    await withCheckedContinuation { cont in
      reactotronServer.events.started = { cont.resume() }
      reactotronServer.start(port: wsPort)
    }

    let registered = expectation(description: "customCommand.register")
    reactotronServer.events.command = { cmd in
      if cmd.type == "customCommand.register" { registered.fulfill() }
    }
    let client = TestClient(port: wsPort)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"cc-test"}}"#)
    try await client.send(#"{"type":"customCommand.register","payload":{"id":1,"command":"go_home","title":"Go Home"}}"#)
    await fulfillment(of: [registered], timeout: 5)

    let (status, json) = try await postMcp(rpc(method: "tools/call", params: .object([
      "name": .string("list_custom_commands"),
      "arguments": .object(["clientId": .string("cc-test")]),
    ])))
    XCTAssertEqual(status, 200)
    let result = toolText(json)
    XCTAssertEqual(result?["status"]?.stringValue, "success")
    let commands = result?["commands"]?.arrayValue ?? []
    XCTAssertEqual(commands.count, 1)
    XCTAssertEqual(commands.first?["command"]?.stringValue, "go_home")
    XCTAssertEqual(commands.first?["title"]?.stringValue, "Go Home")

    client.close()
  }

  // MARK: - resources/read

  func testResourcesReadTimelineReturnsBufferedAndRedactedEvents() async throws {
    let command = Command(
      type: "custom.event",
      connectionId: 1,
      messageId: 1,
      date: Date(),
      deltaTime: 0,
      important: false,
      payload: .object(["password": .string("hunter2"), "note": .string("ok")]),
      clientId: nil,
      diff: nil
    )
    let m = mcp!
    await MainActor.run { m.buffer(command) }

    let (status, json) = try await postMcp(rpc(method: "resources/read", params: .object([
      "uri": .string("reactotron://timeline"),
    ])))
    XCTAssertEqual(status, 200)
    let data = resourceText(json)
    XCTAssertEqual(data?["eventCount"]?.numberValue, 1)
    let events = data?["events"]?.arrayValue ?? []
    XCTAssertEqual(events.count, 1)
    let preview = events.first?["payloadPreview"]?.stringValue ?? ""
    XCTAssertTrue(preview.contains("[REDACTED]"), "expected redaction marker in: \(preview)")
    XCTAssertFalse(preview.contains("hunter2"), "raw secret leaked in: \(preview)")
  }

  // MARK: - JSON-RPC error paths

  func testUnknownMethodReturnsMethodNotFound() async throws {
    let (status, json) = try await postMcp(rpc(method: "totally/bogus/method"))
    XCTAssertEqual(status, 200)
    XCTAssertEqual(json["error"]?["code"]?.numberValue, -32601)
  }

  func testMalformedJSONReturnsParseError() async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port!)/mcp")!)
    request.httpMethod = "POST"
    request.httpBody = Data("{not valid json".utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = response as! HTTPURLResponse
    XCTAssertEqual(http.statusCode, 200)
    let json = JSONValue.parse(data)
    XCTAssertEqual(json?["error"]?["code"]?.numberValue, -32700)
  }

  // MARK: - HTTP verbs

  func testGetIsMethodNotAllowed() async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port!)/mcp")!)
    request.httpMethod = "GET"
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 405)
  }

  func testDeleteReturns200() async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port!)/mcp")!)
    request.httpMethod = "DELETE"
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }
}
