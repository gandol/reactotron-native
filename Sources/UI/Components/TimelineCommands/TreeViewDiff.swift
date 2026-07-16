import SwiftUI

/// One entry of a `state.action.complete` command's `diff` array. Port of
/// `reactotron-core-contract`'s `Difference` union
/// (`DifferenceCreate | DifferenceRemove | DifferenceChange`).
struct DiffEntry {
  let type: String // "CREATE" | "REMOVE" | "CHANGE"
  let path: [String]
  let value: JSONValue?
  let oldValue: JSONValue?

  var pathText: String { path.joined(separator: ".") }

  /// Parses `Command.diff` (a `JSONValue?` array of diff objects) into
  /// `DiffEntry`s, silently dropping any entry that isn't shaped like a
  /// `Difference` rather than crashing — matches this task's safety
  /// requirement for malformed/unexpected payloads.
  static func parse(_ diff: JSONValue?) -> [DiffEntry] {
    guard let arr = diff?.arrayValue else { return [] }
    return arr.compactMap { item in
      guard let obj = item.objectValue, let type = obj["type"]?.stringValue else { return nil }
      let path = (obj["path"]?.arrayValue ?? []).map(pathComponentText)
      return DiffEntry(type: type, path: path, value: obj["value"], oldValue: obj["oldValue"])
    }
  }

  private static func pathComponentText(_ v: JSONValue) -> String {
    if let s = v.stringValue { return s }
    if let n = v.numberValue { return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n) }
    return ""
  }
}

/// Port of `reactotron-core-ui/src/components/TreeViewDiff` — renders each
/// diff entry as a flat `path : oldValue → newValue` row, colored per
/// change type.
///
/// Source builds a `JSONTree` over a flat `path -> path` map (`hideRoot`)
/// with a custom `valueRenderer` that swaps in the colored
/// old/new-value spans — effectively a flat list dressed up in `JSONTree`'s
/// disclosure chrome (every entry sits at the same depth; there's no actual
/// nesting to disclose). This port renders that same flat list directly as
/// a `VStack`, which is simpler and produces the same information without
/// depending on `TreeView`'s disclosure-tree machinery for what is, here,
/// always a one-level list.
///
/// Colors: new/created values use `Theme.string` (source: `NewValue`, themed
/// green). Old/removed values use `Theme.tag` with strikethrough (source's
/// `RemovedValue` references `theme.delete`, a key that does not exist
/// anywhere in `themes.ts` — an upstream bug where the color silently falls
/// through to the browser default. `Theme.tag` + strikethrough is the closest
/// sane native equivalent, and is already the app's "something changed/was
/// removed" color elsewhere, e.g. the ERROR log tint.)
struct TreeViewDiff: View {
  let diff: JSONValue?

  var body: some View {
    let entries = DiffEntry.parse(diff)
    if entries.isEmpty {
      EmptyView()
    } else {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
          row(entry)
        }
      }
    }
  }

  @ViewBuilder
  private func row(_ entry: DiffEntry) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(entry.pathText)
        .foregroundStyle(Theme.tag)
      Text(":")
        .foregroundStyle(Theme.foregroundDark)
      valueText(for: entry)
    }
    .font(Theme.font(12))
  }

  @ViewBuilder
  private func valueText(for entry: DiffEntry) -> some View {
    switch entry.type {
    case "CHANGE":
      HStack(spacing: 6) {
        Text(jsonText(entry.oldValue))
          .foregroundStyle(Theme.tag)
          .strikethrough()
        Text(jsonText(entry.value))
          .foregroundStyle(Theme.string)
      }
    case "CREATE":
      Text(jsonText(entry.value))
        .foregroundStyle(Theme.string)
    case "REMOVE":
      Text(jsonText(entry.oldValue))
        .foregroundStyle(Theme.tag)
        .strikethrough()
    default:
      EmptyView()
    }
  }

  private func jsonText(_ v: JSONValue?) -> String {
    guard let v else { return "undefined" }
    return v.encodedString() ?? "null"
  }
}
