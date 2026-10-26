import SwiftUI

/// Port of `reactotron-core-ui/src/components/ContentView`. Chooses how to
/// render an arbitrary JSON value the way Reactotron does:
///
/// - `null` → "null" in the tag color
/// - a string (or a JSON string that doesn't parse to an object) → selectable
///   multi-line text
/// - a SHALLOW object/array (no nested objects — e.g. HTTP headers) → a flat
///   key/value table (`KeyValueTable`, the `makeTable` equivalent)
/// - a nested object/array → the recursive `TreeView`
///
/// This is what makes request/response **headers** render as a clean two-column
/// table (like the real app) instead of a disclosure tree.
struct ContentValueView: View {
  let value: JSONValue
  var treeLevel: Int = 0

  var body: some View {
    // Source first tries JSON.parse(value): a JSON string is expanded into the
    // structure it encodes before deciding table-vs-tree.
    let resolved = resolvedValue

    switch resolved {
    case .null:
      Text("null").font(Theme.font(12)).foregroundStyle(Theme.tag)
    case .string(let s):
      Text(s.trimmingCharacters(in: .whitespacesAndNewlines))
        .font(Theme.font(12))
        .foregroundStyle(Theme.foreground)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .bool(let b):
      Text(b ? "true" : "false").font(Theme.font(12)).foregroundStyle(Theme.constant).textSelection(.enabled)
    case .number(let n):
      Text(n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n))
        .font(Theme.font(12)).foregroundStyle(Theme.constant).textSelection(.enabled)
    case .object(let dict):
      if isShallow(resolved) {
        KeyValueTable(object: dict)
      } else {
        TreeView(value: resolved, level: treeLevel)
      }
    case .array:
      if isShallow(resolved) {
        // A shallow array (all scalar) — render as an index/value table.
        KeyValueTable(object: arrayAsObject(resolved))
      } else {
        TreeView(value: resolved, level: treeLevel)
      }
    }
  }

  /// Mirrors source's `JSON.parse(value)` attempt: if `value` is a string that
  /// parses to a JSON object/array, use the parsed structure.
  private var resolvedValue: JSONValue {
    if case .string(let s) = value,
       let parsed = JSONValue.parse(Data(s.utf8)),
       parsed.objectValue != nil || parsed.arrayValue != nil {
      return parsed
    }
    return value
  }

  /// Port of `utils/isShallow`: an array is shallow if no element is an
  /// object/array; an object is shallow if no value is an object/array.
  private func isShallow(_ v: JSONValue) -> Bool {
    switch v {
    case .array(let items):
      return !items.contains { $0.objectValue != nil || $0.arrayValue != nil }
    case .object(let dict):
      return !dict.values.contains { $0.objectValue != nil || $0.arrayValue != nil }
    default:
      return true
    }
  }

  private func arrayAsObject(_ v: JSONValue) -> [String: JSONValue] {
    guard case .array(let items) = v else { return [:] }
    var out: [String: JSONValue] = [:]
    for (i, item) in items.enumerated() { out[String(i)] = item }
    return out
  }
}
