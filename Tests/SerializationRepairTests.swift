import XCTest
@testable import Reactotron

final class SerializationRepairTests: XCTestCase {
  func testSentinelReplacements() {
    let input: JSONValue = .object([
      "u": .string("~~~ undefined ~~~"),
      "n": .string("~~~ null ~~~"),
      "f": .string("~~~ false ~~~"),
      "z": .string("~~~ zero ~~~"),
      "e": .string("~~~ empty string ~~~"),
      "fn": .string("~~~ anonymous function ~~~"),
      "keep": .string("hello"),
    ])
    let out = SerializationRepair.repair(input)
    XCTAssertEqual(out["u"], .null)
    XCTAssertEqual(out["n"], .null)
    XCTAssertEqual(out["f"], .bool(false))
    XCTAssertEqual(out["z"], .number(0))
    XCTAssertEqual(out["e"], .string(""))
    XCTAssertEqual(out["fn"], .string("fn()"))
    XCTAssertEqual(out["keep"], .string("hello"))
  }

  func testNamedFunctionSentinelStripsTildes() {
    let out = SerializationRepair.repair(.object(["f": .string("~~~ fetchData() ~~~")] as JSONObject))
    XCTAssertEqual(out["f"], .string(" fetchData() "))
  }

  func testRecursesIntoArraysAndObjects() {
    let out = SerializationRepair.repair(
      .object(["a": .array([.string("~~~ null ~~~"), .object(["b": .string("~~~ zero ~~~")] as JSONObject)] as [JSONValue])] as JSONObject))
    XCTAssertEqual(out["a"]?[0], .null)
    XCTAssertEqual(out["a"]?[1]?["b"], .number(0))
  }

  func testTopLevelStringUntouched() {
    XCTAssertEqual(SerializationRepair.repair(.string("~~~ null ~~~")), .string("~~~ null ~~~"))
  }

  func testNaNAndInfinity() {
    let out = SerializationRepair.repair(.object([
      "nan": .string("~~~ NaN ~~~"), "inf": .string("~~~ Infinity ~~~"),
      "ninf": .string("~~~ -Infinity ~~~"),
    ] as JSONObject))
    XCTAssertTrue(out["nan"]?.numberValue?.isNaN == true)
    XCTAssertEqual(out["inf"], .number(.infinity))
    XCTAssertEqual(out["ninf"], .number(-.infinity))
  }
}
