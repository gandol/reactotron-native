import Foundation

/// `JSON.stringify` for `JSONValue` — what the upstream server and UI use
/// everywhere a value becomes text (wire sends in `reactotron-core-server.ts`,
/// `filterCommands/index.ts`'s `matching`, clipboard copies).
///
/// Hand-written instead of `JSONEncoder` so the output matches JS:
/// - object keys in insertion order;
/// - `/` is not escaped; string escapes are exactly JS's (`\" \\ \b \f \n \r
///   \t`, `\u00xx` lowercase for other C0 controls, everything else literal);
/// - numbers spelled like ECMAScript `Number::toString` (`1e-7`, `1e+21`,
///   `10000000000000000`), `-0` → `0`, non-finite → `null`.
///
/// A `.raw` subtree whose bytes are canonical (`RawJSON.isVerbatimJSON`) is
/// copied verbatim — those bytes are exactly what the rules above would
/// produce for its parse; any other raw subtree is materialized and written.
/// Pretty output always materializes.
enum JSONWriter {
  /// Compact `JSON.stringify(value)`.
  static func stringify(_ value: JSONValue) -> String {
    var out: [UInt8] = []
    out.reserveCapacity(64)
    writeCompact(value, into: &out)
    return String(decoding: out, as: UTF8.self)
  }

  /// `JSON.stringify(value, null, 2)`. With `sortedKeys`, object keys are
  /// sorted at every level instead of kept in insertion order.
  static func pretty(_ value: JSONValue, sortedKeys: Bool = false) -> String {
    var out: [UInt8] = []
    out.reserveCapacity(128)
    writePretty(value, indent: 0, sortedKeys: sortedKeys, into: &out)
    return String(decoding: out, as: UTF8.self)
  }

  private static func writeCompact(_ value: JSONValue, into out: inout [UInt8]) {
    switch value {
    case .null: out.append(contentsOf: "null".utf8)
    case .bool(let b): out.append(contentsOf: (b ? "true" : "false").utf8)
    case .number(let n): out.append(contentsOf: numberString(n).utf8)
    case .string(let s): writeString(s, into: &out)
    case .array(let a):
      out.append(UInt8(ascii: "["))
      for (i, item) in a.enumerated() {
        if i > 0 { out.append(UInt8(ascii: ",")) }
        writeCompact(item, into: &out)
      }
      out.append(UInt8(ascii: "]"))
    case .object(let o):
      out.append(UInt8(ascii: "{"))
      for (i, pair) in o.enumerated() {
        if i > 0 { out.append(UInt8(ascii: ",")) }
        writeString(pair.key, into: &out)
        out.append(UInt8(ascii: ":"))
        writeCompact(pair.value, into: &out)
      }
      out.append(UInt8(ascii: "}"))
    case .raw(let r):
      // Canonical wire bytes already are `JSON.stringify` of their parse.
      if r.isVerbatimJSON {
        out.append(contentsOf: r.bytes)
      } else {
        writeCompact(r.materialize(), into: &out)
      }
    }
  }

  private static func writePretty(_ value: JSONValue, indent: Int, sortedKeys: Bool, into out: inout [UInt8]) {
    switch value {
    case .array(let a) where !a.isEmpty:
      out.append(UInt8(ascii: "["))
      for (i, item) in a.enumerated() {
        if i > 0 { out.append(UInt8(ascii: ",")) }
        newline(indent + 1, into: &out)
        writePretty(item, indent: indent + 1, sortedKeys: sortedKeys, into: &out)
      }
      newline(indent, into: &out)
      out.append(UInt8(ascii: "]"))
    case .object(let o) where !o.isEmpty:
      out.append(UInt8(ascii: "{"))
      let pairs: [JSONObject.Element] = sortedKeys ? o.sorted { $0.key < $1.key } : Array(o)
      for (i, pair) in pairs.enumerated() {
        if i > 0 { out.append(UInt8(ascii: ",")) }
        newline(indent + 1, into: &out)
        writeString(pair.key, into: &out)
        out.append(contentsOf: ": ".utf8)
        writePretty(pair.value, indent: indent + 1, sortedKeys: sortedKeys, into: &out)
      }
      newline(indent, into: &out)
      out.append(UInt8(ascii: "}"))
    case .raw(let r):
      writePretty(r.materialize(), indent: indent, sortedKeys: sortedKeys, into: &out)
    default:
      writeCompact(value, into: &out)
    }
  }

  private static func newline(_ indent: Int, into out: inout [UInt8]) {
    out.append(0x0A)
    out.append(contentsOf: repeatElement(UInt8(ascii: " "), count: indent * 2))
  }

  private static let hexDigits = Array("0123456789abcdef".utf8)

  /// JS `QuoteJSONString`.
  private static func writeString(_ s: String, into out: inout [UInt8]) {
    out.append(0x22)
    for b in s.utf8 {
      switch b {
      case 0x22: out.append(contentsOf: [0x5C, 0x22])
      case 0x5C: out.append(contentsOf: [0x5C, 0x5C])
      case 0x08: out.append(contentsOf: [0x5C, UInt8(ascii: "b")])
      case 0x0C: out.append(contentsOf: [0x5C, UInt8(ascii: "f")])
      case 0x0A: out.append(contentsOf: [0x5C, UInt8(ascii: "n")])
      case 0x0D: out.append(contentsOf: [0x5C, UInt8(ascii: "r")])
      case 0x09: out.append(contentsOf: [0x5C, UInt8(ascii: "t")])
      case 0..<0x20:
        out.append(contentsOf: [0x5C, UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0")])
        out.append(hexDigits[Int(b >> 4)])
        out.append(hexDigits[Int(b & 0xF)])
      default: out.append(b)
      }
    }
    out.append(0x22)
  }

  /// ECMAScript `Number::toString(10)` for finite values (non-finite →
  /// `null`, as `JSON.stringify` does). Takes Swift's shortest round-trip
  /// digits from `Double.description` and re-lays them out per the spec:
  /// with k significant digits and decimal exponent n (value = 0.d₁…d_k × 10ⁿ),
  /// - k ≤ n ≤ 21  → digits followed by n−k zeros
  /// - 0 < n ≤ 21  → decimal point after the n-th digit
  /// - −6 < n ≤ 0  → `0.` + −n zeros + digits
  /// - otherwise   → `d.ddde±x`
  static func numberString(_ n: Double) -> String {
    guard n.isFinite else { return "null" }
    if n == 0 { return "0" }  // also -0
    if n.rounded(.towardZero) == n, abs(n) < 1e15 { return String(Int64(n)) }

    let desc = abs(n).description
    var mantissa = Substring(desc)
    var exponent = 0
    if let e = desc.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      mantissa = desc[..<e]
      exponent = Int(desc[desc.index(after: e)...]) ?? 0
    }
    var digits: [UInt8] = []
    var pointPos = -1
    for c in mantissa.utf8 {
      if c == UInt8(ascii: ".") { pointPos = digits.count } else { digits.append(c) }
    }
    if pointPos < 0 { pointPos = digits.count }
    var lead = 0
    while lead < digits.count, digits[lead] == UInt8(ascii: "0") { lead += 1 }
    digits.removeFirst(lead)
    while digits.last == UInt8(ascii: "0") { digits.removeLast() }
    guard !digits.isEmpty else { return "0" }

    let k = digits.count
    let e = pointPos - lead + exponent
    var out: [UInt8] = n < 0 ? [UInt8(ascii: "-")] : []
    if k <= e, e <= 21 {
      out += digits
      out += repeatElement(UInt8(ascii: "0"), count: e - k)
    } else if 0 < e, e <= 21 {
      out += digits[0..<e]
      out.append(UInt8(ascii: "."))
      out += digits[e...]
    } else if -6 < e, e <= 0 {
      out += Array("0.".utf8)
      out += repeatElement(UInt8(ascii: "0"), count: -e)
      out += digits
    } else {
      out.append(digits[0])
      if k > 1 {
        out.append(UInt8(ascii: "."))
        out += digits[1...]
      }
      let x = e - 1
      out += Array((x < 0 ? "e-" : "e+").utf8)
      out += Array(String(abs(x)).utf8)
    }
    return String(decoding: out, as: UTF8.self)
  }
}
