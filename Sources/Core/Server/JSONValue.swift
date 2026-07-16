import Foundation

enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
    else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
    else {
      throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    // JSON has no NaN/Infinity; encode as null (JS JSON.stringify does the same)
    case .number(let n): n.isFinite ? try c.encode(n) : try c.encodeNil()
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  var stringValue: String? { if case .string(let s) = self { s } else { nil } }
  var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
  var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
  var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
  var objectValue: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
  var isNull: Bool { self == .null }

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
    case .array, .object: true
    }
  }

  static func parse(_ data: Data) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  func encodedString() -> String? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
