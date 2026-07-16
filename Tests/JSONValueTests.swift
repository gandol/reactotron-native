import XCTest
@testable import Reactotron

final class JSONValueTests: XCTestCase {
  func testDecodeRoundTrip() throws {
    let json = #"{"a":1,"b":"x","c":true,"d":null,"e":[1,2],"f":{"g":2.5}}"#
    let v = JSONValue.parse(Data(json.utf8))
    XCTAssertEqual(v?["a"], .number(1))
    XCTAssertEqual(v?["b"], .string("x"))
    XCTAssertEqual(v?["c"], .bool(true))
    XCTAssertEqual(v?["d"], .null)
    XCTAssertEqual(v?["e"]?[1], .number(2))
    XCTAssertEqual(v?["f"]?["g"], .number(2.5))
  }

  func testTruthiness() {
    XCTAssertFalse(JSONValue.null.isTruthy)
    XCTAssertFalse(JSONValue.bool(false).isTruthy)
    XCTAssertFalse(JSONValue.number(0).isTruthy)
    XCTAssertFalse(JSONValue.string("").isTruthy)
    XCTAssertTrue(JSONValue.string("x").isTruthy)
    XCTAssertTrue(JSONValue.object([:]).isTruthy)
  }

  func testEncodedStringIsValidJSON() {
    let v = JSONValue.object(["n": .number(.nan), "i": .number(.infinity), "s": .string("ok")])
    let s = v.encodedString()!
    XCTAssertNotNil(JSONValue.parse(Data(s.utf8)))
    XCTAssertTrue(s.contains(#""s":"ok""#))
  }
}
