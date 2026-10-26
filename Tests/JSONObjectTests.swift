import XCTest
@testable import Reactotron

/// `JSONObject` — the insertion-ordered stand-in for a JS object.
final class JSONObjectTests: XCTestCase {
  func testLiteralKeepsOrder() {
    let o: JSONObject = ["zeta": .number(1), "alpha": .number(2), "mid": .number(3)]
    XCTAssertEqual(o.keys, ["zeta", "alpha", "mid"])
    XCTAssertEqual(o.values, [.number(1), .number(2), .number(3)])
  }

  func testDuplicateLiteralKeyLastWinsAtFirstPosition() {
    let o: JSONObject = ["a": .number(1), "b": .number(2), "a": .number(3)]
    XCTAssertEqual(o.keys, ["a", "b"])
    XCTAssertEqual(o["a"], .number(3))
  }

  func testSubscriptSetReplacesInPlaceAppendsAndRemoves() {
    var o: JSONObject = ["a": .number(1), "b": .number(2)]
    o["a"] = .number(10)
    XCTAssertEqual(o.keys, ["a", "b"])
    XCTAssertEqual(o["a"], .number(10))
    o["c"] = .number(3)
    XCTAssertEqual(o.keys, ["a", "b", "c"])
    o["a"] = nil
    XCTAssertEqual(o.keys, ["b", "c"])
    XCTAssertNil(o["a"])
    XCTAssertEqual(o.removeValue(forKey: "b"), .number(2))
    XCTAssertNil(o.removeValue(forKey: "missing"))
    XCTAssertEqual(o.keys, ["c"])
  }

  func testEqualityIsOrderInsensitive() {
    XCTAssertEqual(["a": .number(1), "b": .number(2)] as JSONObject, ["b": .number(2), "a": .number(1)] as JSONObject)
    XCTAssertNotEqual(["a": .number(1), "b": .number(2)] as JSONObject, ["a": .number(1), "b": .number(3)] as JSONObject)
    XCTAssertNotEqual(["a": .number(1)] as JSONObject, ["a": .number(1), "b": .number(2)] as JSONObject)
    XCTAssertNotEqual(["a": .number(1), "b": .number(2)] as JSONObject, ["a": .number(1), "c": .number(2)] as JSONObject)
    XCTAssertEqual(JSONValue.object(["x": .object(["p": .number(1), "q": .number(2)])]), .object(["x": .object(["q": .number(2), "p": .number(1)])]))
  }

  func testEqualityAboveIndexThreshold() {
    let keys = (0..<40).map { "k\($0)" }
    let forward = JSONObject(uniqueKeysWithValues: keys.map { ($0, JSONValue.string($0)) })
    let backward = JSONObject(uniqueKeysWithValues: keys.reversed().map { ($0, JSONValue.string($0)) })
    XCTAssertEqual(forward, backward)
    var changed = backward
    changed["k7"] = .null
    XCTAssertNotEqual(forward, changed)
  }

  func testMapValuesKeepsOrder() {
    let o: JSONObject = ["z": .number(1), "a": .number(2)]
    let doubled = o.mapValues { .number(($0.numberValue ?? 0) * 2) }
    XCTAssertEqual(doubled.keys, ["z", "a"])
    XCTAssertEqual(doubled["a"], .number(4))
  }

  func testIterationUsesDictionaryLabels() {
    let o: JSONObject = ["x": .string("1"), "y": .string("2")]
    var seen: [String] = []
    for (key, value) in o { seen.append("\(key)=\(value.stringValue ?? "")") }
    XCTAssertEqual(seen, ["x=1", "y=2"])
    XCTAssertEqual(o.map { $0.key }, ["x", "y"])
    XCTAssertEqual(o.sorted { $0.key > $1.key }.map(\.value), [.string("2"), .string("1")])
  }
}
