import XCTest
@testable import Reactotron

final class RedactionTests: XCTestCase {
  private let rules = Redaction.Rules.defaults

  /// Sensitive keys are matched case-insensitively at any depth.
  func testSensitiveKeyRedactedCaseInsensitivelyAtDepth() {
    let input = JSONValue.object([
      "user": .object([
        "name": .string("alice"),
        "PassWord": .string("hunter2"),
        "nested": .object([
          "Api_Key": .string("abc123"),
          "ok": .string("fine"),
        ]),
      ]),
    ])

    let out = Redaction.redact(input, rules: rules)

    XCTAssertEqual(out["user"]?["PassWord"]?.stringValue, "[REDACTED]")
    XCTAssertEqual(out["user"]?["nested"]?["Api_Key"]?.stringValue, "[REDACTED]")
    XCTAssertEqual(out["user"]?["name"]?.stringValue, "alice")
    XCTAssertEqual(out["user"]?["nested"]?["ok"]?.stringValue, "fine")
  }

  /// A Bearer token embedded in a longer string has just its matched range
  /// replaced.
  func testBearerTokenSubstringReplaced() {
    let input = JSONValue.object(["note": .string("call with Bearer abc123DEF456ghijkl789MNO done")])

    let out = Redaction.redact(input, rules: rules)
    let note = out["note"]?.stringValue ?? ""

    XCTAssertTrue(note.contains("[REDACTED]"))
    XCTAssertFalse(note.contains("abc123DEF456ghijkl789MNO"))
    XCTAssertTrue(note.hasPrefix("call with "))
    XCTAssertTrue(note.hasSuffix(" done"))
  }

  /// A PEM private-key block (spanning newlines) is redacted.
  func testPemBlockReplaced() {
    let pem = "-----BEGIN PRIVATE KEY-----\nMIIBVQIBADANBgkqhkiG9w0BAQEF\nAASCAT8wggE7AgEAAkEA\n-----END PRIVATE KEY-----"
    let input = JSONValue.object(["cert": .string("prefix \(pem) suffix")])

    let out = Redaction.redact(input, rules: rules)
    let cert = out["cert"]?.stringValue ?? ""

    XCTAssertTrue(cert.contains("[REDACTED]"))
    XCTAssertFalse(cert.contains("BEGIN PRIVATE KEY"))
    XCTAssertTrue(cert.hasPrefix("prefix "))
    XCTAssertTrue(cert.hasSuffix(" suffix"))
  }

  /// Non-sensitive keys and non-matching values pass through untouched.
  func testNonMatchingValueUntouched() {
    let input = JSONValue.object([
      "greeting": .string("hello world"),
      "count": .number(42),
      "flag": .bool(true),
    ])

    let out = Redaction.redact(input, rules: rules)

    XCTAssertEqual(out["greeting"]?.stringValue, "hello world")
    XCTAssertEqual(out["count"]?.numberValue, 42)
    XCTAssertEqual(out["flag"]?.boolValue, true)
  }

  /// State path patterns (with trailing wildcard) redact by anchored path,
  /// leaving siblings intact.
  func testStatePathPatternRedaction() {
    var r = Redaction.Rules.defaults
    r.statePathPatterns = ["auth.tokens.*"]
    let input = JSONValue.object([
      "auth": .object([
        "tokens": .object(["access": .string("x"), "refresh": .string("y")]),
        "user": .string("me"),
      ]),
    ])

    let out = Redaction.redact(input, rules: r)

    XCTAssertEqual(out["auth"]?["tokens"]?["access"]?.stringValue, "[REDACTED]")
    XCTAssertEqual(out["auth"]?["tokens"]?["refresh"]?.stringValue, "[REDACTED]")
    XCTAssertEqual(out["auth"]?["user"]?.stringValue, "me")
  }
}
