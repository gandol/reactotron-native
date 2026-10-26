import XCTest
@testable import Reactotron

final class WireModelsTests: XCTestCase {
  func testDecodeWireMessage() throws {
    let json = #"{"type":"log","payload":{"level":"debug","message":"hi"},"important":true,"deltaTime":12,"date":"2026-07-16T10:00:00.000Z"}"#
    let m = try XCTUnwrap(WireMessage(data: Data(json.utf8)))
    XCTAssertEqual(m.type, "log")
    XCTAssertEqual(m.payload?["message"], .string("hi"))
    XCTAssertEqual(m.important?.isTruthy, true)
    XCTAssertEqual(m.deltaTime, 12)
  }

  func testDecodeWireMessageMinimal() throws {
    let m = try XCTUnwrap(WireMessage(data: Data(#"{"type":"clear"}"#.utf8)))
    XCTAssertEqual(m.type, "clear")
    XCTAssertNil(m.payload)
  }

  /// `WireMessage(data:)` drops exactly the frames the former synthesized
  /// `Decodable` rejected.
  func testWireMessageAcceptanceRules() {
    func msg(_ s: String) -> WireMessage? { WireMessage(data: Data(s.utf8)) }
    XCTAssertNil(msg(#"{"type":"log","deltaTime":"12"}"#))
    XCTAssertNil(msg(#"{"payload":{}}"#))
    XCTAssertNil(msg(#"{"type":5}"#))
    XCTAssertNil(msg(#"{"type":null}"#))
    XCTAssertNil(msg(#"{"type":"log","date":5}"#))
    XCTAssertNil(msg(#"["type","log"]"#))
    XCTAssertNil(msg(#"{"type":"log"} trailing"#))

    let nullDate = msg(#"{"type":"log","date":null,"deltaTime":null}"#)
    XCTAssertNotNil(nullDate)
    XCTAssertNil(nullDate?.date)
    XCTAssertNil(nullDate?.deltaTime)

    let nulls = msg(#"{"type":"log","payload":null,"important":null,"diff":null,"extra":[1]}"#)
    XCTAssertNil(nulls?.payload)
    XCTAssertNil(nulls?.important)
    XCTAssertNil(nulls?.diff)

    let anyJSON = msg(#"{"type":"x","payload":"s","important":1,"diff":[1]}"#)
    XCTAssertEqual(anyJSON?.payload, .string("s"))
    XCTAssertEqual(anyJSON?.important?.isTruthy, true)
    XCTAssertEqual(anyJSON?.diff, .array([.number(1)]))

    XCTAssertEqual(msg(#"{"type":"a","type":"b"}"#)?.type, "b")
  }

  func testWireMessagePayloadKeepsKeyOrder() {
    let m = WireMessage(data: Data(#"{"payload":{"z":1,"a":2},"type":"log"}"#.utf8))
    XCTAssertEqual(m?.payload?.objectValue?.keys, ["z", "a"])
  }

  func testParseCommandDate() {
    XCTAssertEqual(
      parseCommandDate("2026-07-16T10:00:00.000Z").timeIntervalSince1970,
      1_784_196_000, accuracy: 1)
    XCTAssertEqual(
      parseCommandDate("2026-07-16T10:00:00Z").timeIntervalSince1970,
      1_784_196_000, accuracy: 1)
    // invalid → now
    XCTAssertEqual(parseCommandDate("garbage").timeIntervalSinceNow, 0, accuracy: 5)
    XCTAssertEqual(parseCommandDate(nil).timeIntervalSinceNow, 0, accuracy: 5)
  }

  func testConnectionAccessors() {
    let c = Connection(
      id: 1, clientId: "abc", address: "127.0.0.1",
      intro: .object(["platform": .string("ios"), "name": .string("MyApp")]))
    XCTAssertEqual(c.platform, "ios")
    XCTAssertEqual(c.name, "MyApp")
    XCTAssertNil(c.platformVersion)
  }
}
