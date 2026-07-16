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
}
