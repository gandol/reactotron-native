import Foundation

/// Strict, order-preserving JSON parser — the `JSON.parse` the upstream
/// server runs on every incoming frame (`reactotron-core-server.ts`'s
/// `JSON.parse(incoming)`), hand-written because Foundation's parsers lose
/// object key order (and `JSONSerialization` keeps the *first* duplicate key
/// where JS keeps the last).
///
/// Grammar is as strict as `JSON.parse`/`JSONDecoder`: whitespace is only
/// space/tab/LF/CR; no trailing commas, leading zeros, `NaN`/`Infinity`,
/// single quotes, unescaped control characters, or trailing garbage. Nesting
/// deeper than `maxDepth` (JSONDecoder's limit) fails. Nesting is handled
/// with an explicit stack, not recursion.
///
/// Semantics follow JS: object keys keep wire order, a duplicate key's last
/// value wins at the first key's position, numbers are IEEE doubles (overflow
/// → ±infinity, like JS). Divergence: a lone `\uD800`-style surrogate becomes
/// U+FFFD (a Swift `String` can't hold one), and invalid UTF-8 inside a
/// string is repaired to U+FFFD rather than rejected.
///
/// Finished arrays/objects are copied out of reusable scratch stacks into
/// exact-capacity storage, so retained payloads carry no growth slack.
enum JSONParser {
  static let maxDepth = 512

  static func parse(_ data: Data) -> JSONValue? {
    parse(data, lazy: nil)
  }

  /// With a `lazy` policy, large subtrees of a wire envelope's `payload` /
  /// `diff` come back as `.raw` (see `LazyJSONPolicy`); everything else is
  /// parsed eagerly. Validation is identical either way — malformed JSON
  /// anywhere, raw subtrees included, rejects the whole document.
  static func parse(_ data: Data, lazy: LazyJSONPolicy?) -> JSONValue? {
    data.withUnsafeBytes { raw -> JSONValue? in
      var parser = Parser(bytes: raw.assumingMemoryBound(to: UInt8.self), lazy: lazy)
      return parser.parseDocument()
    }
  }

  static func parse(bytes: UnsafeBufferPointer<UInt8>) -> JSONValue? {
    var parser = Parser(bytes: bytes)
    return parser.parseDocument()
  }

  static func parse(_ text: String) -> JSONValue? {
    var text = text
    return text.withUTF8 { buf in
      var parser = Parser(bytes: buf)
      return parser.parseDocument()
    }
  }
}

/// Which subtrees of an incoming frame stay unparsed (`JSONValue.raw`) — a
/// memory optimization with no upstream equivalent (see `RawJSON`).
///
/// Only the envelope's `payload` and `diff` are considered. A container there
/// becomes raw when its exact byte length is at least `minBytes` and it isn't
/// on the *spine* — positions that hot readers (row previews, filterSearch,
/// server bookkeeping, MCP summaries) touch on every render or every
/// command. Spine containers are always parsed, but their children stay
/// eligible:
///
/// | spine                                   | read by                                         |
/// |-----------------------------------------|-------------------------------------------------|
/// | `payload`, `diff` roots                 | everything                                      |
/// | `diff[*]`                               | `DiffEntry.parse` (type/path)                   |
/// | `payload.request`, `.response`          | api row preview, status, MCP summaries          |
/// | `payload.message`                       | log row preview, filterSearch                   |
/// | `payload.changes`, `.changes[*]`        | server subscriptions (`path`), `StateUIStore`   |
/// | `payload.changed`, `.added`, `.removed` | SUBSCRIPTIONS row preview counts                |
/// | `payload.args`, `.args[*]`              | `customCommand.register` parsing                |
/// | `payload.keys`, `.steps`, `.image`      | STATE KEYS pills, benchmark preview, image URL  |
/// | `payload.data`                          | async-storage row preview (`data.key`)          |
/// | `payload.diff`, `.diff[*]`              | `DiffEntry.parse` (`reactotron-redux` sends     |
/// |                                         | `{ name, action, ms, diff }`, `sendAction.ts`)  |
///
/// Everything below `minBytes` is parsed eagerly, as are all descendants of
/// such a small container (they're smaller still). Two more cases are parsed
/// eagerly whatever their size:
/// - a container on one of filterSearch's paths (`payload.message`'s
///   children, `.preview`, `.name`, `.path`, `.triggerType`, `.description`,
///   `.request.url`, `.request.data`) whose bytes can't stand in for
///   `JSON.stringify` (non-canonical, or needs `SerializationRepair`) —
///   otherwise every search keystroke would re-parse it;
/// - a container with a duplicate object key anywhere inside (never sent by
///   a JS client): the parse keeps only the last value, so the bytes, their
///   top-level count, and verbatim writes would disagree with it.
struct LazyJSONPolicy: Sendable {
  var minBytes: Int

  /// The policy `ReactotronServer` parses every frame with.
  static let commandPayload = LazyJSONPolicy(minBytes: 1024)

  static let envelopeKeys: Set<String> = ["payload", "diff"]
  static let payloadSpineKeys: Set<String> = [
    "request", "response", "message", "changes", "changed", "added", "removed",
    "args", "keys", "steps", "image", "data", "diff",
  ]
  /// Payload spine keys whose array items are spine too.
  static let payloadSpineItemKeys: Set<String> = ["changes", "args", "diff"]
  /// Direct `payload` children that `filterSearch` stringifies
  /// (`COMMON_MATCHING_PATHS` in `filterCommands/index.ts`).
  static let payloadSearchKeys: Set<String> = [
    "message", "preview", "name", "path", "triggerType", "description",
  ]
}

private extension UInt8 {
  static let quote = UInt8(ascii: "\"")
  static let backslash = UInt8(ascii: "\\")
  static let comma = UInt8(ascii: ",")
  static let colon = UInt8(ascii: ":")
  static let openBrace = UInt8(ascii: "{")
  static let closeBrace = UInt8(ascii: "}")
  static let openBracket = UInt8(ascii: "[")
  static let closeBracket = UInt8(ascii: "]")
  static let minus = UInt8(ascii: "-")
  static let plus = UInt8(ascii: "+")
  static let dot = UInt8(ascii: ".")
  static let zero = UInt8(ascii: "0")
  static let nine = UInt8(ascii: "9")

  var isDigit: Bool { self >= .zero && self <= .nine }
}

private struct Parser {
  /// One open container. Nesting is tracked on this explicit stack rather
  /// than by recursion, so a maximally nested document can't overflow a
  /// dispatch worker thread's 512 KiB stack (the wire is parsed on the
  /// server queue), even in an unoptimized build.
  private struct Frame {
    let isObject: Bool
    /// Where this container's children start in `items` / `pairs`.
    let base: Int
    /// Object only: the key whose value is being parsed.
    var key = ""
    /// Object only: key → absolute index into `pairs`, built once the
    /// object passes `linearDuplicateLimit` keys.
    var index: [String: Int]?
    /// Lazy mode: this container (or an ancestor) was skip-scanned and found
    /// smaller than `minBytes`, so nothing below it can become raw.
    var eager = false
  }

  /// Result of `skipScan` over one container.
  private struct Scan {
    var end = 0
    var count = 0
    var needsRepair = false
    var isCanonical = true
    /// Some object inside repeats a key (the scan stops there).
    var hasDuplicateKey = false
  }

  /// Skip-scan's record of one open object: where its key hashes start in
  /// `scanKeyHashes`, plus a hash index once it passes `linearDuplicateLimit`.
  private struct ScanObject {
    let base: Int
    var index: Set<Int>?
  }

  let bytes: UnsafeBufferPointer<UInt8>
  let lazy: LazyJSONPolicy?
  var pos = 0
  private var frames: [Frame] = []
  /// Skip-scan's own nesting stack (true = object), reused across scans.
  private var scanStack: [Bool] = []
  /// Skip-scan's open objects and their keys' hashes (duplicate detection).
  private var scanObjects: [ScanObject] = []
  private var scanKeyHashes: [Int] = []
  /// Scratch stack of array items; each array copies its own tail out.
  private var items: [JSONValue] = []
  /// Scratch stack of object pairs; each object copies its own tail out.
  private var pairs: ContiguousArray<JSONObject.Element> = []
  /// Scratch buffer for strings that contain escapes.
  private var stringBytes: [UInt8] = []

  /// Objects up to this many keys check duplicates by linear scan; larger
  /// ones build a temporary hash index for the rest of that object.
  private static let linearDuplicateLimit = 16

  init(bytes: UnsafeBufferPointer<UInt8>, lazy: LazyJSONPolicy? = nil) {
    self.bytes = bytes
    self.lazy = lazy
  }

  mutating func parseDocument() -> JSONValue? {
    skipWhitespace()
    nextValue: while true {
      // 1. Read one value; an opening `[`/`{` with content pushes a frame
      //    and loops back here for its first child.
      guard pos < bytes.count else { return nil }
      var value: JSONValue
      switch bytes[pos] {
      case .openBracket, .openBrace:
        let isObject = bytes[pos] == .openBrace
        // Depth of this container = open ancestors + 1 (empty ones count).
        guard frames.count < JSONParser.maxDepth else { return nil }
        var eager = frames.last?.eager ?? false
        if let lazy, !eager, isLazyEligible() {
          // Validate and measure without building anything; big enough →
          // keep the bytes, otherwise parse it (and all below it) normally.
          let start = pos
          guard let scan = skipScan() else { return nil }
          if !scan.hasDuplicateKey, scan.end - start >= lazy.minBytes,
            (scan.isCanonical && !scan.needsRepair) || !isSearchPath() {
            pos = scan.end
            value = .raw(RawJSON(
              bytes: ContiguousArray(UnsafeBufferPointer(rebasing: bytes[start..<scan.end])),
              isObject: isObject,
              count: scan.count,
              needsRepair: scan.needsRepair,
              isCanonical: scan.isCanonical
            ))
            break
          }
          eager = true
        }
        pos += 1
        skipWhitespace()
        if pos < bytes.count, bytes[pos] == (isObject ? .closeBrace : .closeBracket) {
          pos += 1
          value = isObject ? .object(JSONObject()) : .array([])
        } else if isObject {
          guard let key = parseKey() else { return nil }
          frames.append(Frame(isObject: true, base: pairs.count, key: key, eager: eager))
          continue nextValue
        } else {
          frames.append(Frame(isObject: false, base: items.count, eager: eager))
          continue nextValue
        }
      case .quote:
        guard let s = parseString() else { return nil }
        value = .string(s)
      case UInt8(ascii: "t"):
        guard parseLiteral("true") else { return nil }
        value = .bool(true)
      case UInt8(ascii: "f"):
        guard parseLiteral("false") else { return nil }
        value = .bool(false)
      case UInt8(ascii: "n"):
        guard parseLiteral("null") else { return nil }
        value = .null
      case .minus, .zero ... .nine:
        guard let n = parseNumber() else { return nil }
        value = n
      default:
        return nil
      }

      // 2. Hand the finished value to its parent; a closing bracket finishes
      //    the parent too, which is then handed to *its* parent, and so on.
      while true {
        guard !frames.isEmpty else {
          skipWhitespace()
          return pos == bytes.count ? value : nil
        }
        let top = frames.count - 1
        if frames[top].isObject {
          insertPair(value: value, frame: top)
        } else {
          items.append(value)
        }
        skipWhitespace()
        guard pos < bytes.count else { return nil }
        let c = bytes[pos]
        pos += 1
        if c == .comma {
          skipWhitespace()
          if frames[top].isObject {
            guard let key = parseKey() else { return nil }
            frames[top].key = key
          }
          continue nextValue
        }
        let base = frames[top].base
        if frames[top].isObject, c == .closeBrace {
          value = .object(JSONObject(uniquePairs: ContiguousArray(pairs[base...])))
          pairs.removeSubrange(base...)
        } else if !frames[top].isObject, c == .closeBracket {
          value = .array(Array(items[base...]))
          items.removeSubrange(base...)
        } else {
          return nil
        }
        frames.removeLast()
      }
    }
  }

  /// `"key"` `:` — leaves `pos` at the start of the value.
  private mutating func parseKey() -> String? {
    guard pos < bytes.count, bytes[pos] == .quote, let key = parseString() else { return nil }
    skipWhitespace()
    guard pos < bytes.count, bytes[pos] == .colon else { return nil }
    pos += 1
    skipWhitespace()
    return key
  }

  /// JS `JSON.parse`: a repeated key overwrites the value but keeps the
  /// property's original position.
  private mutating func insertPair(value: JSONValue, frame top: Int) {
    let key = frames[top].key
    if frames[top].index != nil {
      if let existing = frames[top].index![key] {
        pairs[existing].value = value
      } else {
        frames[top].index![key] = pairs.count
        pairs.append((key: key, value: value))
      }
      return
    }
    let base = frames[top].base
    var i = base
    while i < pairs.count {
      if pairs[i].key == key {
        pairs[i].value = value
        return
      }
      i += 1
    }
    pairs.append((key: key, value: value))
    if pairs.count - base > Self.linearDuplicateLimit {
      var built: [String: Int] = [:]
      built.reserveCapacity((pairs.count - base) * 2)
      for j in base..<pairs.count { built[pairs[j].key] = j }
      frames[top].index = built
    }
  }

  private mutating func skipWhitespace() {
    while pos < bytes.count {
      switch bytes[pos] {
      case 0x20, 0x09, 0x0A, 0x0D: pos += 1
      default: return
      }
    }
  }

  private mutating func parseLiteral(_ word: StaticString) -> Bool {
    let n = word.utf8CodeUnitCount
    guard pos + n <= bytes.count else { return false }
    let w = word.utf8Start
    for i in 0..<n where bytes[pos + i] != w[i] { return false }
    pos += n
    return true
  }

  /// Parses a string literal starting at the opening quote.
  private mutating func parseString() -> String? {
    pos += 1  // opening quote
    let start = pos
    // Fast path: no escapes → decode the byte range directly.
    while pos < bytes.count {
      let c = bytes[pos]
      if c == .quote {
        let s = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<pos]), as: UTF8.self)
        pos += 1
        return s
      }
      if c == .backslash { break }
      if c < 0x20 { return nil }
      pos += 1
    }
    guard pos < bytes.count else { return nil }

    // Slow path: copy what we have so far, then decode escapes.
    stringBytes.removeAll(keepingCapacity: true)
    stringBytes.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[start..<pos]))
    while pos < bytes.count {
      let c = bytes[pos]
      if c == .quote {
        pos += 1
        return String(decoding: stringBytes, as: UTF8.self)
      }
      if c < 0x20 { return nil }
      if c != .backslash {
        stringBytes.append(c)
        pos += 1
        continue
      }
      pos += 1
      guard pos < bytes.count else { return nil }
      let e = bytes[pos]
      pos += 1
      switch e {
      case .quote: stringBytes.append(0x22)
      case .backslash: stringBytes.append(0x5C)
      case UInt8(ascii: "/"): stringBytes.append(0x2F)
      case UInt8(ascii: "b"): stringBytes.append(0x08)
      case UInt8(ascii: "f"): stringBytes.append(0x0C)
      case UInt8(ascii: "n"): stringBytes.append(0x0A)
      case UInt8(ascii: "r"): stringBytes.append(0x0D)
      case UInt8(ascii: "t"): stringBytes.append(0x09)
      case UInt8(ascii: "u"):
        guard let unit = hex4(at: pos) else { return nil }
        pos += 4
        var scalar: UInt32
        if (0xD800...0xDBFF).contains(unit) {
          // High surrogate: combine with an immediately following low one.
          if pos + 6 <= bytes.count, bytes[pos] == .backslash, bytes[pos + 1] == UInt8(ascii: "u"),
            let low = hex4(at: pos + 2), (0xDC00...0xDFFF).contains(low) {
            pos += 6
            scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
          } else {
            scalar = 0xFFFD
          }
        } else if (0xDC00...0xDFFF).contains(unit) {
          scalar = 0xFFFD
        } else {
          scalar = unit
        }
        appendUTF8(scalar)
      default:
        return nil
      }
    }
    return nil
  }

  private func hex4(at i: Int) -> UInt32? {
    guard i + 4 <= bytes.count else { return nil }
    var v: UInt32 = 0
    for j in i..<(i + 4) {
      let c = bytes[j]
      let d: UInt8
      switch c {
      case .zero ... .nine: d = c - .zero
      case UInt8(ascii: "a")...UInt8(ascii: "f"): d = c - UInt8(ascii: "a") + 10
      case UInt8(ascii: "A")...UInt8(ascii: "F"): d = c - UInt8(ascii: "A") + 10
      default: return nil
      }
      v = v << 4 | UInt32(d)
    }
    return v
  }

  private mutating func appendUTF8(_ scalar: UInt32) {
    switch scalar {
    case 0..<0x80:
      stringBytes.append(UInt8(scalar))
    case 0x80..<0x800:
      stringBytes.append(UInt8(0xC0 | (scalar >> 6)))
      stringBytes.append(UInt8(0x80 | (scalar & 0x3F)))
    case 0x800..<0x10000:
      stringBytes.append(UInt8(0xE0 | (scalar >> 12)))
      stringBytes.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
      stringBytes.append(UInt8(0x80 | (scalar & 0x3F)))
    default:
      stringBytes.append(UInt8(0xF0 | (scalar >> 18)))
      stringBytes.append(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
      stringBytes.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
      stringBytes.append(UInt8(0x80 | (scalar & 0x3F)))
    }
  }

  /// Grammar of a number token: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`.
  /// Advances past the token; nil if malformed.
  private mutating func scanNumberToken() -> (isInteger: Bool, intStart: Int, negative: Bool)? {
    var negative = false
    if bytes[pos] == .minus {
      negative = true
      pos += 1
    }
    guard pos < bytes.count else { return nil }
    let intStart = pos
    if bytes[pos] == .zero {
      pos += 1
    } else if bytes[pos].isDigit {
      while pos < bytes.count, bytes[pos].isDigit { pos += 1 }
    } else {
      return nil
    }
    var isInteger = true
    if pos < bytes.count, bytes[pos] == .dot {
      isInteger = false
      pos += 1
      let fracStart = pos
      while pos < bytes.count, bytes[pos].isDigit { pos += 1 }
      guard pos > fracStart else { return nil }
    }
    if pos < bytes.count, bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E") {
      isInteger = false
      pos += 1
      if pos < bytes.count, bytes[pos] == .plus || bytes[pos] == .minus { pos += 1 }
      let expStart = pos
      while pos < bytes.count, bytes[pos].isDigit { pos += 1 }
      guard pos > expStart else { return nil }
    }
    return (isInteger, intStart, negative)
  }

  private mutating func parseNumber() -> JSONValue? {
    let start = pos
    guard let token = scanNumberToken() else { return nil }
    let intDigits = pos - token.intStart
    // Small integers are exact in a Double — compute directly.
    if token.isInteger, intDigits <= 15 {
      var v: Int64 = 0
      for i in token.intStart..<pos { v = v &* 10 &+ Int64(bytes[i] &- .zero) }
      if token.negative { return .number(v == 0 ? -0.0 : Double(-v)) }
      return .number(Double(v))
    }
    // Everything else: correctly rounded, overflow → ±infinity (like JS).
    let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<pos]), as: UTF8.self)
    guard let d = Double(text) else { return nil }
    return .number(d)
  }

  // MARK: - Lazy mode

  /// Whether the container opening at `pos` may become `.raw` under
  /// `LazyJSONPolicy` (the spine table there). `frames[0]` is the envelope;
  /// its current `key` says which envelope member is being parsed.
  private func isLazyEligible() -> Bool {
    let depth = frames.count
    guard depth >= 2, frames[0].isObject, LazyJSONPolicy.envelopeKeys.contains(frames[0].key) else {
      return false  // the envelope itself, or a `payload`/`diff` root
    }
    let isPayload = frames[0].key == "payload"
    if depth == 2 {
      // Child of the payload/diff root.
      if isPayload { return !(frames[1].isObject && LazyJSONPolicy.payloadSpineKeys.contains(frames[1].key)) }
      return frames[1].isObject  // `diff[*]` is spine
    }
    if depth == 3, isPayload, frames[1].isObject, !frames[2].isObject,
      LazyJSONPolicy.payloadSpineItemKeys.contains(frames[1].key) {
      return false  // `changes[*]`, `args[*]`
    }
    return true
  }

  /// Whether the (lazy-eligible) container opening at `pos` is, or is inside,
  /// a value `filterSearch` stringifies — see `LazyJSONPolicy`.
  private func isSearchPath() -> Bool {
    guard frames[0].key == "payload", frames[1].isObject else { return false }
    let key = frames[1].key
    if LazyJSONPolicy.payloadSearchKeys.contains(key) { return true }
    return key == "request" && frames.count >= 3 && frames[2].isObject
      && (frames[2].key == "url" || frames[2].key == "data")
  }

  /// Walks the container opening at `pos` with the same grammar and depth
  /// limit as `parseDocument`, building nothing, and reports where it ends,
  /// its top-level member count, and the `RawJSON` flags. Leaves `pos`
  /// unchanged; nil if the container is malformed.
  private mutating func skipScan() -> Scan? {
    let start = pos
    defer { pos = start }
    var scan = Scan()
    var sawHighByte = false
    scanStack.removeAll(keepingCapacity: true)
    scanObjects.removeAll(keepingCapacity: true)
    scanKeyHashes.removeAll(keepingCapacity: true)

    nextValue: while true {
      guard pos < bytes.count else { return nil }
      switch bytes[pos] {
      case .openBracket, .openBrace:
        let isObject = bytes[pos] == .openBrace
        guard frames.count + scanStack.count < JSONParser.maxDepth else { return nil }
        pos += 1
        scanWhitespace(&scan)
        if pos < bytes.count, bytes[pos] == (isObject ? .closeBrace : .closeBracket) {
          pos += 1
        } else {
          scanStack.append(isObject)
          if isObject {
            scanObjects.append(ScanObject(base: scanKeyHashes.count))
            guard scanKey(&scan, sawHighByte: &sawHighByte) else { return nil }
            if scan.hasDuplicateKey { return scan }
          }
          continue nextValue
        }
      case .quote:
        guard scanString(&scan, isKey: false, sawHighByte: &sawHighByte) else { return nil }
      case UInt8(ascii: "t"):
        guard parseLiteral("true") else { return nil }
      case UInt8(ascii: "f"):
        guard parseLiteral("false") else { return nil }
      case UInt8(ascii: "n"):
        guard parseLiteral("null") else { return nil }
      case .minus, .zero ... .nine:
        guard scanNumber(&scan) else { return nil }
      default:
        return nil
      }

      // A value just ended; close as many containers as end here.
      while true {
        guard let isObject = scanStack.last else {
          scan.end = pos
          if sawHighByte, scan.isCanonical,
            !Self.isValidUTF8(UnsafeBufferPointer(rebasing: bytes[start..<pos])) {
            scan.isCanonical = false
          }
          return scan
        }
        if scanStack.count == 1 { scan.count += 1 }
        scanWhitespace(&scan)
        guard pos < bytes.count else { return nil }
        let c = bytes[pos]
        pos += 1
        if c == .comma {
          scanWhitespace(&scan)
          if isObject {
            guard scanKey(&scan, sawHighByte: &sawHighByte) else { return nil }
            if scan.hasDuplicateKey { return scan }
          }
          continue nextValue
        }
        guard c == (isObject ? .closeBrace : .closeBracket) else { return nil }
        scanStack.removeLast()
        if isObject {
          scanKeyHashes.removeSubrange(scanObjects.removeLast().base...)
        }
      }
    }
  }

  /// Any whitespace between tokens makes the bytes non-canonical
  /// (`JSON.stringify` emits none).
  private mutating func scanWhitespace(_ scan: inout Scan) {
    let before = pos
    skipWhitespace()
    if pos != before { scan.isCanonical = false }
  }

  /// Validates `"key"` `:` and records the key in the innermost open object,
  /// setting `hasDuplicateKey` if that object already has it.
  private mutating func scanKey(_ scan: inout Scan, sawHighByte: inout Bool) -> Bool {
    let keyStart = pos
    guard pos < bytes.count, bytes[pos] == .quote,
      scanString(&scan, isKey: true, sawHighByte: &sawHighByte)
    else { return false }
    if recordScannedKey(from: keyStart) { scan.hasDuplicateKey = true }
    scanWhitespace(&scan)
    guard pos < bytes.count, bytes[pos] == .colon else { return false }
    pos += 1
    scanWhitespace(&scan)
    return true
  }

  /// Hashes the decoded key whose (already validated) literal spans
  /// `keyStart..<pos` and adds it to the innermost scanned object; true if
  /// the object already had that hash. A 64-bit hash collision only makes a
  /// subtree parse eagerly, which is always correct.
  private mutating func recordScannedKey(from keyStart: Int) -> Bool {
    let end = pos
    var hasher = Hasher()
    let literal = UnsafeBufferPointer(rebasing: bytes[(keyStart + 1)..<(end - 1)])
    if literal.contains(.backslash) {
      // Escapes: hash the decoded text, so `"a"` and `"\u0061"` collide.
      pos = keyStart
      var key = parseString() ?? ""
      pos = end
      key.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
    } else {
      hasher.combine(bytes: UnsafeRawBufferPointer(literal))
    }
    let hash = hasher.finalize()
    let top = scanObjects.count - 1
    let base = scanObjects[top].base
    if scanObjects[top].index != nil {
      if !scanObjects[top].index!.insert(hash).inserted { return true }
    } else {
      if scanKeyHashes[base...].contains(hash) { return true }
      if scanKeyHashes.count - base >= Self.linearDuplicateLimit {
        var index = Set(scanKeyHashes[base...])
        index.insert(hash)
        scanObjects[top].index = index
      }
    }
    scanKeyHashes.append(hash)
    return false
  }

  /// Validates a string literal at the opening quote, like `parseString`.
  /// Flags: a value string starting with `~~~ ` (every
  /// `repair-serialization.ts` trigger does) needs repair; a `\u` escape
  /// that isn't a C0 control could spell one, so it does too, and isn't
  /// canonical either. `\/`, uppercase hex, or a `\u` escape JS writes
  /// with a short form also make the bytes non-canonical.
  private mutating func scanString(_ scan: inout Scan, isKey: Bool, sawHighByte: inout Bool) -> Bool {
    pos += 1  // opening quote
    if !isKey, pos + 4 <= bytes.count, bytes[pos] == UInt8(ascii: "~"), bytes[pos + 1] == UInt8(ascii: "~"),
      bytes[pos + 2] == UInt8(ascii: "~"), bytes[pos + 3] == 0x20 {
      scan.needsRepair = true
    }
    while pos < bytes.count {
      let c = bytes[pos]
      pos += 1
      if c == .quote { return true }
      if c < 0x20 { return false }
      if c >= 0x80 { sawHighByte = true }
      guard c == .backslash else { continue }
      guard pos < bytes.count else { return false }
      let e = bytes[pos]
      pos += 1
      switch e {
      case .quote, .backslash, UInt8(ascii: "b"), UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"),
        UInt8(ascii: "t"):
        break
      case UInt8(ascii: "/"):
        scan.isCanonical = false
      case UInt8(ascii: "u"):
        guard let unit = hex4(at: pos) else { return false }
        let lowercaseHex = (pos..<(pos + 4)).allSatisfy { !(UInt8(ascii: "A")...UInt8(ascii: "F")).contains(bytes[$0]) }
        pos += 4
        switch unit {
        case 0x08, 0x09, 0x0A, 0x0C, 0x0D:
          scan.isCanonical = false  // JS writes \b \t \n \f \r
        case 0..<0x20:
          if !lowercaseHex { scan.isCanonical = false }
        default:
          scan.isCanonical = false
          scan.needsRepair = true
        }
      default:
        return false
      }
    }
    return false
  }

  /// Validates a number token; it's canonical only if it's exactly what
  /// `JSONWriter.numberString` (JS `Number::toString`) writes for its value.
  private mutating func scanNumber(_ scan: inout Scan) -> Bool {
    let start = pos
    guard let token = scanNumberToken() else { return false }
    guard scan.isCanonical else { return true }
    let intDigits = pos - token.intStart
    if token.isInteger, intDigits <= 15 {
      // Grammar already excludes leading zeros; only `-0` re-spells (as `0`).
      if token.negative, bytes[token.intStart] == .zero { scan.isCanonical = false }
      return true
    }
    let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<pos]), as: UTF8.self)
    guard let d = Double(text) else { return false }
    if JSONWriter.numberString(d) != text { scan.isCanonical = false }
    return true
  }

  private static func isValidUTF8(_ buffer: UnsafeBufferPointer<UInt8>) -> Bool {
    var decoder = UTF8()
    var iterator = buffer.makeIterator()
    while true {
      switch decoder.decode(&iterator) {
      case .scalarValue: continue
      case .emptyInput: return true
      case .error: return false
      }
    }
  }
}
