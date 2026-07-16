import XCTest
@testable import Reactotron

// MARK: - TimelineRowModel.resolve() TDD tests
//
// Payload shapes below are taken from the reference *.story.tsx fixtures in
// reactotron-core-ui/src/timelineCommands/**/*.story.tsx and the
// reactotron-core-contract payload interfaces, not guessed.

final class TimelineRowModelTests: XCTestCase {

  // MARK: - client.intro (ClientIntroCommand.story.tsx: payload: { name: "Test?" })

  func testClientIntroTitleAndPreview() {
    let cmd = makeCommand(type: "client.intro", payload: .object([
      "name": .string("MyApp"),
      "platform": .string("ios"),
      "platformVersion": .string("16.0"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "CONNECTION")
    XCTAssertEqual(model.preview, "MyApp")
    XCTAssertEqual(model.titleColor, .clear)
  }

  func testClientIntroMissingName() {
    let cmd = makeCommand(type: "client.intro", payload: .object([:]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "CONNECTION")
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - log (debug) — getLevelName("debug") === "DEBUG"

  func testLogDebugTitle() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .string("hello world"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DEBUG")
    XCTAssertEqual(model.preview, "hello world")
    XCTAssertEqual(model.titleColor, .clear)
  }

  func testLogStringMessageNotTruncatedAtNewline() {
    // Source's getPreview does `message.slice(0, 500)` with no first-line
    // splitting — multi-line strings are NOT cut at the first \n.
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .string("line1\nline2\nline3"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "line1\nline2\nline3")
  }

  func testLogLongStringMessageSlicedTo500() {
    let long = String(repeating: "x", count: 600)
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .string(long),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview.count, 500)
  }

  func testLogDebugEmptyMessage() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DEBUG")
    XCTAssertEqual(model.preview, "")
  }

  func testLogNullMessage() {
    // getPreview: `if (message === null) return "null"`.
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .null,
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "null")
  }

  func testLogDebugObjectMessage() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .object(["key": .string("val")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DEBUG")
    XCTAssertTrue(model.preview.contains("key"))
    XCTAssertTrue(model.preview.contains("val"))
  }

  func testLogObjectMessageCapsAtFiveKeys() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .object([
        "a": .number(1), "b": .number(2), "c": .number(3),
        "d": .number(4), "e": .number(5), "f": .number(6),
      ]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertTrue(model.preview.contains("…"), "expected truncation marker for >5 keys")
  }

  func testLogArrayMessage() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("debug"),
      "message": .array([.number(1), .number(2)]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "[ 1, 2 ]")
  }

  // MARK: - log (warn) — getLevelName("warn") === "WARNING"

  func testLogWarnTitleAndColor() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("warn"),
      "message": .string("careful!"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "WARNING")
    XCTAssertEqual(model.preview, "careful!")
    XCTAssertEqual(model.titleColor, Theme.warning)
  }

  // MARK: - log (error) — getLevelName("error") === "ERROR"

  func testLogErrorTitleAndColor() {
    let cmd = makeCommand(type: "log", payload: .object([
      "level": .string("error"),
      "message": .string("boom!"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "ERROR")
    XCTAssertEqual(model.preview, "boom!")
    XCTAssertEqual(model.titleColor, Theme.tag)
  }

  func testLogUnrecognizedLevelFallsBackToLOG() {
    // getLevelName's default branch — LogPayload only ever carries
    // debug/warn/error, but an unrecognized/missing level must not crash.
    let cmd = makeCommand(type: "log", payload: .object([
      "message": .string("info msg"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "LOG")
  }

  // MARK: - api.response (ApiResponsePayload: { request: {method,url,data}, response: {status}, duration })

  func testApiResponsePreview() {
    let cmd = makeCommand(type: "api.response", payload: .object([
      "request": .object([
        "method": .string("get"),
        "url": .string("https://api.example.com/users/1?token=abc"),
        "data": .null,
      ]),
      "response": .object(["status": .number(200)]),
      "duration": .number(150),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "API RESPONSE")
    // Method uppercased, query string stripped, no status/duration in preview.
    XCTAssertEqual(model.preview, "GET /users/1")
  }

  func testApiResponseMissingRequest() {
    let cmd = makeCommand(type: "api.response", payload: .null)
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "API RESPONSE")
    XCTAssertEqual(model.preview, "")
  }

  func testApiResponseGraphQLOperationName() {
    let cmd = makeCommand(type: "api.response", payload: .object([
      "request": .object([
        "method": .string("post"),
        "url": .string("https://api.example.com/graphql"),
        "data": .string(#"{"operationName":"LaunchList","variables":{}}"#),
      ]),
      "response": .object(["status": .number(200)]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "POST /graphql LaunchList")
  }

  // MARK: - state.action.complete (payload: { name, action, ms, diff? })

  func testStateActionTitleFromName() {
    let cmd = makeCommand(type: "state.action.complete", payload: .object([
      "name": .string("LOGIN_SUCCESS"),
      "action": .object(["type": .string("LOGIN_SUCCESS")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "ACTION")
    XCTAssertEqual(model.preview, "LOGIN_SUCCESS")
  }

  func testStateActionMissingName() {
    let cmd = makeCommand(type: "state.action.complete", payload: .null)
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "ACTION")
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - state.values.change — title "SUBSCRIPTIONS", "N changed N added N removed"

  func testStateValuesChangePreview() {
    let cmd = makeCommand(type: "state.values.change", payload: .object([
      "changed": .object(["counter": .number(5)]),
      "added": .object(["flag": .bool(true), "name": .string("x")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "SUBSCRIPTIONS")
    XCTAssertEqual(model.preview, "1 changed 2 added")
  }

  func testStateValuesChangeRemovedOnly() {
    let cmd = makeCommand(type: "state.values.change", payload: .object([
      "removed": .object(["old": .null]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "1 removed")
  }

  func testStateValuesChangeAllThreeInOrder() {
    let cmd = makeCommand(type: "state.values.change", payload: .object([
      "changed": .object(["a": .number(1)]),
      "added": .object(["b": .number(2)]),
      "removed": .object(["c": .number(3)]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "1 changed 1 added 1 removed")
  }

  func testStateValuesChangeArrayValuesExcluded() {
    // Source: hasX = !!payload.x && !Array.isArray(payload.x) — the default
    // story fixture passes [] for all three, none of which should count.
    let cmd = makeCommand(type: "state.values.change", payload: .object([
      "added": .array([]),
      "changed": .array([]),
      "removed": .array([]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "SUBSCRIPTIONS")
    XCTAssertEqual(model.preview, "")
  }

  func testStateValuesChangeEmptyPayload() {
    let cmd = makeCommand(type: "state.values.change", payload: .object([:]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - state.values.response — preview is ALWAYS "" in source

  func testStateValuesResponsePreviewAlwaysEmpty() {
    let cmd = makeCommand(type: "state.values.response", payload: .object([
      "path": .string("userReducer"),
      "value": .object(["counter": .number(5)]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "STATE")
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - state.keys.response — preview is ALWAYS "" in source

  func testStateKeysResponsePreviewAlwaysEmpty() {
    let cmd = makeCommand(type: "state.keys.response", payload: .object([
      "keys": .array([.string("dummyReducer"), .string("anotherReducer")]),
      "path": .string("dummyReducer"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "STATE KEYS")
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - state.backup.response (snapshot) — not in timelineCommandResolver; resolver still has a sane default

  func testStateBackupResponse() {
    let cmd = makeCommand(type: "state.backup.response", payload: .object([
      "data": .object(["key": .string("val")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "SNAPSHOT")
    XCTAssertEqual(model.preview, "Snapshot")
  }

  // MARK: - asyncStorage.mutation (matches source exactly, no fix needed)

  func testAsyncStorageMutationSetItem() {
    let cmd = makeCommand(type: "asyncStorage.mutation", payload: .object([
      "action": .string("setItem"),
      "data": .object(["key": .string("MyKey"), "value": .string("MyValue")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "ASYNC STORAGE")
    XCTAssertEqual(model.preview, "setItem: MyKey")
  }

  func testAsyncStorageMutationRemoveItem() {
    let cmd = makeCommand(type: "asyncStorage.mutation", payload: .object([
      "action": .string("removeItem"),
      "data": .object(["key": .string("token")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "removeItem: token")
  }

  func testAsyncStorageMutationMergeItem() {
    let cmd = makeCommand(type: "asyncStorage.mutation", payload: .object([
      "action": .string("mergeItem"),
      "data": .object(["key": .string("settings")]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "mergeItem: settings")
  }

  func testAsyncStorageMutationOtherAction() {
    let cmd = makeCommand(type: "asyncStorage.mutation", payload: .object([
      "action": .string("clear"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "clear")
  }

  // MARK: - saga.task.complete

  func testSagaTaskComplete() {
    let cmd = makeCommand(type: "saga.task.complete", payload: .object([
      "triggerType": .string("TAKE"),
      "description": .string("watchUserSaga"),
      "duration": .number(42),
      "children": .array([]),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "SAGA")
    XCTAssertEqual(model.preview, "TAKE in 42ms")
  }

  // MARK: - benchmark.report

  func testBenchmarkReport() {
    // Step times are milliseconds (BenchmarkStep, story fixture uses the
    // same scale, e.g. { time: 1009 }) — 3000ms total -> "3.000s".
    let steps: JSONValue = .array([
      .object(["title": .string("start"), "time": .number(0), "delta": .number(0)]),
      .object(["title": .string("step1"), "time": .number(1500), "delta": .number(1500)]),
      .object(["title": .string("step2"), "time": .number(3000), "delta": .number(1500)]),
    ])
    let cmd = makeCommand(type: "benchmark.report", payload: .object([
      "title": .string("Fetch Users"),
      "steps": steps,
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "BENCHMARK")
    XCTAssertEqual(model.preview, "Fetch Users in 3.000s")
  }

  // MARK: - display

  func testDisplayCustomName() {
    let cmd = makeCommand(type: "display", payload: .object([
      "name": .string("Custom Panel"),
      "preview": .string("A Preview!"),
      "value": .number(10),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "Custom Panel")
    XCTAssertEqual(model.preview, "A Preview!")
  }

  func testDisplayNoName() {
    let cmd = makeCommand(type: "display", payload: .object([
      "preview": .string("No name panel"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DISPLAY")
    XCTAssertEqual(model.preview, "No name panel")
  }

  func testDisplayEmptyStringNameFallsBackToDISPLAY() {
    // Source: `payload.name || "DISPLAY"` — JS `||` treats "" as falsy too.
    let cmd = makeCommand(type: "display", payload: .object([
      "name": .string(""),
      "preview": .string("x"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DISPLAY")
  }

  func testDisplayEmptyPayload() {
    let cmd = makeCommand(type: "display", payload: .null)
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DISPLAY")
  }

  // MARK: - image (preview is `payload.preview`, NOT `payload.uri`)

  func testImageCommandPreviewIsPreviewFieldNotUri() {
    let cmd = makeCommand(type: "image", payload: .object([
      "uri": .string("https://example.com/img.png"),
      "preview": .string("Test"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "IMAGE")
    XCTAssertEqual(model.preview, "Test")
  }

  func testImageCommandNoPreview() {
    let cmd = makeCommand(type: "image", payload: .object(["uri": .string("https://x/y.png")]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "IMAGE")
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - customCommand.register / unregister — falls back to display-style resolution

  func testCustomCommandRegisterFallsBack() {
    let cmd = makeCommand(type: "customCommand.register", payload: .object([
      "command": .string("myCmd"),
      "name": .string("myCmd"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "myCmd")
  }

  func testCustomCommandUnregisterFallsBack() {
    let cmd = makeCommand(type: "customCommand.unregister", payload: .object([
      "name": .string("myOtherCmd"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "myOtherCmd")
  }

  // MARK: - unknown type

  func testUnknownTypeFallsBack() {
    let cmd = makeCommand(type: "some.unknown.type", payload: .object([
      "name": .string("Mystery"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "some.unknown.type")
    XCTAssertEqual(model.preview, "")
  }

  func testEmptyTypeFallsBack() {
    let cmd = makeCommand(type: "", payload: .null)
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "")
    XCTAssertEqual(model.preview, "")
  }

  // MARK: - malformed payload safety

  func testNullPayloadDoesNotCrash() {
    let cmd = makeCommand(type: "log", payload: .null)
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "LOG")
  }

  func testArrayPayloadDoesNotCrash() {
    let cmd = makeCommand(type: "display", payload: .array([.number(1), .number(2)]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DISPLAY")
  }

  func testStringPayloadDoesNotCrash() {
    let cmd = makeCommand(type: "display", payload: .string("raw string"))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "DISPLAY")
  }

  func testApiResponseStringPayloadDoesNotCrash() {
    let cmd = makeCommand(type: "api.response", payload: .string("not an object"))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.title, "API RESPONSE")
    XCTAssertEqual(model.preview, "")
  }

  func testStateValuesChangeMalformedBucketDoesNotCrash() {
    // "changed" truthy but not an object (a string) — must not force-unwrap.
    let cmd = makeCommand(type: "state.values.change", payload: .object([
      "changed": .string("not an object"),
    ]))
    let model = TimelineRowModel.resolve(cmd)
    XCTAssertEqual(model.preview, "0 changed")
  }

  // MARK: - Helpers

  private func makeCommand(type: String, payload: JSONValue) -> Command {
    Command(
      type: type,
      connectionId: 0,
      messageId: 1,
      date: Date(),
      deltaTime: 0,
      important: false,
      payload: payload,
      clientId: nil,
      diff: nil
    )
  }
}
