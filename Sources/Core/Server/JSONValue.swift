import Foundation

/// Untyped JSON value — the Swift stand-in for whatever `JSON.parse` hands the
/// upstream server. Objects keep wire key order (`JSONObject`), like JS.
///
/// Not `Codable` on purpose: Foundation's `JSONDecoder`/`JSONEncoder` lose key
/// order and spell numbers differently from JS, so all reading and writing
/// goes through `JSONParser` / `JSONWriter` (see their doc comments).
enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object(JSONObject)
  /// A large container from a command payload, still as its wire bytes
  /// (memory optimization, see `RawJSON` / `LazyJSONPolicy`). Only the wire
  /// parser in lazy mode produces it. The accessors below materialize it on
  /// demand, so code that doesn't know about it stays correct; hot paths use
  /// the zero-parse helpers (`isArray`, `isObject`, `containerCount`,
  /// `isTruthy`) or `JSONWriter`, which emits canonical bytes verbatim.
  case raw(RawJSON)

  var stringValue: String? { if case .string(let s) = self { s } else { nil } }
  var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
  var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
  var arrayValue: [JSONValue]? {
    switch self {
    case .array(let a): a
    case .raw(let r) where !r.isObject: r.materialize().arrayValue
    default: nil
    }
  }
  var objectValue: JSONObject? {
    switch self {
    case .object(let o): o
    case .raw(let r) where r.isObject: r.materialize().objectValue
    default: nil
    }
  }
  var isNull: Bool { if case .null = self { true } else { false } }

  /// Zero-parse shape checks (a `.raw` value knows its bracket).
  var isArray: Bool {
    switch self {
    case .array: true
    case .raw(let r): !r.isObject
    default: false
    }
  }
  var isObject: Bool {
    switch self {
    case .object: true
    case .raw(let r): r.isObject
    default: false
    }
  }
  /// Key / item count of an object or array (raw included, without parsing).
  var containerCount: Int? {
    switch self {
    case .array(let a): a.count
    case .object(let o): o.count
    case .raw(let r): r.count
    default: nil
    }
  }

  /// `self`, with a top-level `.raw` parsed (one level of laziness removed —
  /// its parse is fully materialized, so the result contains no `.raw`).
  var materialized: JSONValue {
    if case .raw(let r) = self { return r.materialize() }
    return self
  }

  subscript(_ key: String) -> JSONValue? { objectValue?[key] }
  subscript(_ index: Int) -> JSONValue? {
    guard let a = arrayValue, a.indices.contains(index) else { return nil }
    return a[index]
  }

  /// JS truthiness — false for null, false, 0, NaN, "".
  var isTruthy: Bool {
    switch self {
    case .null: false
    case .bool(let b): b
    case .number(let n): n != 0 && !n.isNaN
    case .string(let s): !s.isEmpty
    case .array, .object, .raw: true
    }
  }

  /// Deep equality with the old `Dictionary` semantics (object key order
  /// ignored). A `.raw` side equals another raw with the same bytes;
  /// otherwise it's materialized and compared structurally.
  static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): return true
    case let (.bool(a), .bool(b)): return a == b
    case let (.number(a), .number(b)): return a == b
    case let (.string(a), .string(b)): return a == b
    case let (.array(a), .array(b)): return a == b
    case let (.object(a), .object(b)): return a == b
    case let (.raw(a), .raw(b)) where a === b || a.bytes == b.bytes: return true
    case let (.raw(a), _): return a.materialize() == rhs
    case let (_, .raw(b)): return lhs == b.materialize()
    default: return false
    }
  }

  /// Strict `JSON.parse` equivalent (ordered keys, last duplicate wins);
  /// nil for malformed input.
  static func parse(_ data: Data) -> JSONValue? {
    JSONParser.parse(data)
  }

  /// Compact `JSON.stringify` equivalent (insertion order, JS number
  /// spelling, `/` unescaped, non-finite numbers → `null`). Always succeeds;
  /// the optional return is kept for existing call sites.
  func encodedString() -> String? {
    JSONWriter.stringify(self)
  }

  /// `JSON.stringify(x, null, 2)` equivalent; `sortedKeys` sorts object keys
  /// at every level instead of keeping insertion order.
  func prettyString(sortedKeys: Bool = false) -> String {
    JSONWriter.pretty(self, sortedKeys: sortedKeys)
  }
}
