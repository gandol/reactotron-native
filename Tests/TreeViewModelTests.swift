import XCTest
@testable import Reactotron

// MARK: - treePreview tests

final class TreeViewModelTests: XCTestCase {

  // MARK: Object preview

  func testObjectPreview_showsKeyColonEllipsis_truncated() {
    let obj: JSONValue = .object([
      "name": .string("Alice"),
      "age": .number(30),
      "city": .string("Berlin"),
    ])
    let result = treePreview(obj)
    // Keys are sorted alphabetically; 3 keys fits within the cap
    XCTAssertEqual(result, "{age: …, city: …, name: …}")
  }

  func testObjectPreview_cappedAt3Keys_withEllipsis() {
    let obj: JSONValue = .object([
      "a": .number(1),
      "b": .number(2),
      "c": .number(3),
      "d": .number(4),
      "e": .number(5),
    ])
    let result = treePreview(obj)
    XCTAssertEqual(result, "{a: …, b: …, c: …, …}")
  }

  func testObjectPreview_exactly3Keys_noTrailingEllipsis() {
    let obj: JSONValue = .object([
      "x": .null,
      "y": .null,
      "z": .null,
    ])
    let result = treePreview(obj)
    XCTAssertEqual(result, "{x: …, y: …, z: …}")
  }

  func testObjectPreview_singleKey() {
    let obj: JSONValue = .object(["x": .number(1)])
    let result = treePreview(obj)
    XCTAssertEqual(result, "{x: …}")
  }

  func testObjectPreview_empty() {
    let obj: JSONValue = .object([:])
    let result = treePreview(obj)
    XCTAssertEqual(result, "{}")
  }

  // MARK: Array preview

  func testArrayPreview_showsItemCount() {
    let arr: JSONValue = .array([.null, .bool(true), .string("hi")])
    let result = treePreview(arr)
    XCTAssertEqual(result, "3 items")
  }

  func testArrayPreview_empty() {
    let arr: JSONValue = .array([])
    let result = treePreview(arr)
    XCTAssertEqual(result, "0 items")
  }

  func testArrayPreview_singleItem() {
    let arr: JSONValue = .array([.number(42)])
    let result = treePreview(arr)
    XCTAssertEqual(result, "1 item")
  }

  // MARK: Scalar previews

  func testStringPreview_quoted() {
    let result = treePreview(.string("hello"))
    XCTAssertEqual(result, "\"hello\"")
  }

  func testStringPreview_empty() {
    let result = treePreview(.string(""))
    XCTAssertEqual(result, "\"\"")
  }

  func testNullPreview() {
    let result = treePreview(.null)
    XCTAssertEqual(result, "null")
  }

  func testBoolPreview_true() {
    let result = treePreview(.bool(true))
    XCTAssertEqual(result, "true")
  }

  func testBoolPreview_false() {
    let result = treePreview(.bool(false))
    XCTAssertEqual(result, "false")
  }

  func testNumberPreview_integer() {
    let result = treePreview(.number(42))
    XCTAssertEqual(result, "42")
  }

  func testNumberPreview_float() {
    let result = treePreview(.number(3.14))
    XCTAssertEqual(result, "3.14")
  }

  func testNumberPreview_nan() {
    let result = treePreview(.number(Double.nan))
    XCTAssertEqual(result, "NaN")
  }
}
