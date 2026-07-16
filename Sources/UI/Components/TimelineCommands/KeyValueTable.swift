import SwiftUI

/// Port of `reactotron-core-ui/src/utils/makeTable.tsx` — a flat key/value
/// list (as opposed to a recursive disclosure tree). Used at the specific
/// call sites where source renders `makeTable`/`makeTableWithContentView`
/// rather than a full `ContentView`: `ClientIntroCommand` (the whole intro
/// payload) and `AsyncStorageMutationCommand` (the mutation's `data` object).
///
/// `textForValue`/coloring port `makeTable.tsx`'s `textForValue` +
/// `ValueContainer`'s per-type color exactly (null/undefined -> tag color,
/// bool/number -> constant color, string/default -> foreground).
///
/// - Note: `JSONValue.objectValue` is a plain `[String: JSONValue]` — this
///   codebase does not track JS's insertion order anywhere — so keys are
///   sorted alphabetically for deterministic output instead. Source shows
///   keys in `Object.keys` (insertion) order.
struct KeyValueTable: View {
  let object: [String: JSONValue]

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(object.keys.sorted(), id: \.self) { key in
        row(key: key, value: object[key] ?? .null)
      }
    }
  }

  private func row(key: String, value: JSONValue) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(key)
        .foregroundStyle(Theme.foregroundDark)
        .frame(width: 150, alignment: .leading)
      Text(textForValue(value))
        .foregroundStyle(colorForValue(value))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(Theme.font(12))
    .textSelection(.enabled)
  }

  private func textForValue(_ v: JSONValue) -> String {
    switch v {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
    case .string(let s): return s
    case .array, .object: return v.encodedString() ?? ""
    }
  }

  private func colorForValue(_ v: JSONValue) -> Color {
    switch v {
    case .null: return Theme.tag
    case .bool, .number: return Theme.constant
    case .string, .array, .object: return Theme.foreground
    }
  }
}
