import XCTest
@testable import Reactotron

// MARK: - filterCommands TDD tests
//
// Exact port of `reactotron-core-ui/src/utils/filterCommands/index.ts`, verified
// against its co-located `filterCommands.test.ts`. Payloads below mirror the real
// shapes in `reactotron-core-contract` (`LogPayload`, `ApiResponsePayload`,
// `ClientIntroPayload`) rather than synthetic placeholders.

final class FilterCommandsTests: XCTestCase {

  private func makeCommand(
    type: String, messageId: Int, payload: JSONValue = .object([:])
  ) -> Command {
    Command(
      type: type,
      connectionId: 0,
      messageId: messageId,
      date: Date(),
      deltaTime: 0,
      important: false,
      payload: payload,
      clientId: nil,
      diff: nil
    )
  }

  // MARK: - search matches payload message

  func testSearchMatchesPayloadMessage() {
    let logCommand = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["level": .string("warn"), "message": .string("Fetching user profile")])
    )
    let otherCommand = makeCommand(
      type: "log", messageId: 2,
      payload: .object(["level": .string("debug"), "message": .string("Unrelated line")])
    )

    let result = filterCommands([logCommand, otherCommand], search: "user profile", hidden: [])

    XCTAssertEqual(result.map(\.messageId), [1])
  }

  // MARK: - search matches type name

  func testSearchMatchesTypeName() {
    let apiCommand = makeCommand(
      type: "api.response", messageId: 1,
      payload: .object([
        "duration": .number(120),
        "request": .object(["url": .string("https://example.com/users"), "method": .string("GET")]),
        "response": .object(["status": .number(200)]),
      ])
    )
    let logCommand = makeCommand(
      type: "log", messageId: 2,
      payload: .object(["level": .string("debug"), "message": .string("hello")])
    )

    let result = filterCommands([apiCommand, logCommand], search: "api.response", hidden: [])

    XCTAssertEqual(result.map(\.messageId), [1])
  }

  // MARK: - hidden types excluded

  func testHiddenTypesExcluded() {
    let logCommand = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["level": .string("debug"), "message": .string("hello")])
    )
    let clientIntroCommand = makeCommand(
      type: "client.intro", messageId: 2,
      payload: .object(["name": .string("MyApp")])
    )

    let result = filterCommands(
      [logCommand, clientIntroCommand], search: "", hidden: ["log"]
    )

    XCTAssertEqual(result.map(\.messageId), [2])
  }

  // MARK: - empty search returns all minus hidden

  func testEmptySearchReturnsAllMinusHidden() {
    let logCommand = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["level": .string("debug"), "message": .string("hello")])
    )
    let apiCommand = makeCommand(
      type: "api.response", messageId: 2,
      payload: .object([
        "duration": .number(10),
        "request": .object(["url": .string("https://example.com")]),
      ])
    )
    let clientIntroCommand = makeCommand(
      type: "client.intro", messageId: 3,
      payload: .object(["name": .string("MyApp")])
    )

    let result = filterCommands(
      [logCommand, apiCommand, clientIntroCommand], search: "", hidden: ["client.intro"]
    )

    XCTAssertEqual(result.map(\.messageId), [1, 2])
  }

  // MARK: - additional parity cases, mirroring filterCommands.test.ts

  func testSearchIsCaseInsensitiveAgainstPayloadPreview() {
    let displayCommand = makeCommand(
      type: "display", messageId: 1,
      payload: .object(["name": .string("State"), "preview": .string("REDUX ACTION")])
    )

    let result = filterCommands([displayCommand], search: "redux", hidden: [])

    XCTAssertEqual(result.map(\.messageId), [1])
  }

  func testLogMatchesLiteralSeverityWordRegardlessOfPayload() {
    // Exact port quirk from the reference: for `log` commands, filterSearch also
    // matches when the *search term itself* matches the literal words "debug",
    // "warning", or "error" — independent of what the payload actually contains.
    let logCommand = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["level": .string("debug"), "message": .string("nothing matches here")])
    )

    let result = filterCommands([logCommand], search: "debug", hidden: [])

    XCTAssertEqual(result.map(\.messageId), [1])
  }

  func testNoMatchReturnsEmpty() {
    let logCommand = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["level": .string("debug"), "message": .string("hello world")])
    )

    let result = filterCommands([logCommand], search: "zzz-no-match-zzz", hidden: [])

    XCTAssertEqual(result, [])
  }

  // MARK: - Upstream TESTS table (filterCommands.test.ts)
  //
  // Port of `TEST_COMMANDS` + `TESTS`; each command's messageId is its index in
  // the source fixture, so expected results are listed as indices.

  private static let requestDataString =
    #"{"operationName":"SEARCHDATA","variables":{"testing":{"nested":"thing"}},"query":"query LaunchList {\n  launches {\n    id\n }\n}\n"}"#

  private var upstreamFixture: [Command] {
    let fixture: [(String, JSONValue)] = [
      ("SEARCHTYPE", .object([:])),
      ("ADUMMYOBJ", .object(["message": .string("SEARCHMESSAGE")])),
      ("ADUMMYOBJ", .object(["preview": .string("SEARCHPREVIEW")])),
      ("ADUMMYOBJ", .object(["name": .string("SEARCHNAME")])),
      ("ADUMMYOBJ", .object(["path": .string("SEARCHPATH")])),
      ("ADUMMYOBJ", .object(["triggerType": .string("SEARCHTRIGGERTYPE")])),
      ("ADUMMYOBJ", .object(["description": .string("SEARCHDESCRIPTION")])),
      ("ADUMMYOBJ", .object(["request": .object(["url": .string("SEARCHURL")])])),
      ("REGEX", .object(["message": .string("[1234] Log text")])),
      ("REGEX", .object(["message": .string("123 Log text")])),
      ("REGEX", .object(["message": .string("Log text (123)")])),
      ("log", .object(["debug": .string("LOGDEBUG")])),
      ("client.intro", .object(["connection": .string("SEARCHCONNECTION")])),
      ("ADUMMYOBJ", .object(["request": .object(["data": .string(Self.requestDataString)])])),
    ]
    return fixture.enumerated().map { makeCommand(type: $1.0, messageId: $0, payload: $1.1) }
  }

  private static let upstreamTests: [(name: String, search: String, result: [Int])] = [
    ("type", "SEARCHTYPE", [0]),
    ("payload.message", "SEARCHMESSAGE", [1]),
    ("payload.preview", "SEARCHPREVIEW", [2]),
    ("payload.name", "SEARCHNAME", [3]),
    ("payload.path", "SEARCHPATH", [4]),
    ("payload.triggerType", "SEARCHTRIGGERTYPE", [5]),
    ("payload.description", "SEARCHDESCRIPTION", [6]),
    ("payload.request.url", "SEARCHURL", [7]),
    ("payload.request.data", "SEARCHDATA", [13]),
    ("log => debug", "debug", [11]),
    ("log => warning", "warning", [11]),
    ("log => error", "error", [11]),
    ("clientIntro => connection", "connection", [12]),
    ("multiple results", "ADUMMYOBJ", [1, 2, 3, 4, 5, 6, 7, 13]),
    ("deep search results", "SEARCH", [0, 1, 2, 3, 4, 5, 6, 7, 13]),
    ("deep search results - even deeper", "ME", [1, 3, 13]),
    ("deep search results - case insensitive", "me", [1, 3, 13]),
    ("deep search results - type case insensitive", "myobj", [1, 2, 3, 4, 5, 6, 7, 13]),
    ("search that results in a invalid regex", "[123", [8]),
    ("another search that results in a invalid regex", "123)", [10]),
  ]

  func testUpstreamTableFilterSearch() {
    let commands = upstreamFixture
    for test in Self.upstreamTests {
      XCTAssertEqual(
        filterSearch(commands, search: test.search).map(\.messageId), test.result, test.name
      )
    }
  }

  func testUpstreamTableFilterCommands() {
    let commands = upstreamFixture
    for test in Self.upstreamTests {
      XCTAssertEqual(
        filterCommands(commands, search: test.search, hidden: []).map(\.messageId), test.result,
        test.name
      )
    }
  }

  func testUpstreamFilterHiddenDropsOnlyListedTypes() {
    let commands = upstreamFixture
    let expected = commands.filter { $0.type != "client.intro" }.map(\.messageId)
    XCTAssertEqual(filterHidden(commands, hidden: ["client.intro"]).map(\.messageId), expected)
    XCTAssertEqual(
      filterCommands(commands, search: "", hidden: ["client.intro"]).map(\.messageId), expected
    )
  }

  /// `JSON.stringify` leaves `/` unescaped, so a slash search must hit an
  /// object-valued `payload.message`.
  func testSlashSearchMatchesObjectValuedMessage() {
    let command = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["message": .object(["path": .string("/users/1")])])
    )
    XCTAssertEqual(filterSearch([command], search: "/users").map(\.messageId), [1])
  }

  /// `JSON.stringify` writes keys in insertion order, so a search spanning two
  /// adjacent keys matches only in the order the client sent them.
  func testSearchSpanningAdjacentKeysFollowsWireOrder() throws {
    let message = try XCTUnwrap(JSONValue.parse(Data(#"{"b":2,"a":1}"#.utf8)))
    let command = makeCommand(type: "log", messageId: 1, payload: .object(["message": message]))
    XCTAssertEqual(filterSearch([command], search: #""b":2,"a""#).map(\.messageId), [1])
    XCTAssertEqual(filterSearch([command], search: #""a":1,"b""#).map(\.messageId), [])

    let literal = makeCommand(
      type: "log", messageId: 2,
      payload: .object(["message": .object(["y": .string("1"), "x": .string("2")])]))
    XCTAssertEqual(filterSearch([literal], search: #""y":"1","x""#).map(\.messageId), [2])
  }

  /// Numbers are spelled like JS `Number::toString` (`1e-7`, not `1e-07`).
  func testSearchUsesJSNumberSpelling() {
    let command = makeCommand(
      type: "log", messageId: 1,
      payload: .object(["message": .object(["x": .number(1e-7), "big": .number(1e16)])]))
    XCTAssertEqual(filterSearch([command], search: #""x":1e-7"#).map(\.messageId), [1])
    XCTAssertEqual(filterSearch([command], search: "10000000000000000").map(\.messageId), [1])
    XCTAssertEqual(filterSearch([command], search: "1e-07").map(\.messageId), [])
  }
}
