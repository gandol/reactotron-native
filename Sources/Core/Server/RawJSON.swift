import Foundation
import os

/// An unparsed JSON container (`{…}` or `[…]`) kept as its exact wire bytes.
///
/// Memory optimization with no upstream equivalent: upstream
/// (`reactotron-core-server.ts`) keeps every payload as a parsed JS object.
/// Here the wire parser leaves large command-payload subtrees (an API
/// response body, a `display` value, a Redux action — see `LazyJSONPolicy`)
/// as bytes, about 1× their wire size instead of ~5× as a parsed tree, and
/// parses them on demand (`materialize()`), e.g. when a timeline row is
/// expanded or an MCP tool reads the command.
///
/// Immutable (only `let` Sendable properties), so it's checked `Sendable`
/// and shared by reference between `SessionStore` and the MCP ring buffer.
/// It never caches its parse — retained commands keep only the bytes; views
/// that render a subtree cache the parse for their own lifetime
/// (`MaterializedJSON`).
final class RawJSON: Sendable {
  /// Exact copy of the subtree's byte range — not a `Data` slice, which would
  /// pin the whole incoming frame's buffer.
  let bytes: ContiguousArray<UInt8>
  /// `{` (true) or `[` (false).
  let isObject: Bool
  /// Top-level key / item count, for previews that don't need a parse.
  let count: Int
  /// Conservative: some string in the subtree may be rewritten by
  /// `SerializationRepair` (it starts with `~~~ `, or has a non-control
  /// `\u` escape that could spell one). `materialize()` runs the repair
  /// that receive time deferred.
  let needsRepair: Bool
  /// `bytes` are exactly what `JSON.stringify(JSON.parse(bytes))` produces
  /// (no insignificant whitespace, only the escapes JS emits, numbers in JS
  /// shortest form, valid UTF-8). Only then may `JSONWriter` emit the bytes
  /// verbatim; otherwise it writes `materialize()`.
  let isCanonical: Bool

  init(bytes: ContiguousArray<UInt8>, isObject: Bool, count: Int, needsRepair: Bool, isCanonical: Bool) {
    self.bytes = bytes
    self.isObject = isObject
    self.count = count
    self.needsRepair = needsRepair
    self.isCanonical = isCanonical
  }

  /// True when the bytes can stand in for `JSON.stringify` of the
  /// materialized (and repaired) value.
  var isVerbatimJSON: Bool { isCanonical && !needsRepair }

  /// The bytes as text (valid UTF-8 whenever `isCanonical`).
  var text: String { String(decoding: bytes, as: UTF8.self) }

  /// Eager ordered parse of the bytes, plus the `SerializationRepair` pass
  /// that was deferred at receive time. The subtree is never a payload root
  /// and always a container, so `repair` here is the same per-child walk
  /// upstream's in-place `repairSerialization` does. Not cached.
  func materialize() -> JSONValue {
    #if DEBUG
    Self.debugMaterializeCount.withLock { $0 += 1 }
    #endif
    let parsed = bytes.withUnsafeBufferPointer { JSONParser.parse(bytes: $0) }
    // The bytes were validated by the wire parser's skip-scan, so this
    // can't fail; fall back to an empty container rather than trap.
    let value = parsed ?? (isObject ? .object(JSONObject()) : .array([]))
    return needsRepair ? SerializationRepair.repair(value) : value
  }

  #if DEBUG
  /// Number of `materialize()` calls so far — lets tests assert that hot
  /// paths (row previews, search over canonical subtrees) never parse.
  /// Debug builds only, so Release never takes the lock.
  static let debugMaterializeCount = OSAllocatedUnfairLock(initialState: 0)
  #endif
}
