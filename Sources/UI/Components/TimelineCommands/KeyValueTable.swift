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
/// - Note: keys are sorted alphabetically. Source shows keys in
///   `Object.keys` (insertion) order; `JSONObject` now keeps that order, but
///   switching the displayed order is a separate behavior change that hasn't
///   been made yet.
struct KeyValueTable: View {
  let object: JSONObject

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      // Sorted pairs, not sorted keys + lookup (lookup is a linear scan).
      ForEach(object.sorted { $0.key < $1.key }, id: \.key) { pair in
        row(key: pair.key, value: pair.value)
      }
    }
  }

  private func row(key: String, value: JSONValue) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(key)
        .foregroundStyle(Theme.foregroundDark)
        .frame(width: 210, alignment: .leading)
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
    case .array, .object, .raw: return v.encodedString() ?? ""
    }
  }

  private func colorForValue(_ v: JSONValue) -> Color {
    switch v {
    case .null: return Theme.tag
    case .bool, .number: return Theme.constant
    case .string, .array, .object, .raw: return Theme.foreground
    }
  }
}
