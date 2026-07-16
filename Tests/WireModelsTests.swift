import XCTest
@testable import Reactotron

final class WireModelsTests: XCTestCase {
  func testDecodeWireMessage() throws {
    let json = #"{"type":"log","payload":{"level":"debug","message":"hi"},"important":true,"deltaTime":12,"date":"2026-07-16T10:00:00.000Z"}"#
    let m = try JSONDecoder().decode(WireMessage.self, from: Data(json.utf8))
    XCTAssertEqual(m.type, "log")
    XCTAssertEqual(m.payload?["message"], .string("hi"))
    XCTAssertEqual(m.important?.isTruthy, true)
    XCTAssertEqual(m.deltaTime, 12)
  }

  func testDecodeWireMessageMinimal() throws {
    let m = try JSONDecoder().decode(WireMessage.self, from: Data(#"{"type":"clear"}"#.utf8))
    XCTAssertEqual(m.type, "clear")
    XCTAssertNil(m.payload)
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
