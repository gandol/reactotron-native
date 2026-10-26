import Foundation

/// Insertion-ordered JSON object — the JS object semantics `JSON.parse`
/// produces (wire key order kept; a duplicate key's last value wins and keeps
/// the first key's position).
///
/// Replaces `[String: JSONValue]` purely for memory: one contiguous buffer of
/// `(key, value)` pairs (~40 B/pair) instead of a hashed `Dictionary` (~350 B
/// for a 4-key object). Command payloads are retained by the hundreds
/// (`SessionStore` keeps 500 per connection, like upstream), so per-object
/// overhead dominates the app's footprint.
///
/// Lookup is a linear scan — payload objects are small, so it costs about the
/// same as hashing. Code that walks keys and looks each one up again should
/// iterate the pairs instead (`for (key, value) in obj`, or
/// `obj.sorted { $0.key < $1.key }`), which stays O(n log n).
///
/// `==` is order-insensitive (same keys, equal values), matching both the old
/// `Dictionary` semantics and JS deep-equal (`lodash.isEqual`).
struct JSONObject: Sendable, Equatable, ExpressibleByDictionaryLiteral, RandomAccessCollection {
  /// Same labels as `Dictionary.Element`, so `$0.key` / `$0.value` and
  /// `for (key, value) in obj` read the same as they did on a dictionary.
  typealias Element = (key: String, value: JSONValue)
  typealias Index = Int
  typealias Indices = Range<Int>

  private(set) var storage: ContiguousArray<Element>

  /// Empty object; shares the empty-array singleton (no allocation).
  init() { storage = [] }

  /// Literal order is kept. A duplicate literal key takes the last value at
  /// the first key's position (a `Dictionary` literal would trap instead).
  init(dictionaryLiteral elements: (String, JSONValue)...) {
    storage = []
    storage.reserveCapacity(elements.count)
    for (key, value) in elements { self[key] = value }
  }

  /// Bridging for code that still builds a `Dictionary`; order is the
  /// dictionary's (unspecified) iteration order.
  init(_ dict: [String: JSONValue]) {
    storage = ContiguousArray(dict.lazy.map { (key: $0.key, value: $0.value) })
  }

  /// Trusted fast path — the caller guarantees the keys are already unique
  /// (parser output, a rebuilt copy of another object, array indices).
  init(uniqueKeysWithValues pairs: some Sequence<(String, JSONValue)>) {
    storage = ContiguousArray(pairs.lazy.map { (key: $0.0, value: $0.1) })
  }

  /// Takes ownership of a pair buffer whose keys are already unique.
  init(uniquePairs: ContiguousArray<Element>) {
    storage = uniquePairs
  }

  // MARK: - Collection

  var startIndex: Int { 0 }
  var endIndex: Int { storage.count }
  subscript(position: Int) -> Element { storage[position] }
  var count: Int { storage.count }
  var isEmpty: Bool { storage.isEmpty }

  // MARK: - Dictionary-like API

  /// Index of `key`, or nil (linear scan).
  func index(forKey key: String) -> Int? {
    storage.firstIndex { $0.key == key }
  }

  /// Get: the value for `key`. Set: replaces in place when the key exists,
  /// appends a new key at the end (JS property-add order), `nil` removes.
  subscript(key: String) -> JSONValue? {
    get {
      for pair in storage where pair.key == key { return pair.value }
      return nil
    }
    set {
      if let i = index(forKey: key) {
        if let newValue { storage[i].value = newValue } else { storage.remove(at: i) }
      } else if let newValue {
        storage.append((key: key, value: newValue))
      }
    }
  }

  var keys: [String] { storage.map(\.key) }
  var values: [JSONValue] { storage.map(\.value) }

  /// Order-preserving `mapValues` (used by `SerializationRepair`).
  func mapValues(_ transform: (JSONValue) throws -> JSONValue) rethrows -> JSONObject {
    var out = ContiguousArray<Element>()
    out.reserveCapacity(storage.count)
    for pair in storage { out.append((key: pair.key, value: try transform(pair.value))) }
    return JSONObject(uniquePairs: out)
  }

  @discardableResult
  mutating func removeValue(forKey key: String) -> JSONValue? {
    guard let i = index(forKey: key) else { return nil }
    return storage.remove(at: i).value
  }

  mutating func reserveCapacity(_ n: Int) { storage.reserveCapacity(n) }

  /// Appends without a duplicate check — only for builders that know `key`
  /// is new (e.g. copying the pairs of another object one by one).
  mutating func appendUnchecked(key: String, value: JSONValue) {
    storage.append((key: key, value: value))
  }

  // MARK: - Equatable

  /// Order-insensitive: equal counts and every lhs pair present in rhs with an
  /// equal value. Above 16 keys one side gets a temporary hash index so large
  /// objects don't compare in O(n²).
  static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
    guard lhs.count == rhs.count else { return false }
    if lhs.count > 16 {
      var index: [String: Int] = [:]
      index.reserveCapacity(rhs.count)
      for (i, pair) in rhs.storage.enumerated() { index[pair.key] = i }
      for pair in lhs.storage {
        guard let i = index[pair.key], rhs.storage[i].value == pair.value else { return false }
      }
      return true
    }
    for pair in lhs.storage {
      guard let other = rhs[pair.key], other == pair.value else { return false }
    }
    return true
  }
}
