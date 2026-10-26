import XCTest
@testable import Reactotron

/// `JSONParser` — strict, order-preserving `JSON.parse`.
final class JSONParserTests: XCTestCase {
  private func parse(_ s: String) -> JSONValue? { JSONValue.parse(Data(s.utf8)) }

  func testObjectKeepsWireOrder() {
    let v = parse(#"{"zeta":1,"alpha":2,"mid":3,"b":{"y":1,"x":2},"a":[{"q":1,"p":2}]}"#)
    XCTAssertEqual(v?.objectValue?.keys, ["zeta", "alpha", "mid", "b", "a"])
    XCTAssertEqual(v?["b"]?.objectValue?.keys, ["y", "x"])
    XCTAssertEqual(v?["a"]?[0]?.objectValue?.keys, ["q", "p"])
  }

  func testDuplicateKeyLastValueFirstPosition() {
    let v = parse(#"{"dup":1,"other":0,"dup":2}"#)
    XCTAssertEqual(v?.objectValue?.keys, ["dup", "other"])
    XCTAssertEqual(v?["dup"], .number(2))
  }

  func testDuplicateKeyInLargeObjectUsesIndexPath() {
    let pairs = (0..<30).map { "\"k\($0)\":\($0)" }.joined(separator: ",")
    let v = parse("{\(pairs),\"k3\":\"again\",\"k25\":null,\"new\":true}")
    let keys = v?.objectValue?.keys
    XCTAssertEqual(keys?.count, 31)
    XCTAssertEqual(keys?[3], "k3")
    XCTAssertEqual(keys?.last, "new")
    XCTAssertEqual(v?["k3"], .string("again"))
    XCTAssertEqual(v?["k25"], .null)
  }

  func testDuplicateKeyDetectionIsPerObject() {
    let v = parse(#"{"a":{"a":1,"b":2},"b":{"a":3}}"#)
    XCTAssertEqual(v?.objectValue?.keys, ["a", "b"])
    XCTAssertEqual(v?["a"]?.objectValue?.keys, ["a", "b"])
    XCTAssertEqual(v?["b"]?["a"], .number(3))
  }

  func testStringEscapes() {
    let v = parse(#"["a\"b\\c\/d\b\f\n\r\t", "\u00e9\u0041", "\ud83d\ude00", "😀", "\ud800x", "\udc00"]"#)
    XCTAssertEqual(v?[0], .string("a\"b\\c/d\u{8}\u{c}\n\r\t"))
    XCTAssertEqual(v?[1], .string("éA"))
    XCTAssertEqual(v?[2], .string("😀"))
    XCTAssertEqual(v?[3], .string("😀"))
    XCTAssertEqual(v?[4], .string("\u{FFFD}x"))  // lone high surrogate
    XCTAssertEqual(v?[5], .string("\u{FFFD}"))  // lone low surrogate
  }

  func testNumbers() {
    XCTAssertEqual(parse("0"), .number(0))
    XCTAssertEqual(parse("-12"), .number(-12))
    XCTAssertEqual(parse("1.5"), .number(1.5))
    XCTAssertEqual(parse("1E5"), .number(100_000))
    XCTAssertEqual(parse("2.5e-3"), .number(0.0025))
    XCTAssertEqual(parse("1e400"), .number(.infinity))
    XCTAssertEqual(parse("-1e400"), .number(-.infinity))
    XCTAssertEqual(parse("12345678901234567890"), .number(12_345_678_901_234_567_890))
    XCTAssertEqual(parse("0.1"), .number(0.1))
    let negZero = parse("-0")?.numberValue
    XCTAssertEqual(negZero, 0)
    XCTAssertEqual(negZero?.sign, .minus)
  }

  func testAcceptsEmptiesAndSurroundingWhitespace() {
    XCTAssertEqual(parse(#""""#), .string(""))
    XCTAssertEqual(parse("{}"), .object([:]))
    XCTAssertEqual(parse("[]"), .array([]))
    XCTAssertEqual(parse(" \t\r\n{ \"a\" : [ 1 , true , null ] }\n "), .object(["a": .array([.number(1), .bool(true), .null])]))
  }

  func testRejectsMalformed() {
    let bad = [
      "", " ", "[1,]", "{\"a\":1,}", "01", "-01", "1.", ".5", "+1", "-", "1e", "1e+", "NaN", "Infinity",
      "'x'", "\"a\u{01}b\"", "\"a\nb\"", "[1] x", "{} {}", "tru", "nul", "[", "{\"a\"}", "{\"a\" 1}",
      "{a:1}", "\"\\x\"", "\"\\u12\"", "\"abc", "[1 2]", "\u{a0}1",
    ]
    for s in bad {
      XCTAssertNil(parse(s), "should reject \(s.debugDescription)")
    }
  }

  func testDepthLimitIsJSONDecoders512() {
    func nested(_ n: Int) -> String { String(repeating: "[", count: n) + String(repeating: "]", count: n) }
    XCTAssertNotNil(parse(nested(512)))
    XCTAssertNil(parse(nested(513)))
    XCTAssertNil(parse(String(repeating: "{\"a\":", count: 513) + "1" + String(repeating: "}", count: 513)))
  }

  /// The wire is parsed on the server's dispatch queue, whose worker threads
  /// have 512 KiB stacks — the deepest accepted document must fit there even
  /// in an unoptimized build.
  func testMaxDepthFitsOnSecondaryThreadStack() {
    let doc = Data((String(repeating: "{\"a\":[", count: 256) + String(repeating: "]}", count: 256)).utf8)
    let done = expectation(description: "parsed")
    nonisolated(unsafe) var ok = false
    let thread = Thread {
      ok = JSONValue.parse(doc) != nil
      done.fulfill()
    }
    thread.stackSize = 512 * 1024
    thread.start()
    wait(for: [done], timeout: 10)
    XCTAssertTrue(ok)
  }

  /// Same results (up to key order) as Foundation's parser on a corpus that
  /// has no duplicate keys — the old `JSONDecoder` path.
  func testCorpusMatchesFoundation() throws {
    let corpus = [
      #"{"type":"log","payload":{"level":"debug","message":"hi"},"important":true,"deltaTime":12,"date":"2026-07-16T10:00:00.000Z"}"#,
      #"{"request":{"url":"https://x.dev/a?b=1","method":"POST","data":"{\"q\":1}","headers":{"Accept":"*/*"}},"response":{"status":200,"body":[1,2.5,-3e-7,null,false,"\u00fc"]},"duration":12.25}"#,
      #"[[],{},[{}],{"a":[]},"",0,-0.5,1e21,123456789012345678,true]"#,
      #"{"nested":{"deep":{"deeper":{"deepest":["x",{"y":"z"}]}}}}"#,
      #"{"emoji":"😀\ud83d\ude00","ctl":"\u0001\t","slash":"a\/b","uni":"\u2028"}"#,
      #"  {"ws" :  [ 1 ,2 , 3 ] }  "#,
      #""just a string""#,
      "42",
      "null",
    ]
    for doc in corpus {
      let ours = try XCTUnwrap(parse(doc), doc)
      let theirs = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(doc.utf8), options: [.fragmentsAllowed]), doc)
      XCTAssertEqual(ours, Self.fromFoundation(theirs), doc)
    }
  }

  private static func fromFoundation(_ any: Any) -> JSONValue {
    switch any {
    case is NSNull: return .null
    case let n as NSNumber:
      if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
      return .number(n.doubleValue)
    case let s as String: return .string(s)
    case let a as [Any]: return .array(a.map(fromFoundation))
    case let d as [String: Any]: return .object(JSONObject(d.mapValues(fromFoundation)))
    default: return .null
    }
  }
}
