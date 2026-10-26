import XCTest
@testable import Reactotron

/// `JSONWriter` against JS `JSON.stringify` output (values checked in node).
final class JSONWriterTests: XCTestCase {
  func testNumbersMatchJSNumberToString() {
    let table: [(Double, String)] = [
      (1, "1"), (-1, "-1"), (1.5, "1.5"), (-1.5, "-1.5"), (0.1, "0.1"), (100, "100"),
      (123456.789, "123456.789"), (1e15, "1000000000000000"), (1e16, "10000000000000000"),
      (123e18, "123000000000000000000"), (1.2345678901234568e+20, "123456789012345680000"),
      (1e21, "1e+21"), (-1e21, "-1e+21"), (2.5e300, "2.5e+300"),
      (1e-6, "0.000001"), (1.5e-6, "0.0000015"), (0.000001234, "0.000001234"),
      (1e-7, "1e-7"), (1.5e-7, "1.5e-7"), (5e-324, "5e-324"),
      (0, "0"), (-0.0, "0"), (.nan, "null"), (.infinity, "null"), (-.infinity, "null"),
      (9007199254740993, "9007199254740992"), (0.30000000000000004, "0.30000000000000004"),
    ]
    for (n, expected) in table {
      XCTAssertEqual(JSONWriter.stringify(.number(n)), expected, "\(n)")
    }
  }

  func testStringEscapesMatchJS() {
    XCTAssertEqual(JSONWriter.stringify(.string("\u{01}")), #""\u0001""#)
    XCTAssertEqual(JSONWriter.stringify(.string("\u{1f}")), #""\u001f""#)
    XCTAssertEqual(JSONWriter.stringify(.string(" ")), #"" ""#)
    XCTAssertEqual(JSONWriter.stringify(.string("/a/b")), #""/a/b""#)
    XCTAssertEqual(JSONWriter.stringify(.string("😀é\u{2028}")), "\"😀é\u{2028}\"")
    XCTAssertEqual(JSONWriter.stringify(.string("q\"b\\\u{8}\u{c}\n\r\t")), #""q\"b\\\b\f\n\r\t""#)
  }

  func testCompactKeepsKeyOrder() {
    let v = JSONValue.object([
      "type": .string("x"), "payload": .object(["z": .bool(true), "a": .null, "m": .array([.number(1), .string("s")])]),
    ])
    XCTAssertEqual(JSONWriter.stringify(v), #"{"type":"x","payload":{"z":true,"a":null,"m":[1,"s"]}}"#)
    XCTAssertEqual(v.encodedString(), JSONWriter.stringify(v))
  }

  func testPrettyMatchesJSONStringifyIndent2() {
    XCTAssertEqual(JSONWriter.pretty(.object(["a": .number(1)])), "{\n  \"a\": 1\n}")
    XCTAssertEqual(
      JSONWriter.pretty(.object(["b": .array([.number(1), .object([:])]), "a": .array([])])),
      "{\n  \"b\": [\n    1,\n    {}\n  ],\n  \"a\": []\n}")
    XCTAssertEqual(
      JSONWriter.pretty(.object(["b": .number(1), "a": .object(["d": .null, "c": .null])]), sortedKeys: true),
      "{\n  \"a\": {\n    \"c\": null,\n    \"d\": null\n  },\n  \"b\": 1\n}")
    XCTAssertEqual(JSONWriter.pretty(.string("x")), "\"x\"")
  }

  func testRoundTripPreservesValueAndOrder() throws {
    let source = #"{"zeta":[1,0.5,-2e-9,1e+300,"\u0000x"],"alpha":{"y":null,"x":false},"mid":"é😀/\\","":{}}"#
    let parsed = try XCTUnwrap(JSONValue.parse(Data(source.utf8)))
    let text = JSONWriter.stringify(parsed)
    XCTAssertEqual(text, #"{"zeta":[1,0.5,-2e-9,1e+300,"\u0000x"],"alpha":{"y":null,"x":false},"mid":"é😀/\\","":{}}"#)
    let reparsed = try XCTUnwrap(JSONValue.parse(Data(text.utf8)))
    XCTAssertEqual(reparsed, parsed)
    XCTAssertEqual(reparsed.objectValue?.keys, ["zeta", "alpha", "mid", ""])
  }
}
