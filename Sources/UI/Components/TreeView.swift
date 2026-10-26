import SwiftUI

/// Pure helper that produces the collapsed-node preview string for a `JSONValue`.
/// Used by `TreeView` for collapsed rows and exposed for unit testing.
///
/// Object previews are capped at the first 3 sorted keys, with `, …` appended
/// when more keys exist (e.g. `{a: …, b: …, c: …, …}`).
func treePreview(_ value: JSONValue) -> String {
  switch value {
  case .null:
    return "null"
  case .bool(let b):
    return b ? "true" : "false"
  case .number(let n):
    if n.isNaN { return "NaN" }
    return n.truncatingRemainder(dividingBy: 1) == 0
      ? String(Int(n))
      : String(n)
  case .string(let s):
    return "\"\(s)\""
  case .array(let items):
    return items.count == 1 ? "1 item" : "\(items.count) items"
  case .object(let dict):
    guard !dict.isEmpty else { return "{}" }
    let sorted = dict.keys.sorted()
    let capped = sorted.prefix(3).map { "\($0): …" }
    let suffix = sorted.count > 3 ? ", …" : ""
    return "{\(capped.joined(separator: ", "))\(suffix)}"
  }
}

// MARK: - TreeView (public root, owns expansion state)

/// Recursive disclosure tree for arbitrary JSON.  Expansion state is owned
/// at the root and shared with all descendant nodes via `@Binding`.
struct TreeView: View {
  let value: JSONValue
  let level: Int

  @State private var expanded: Set<String>

  init(value: JSONValue, level: Int = 0) {
    self.value = value
    self.level = level
    // Auto-expand the root node initially, matching reactotron-core-ui's
    // TreeView (`shouldExpandNodeInitially` with the default level), so the
    // top-level keys are visible without a click. Nested nodes stay collapsed.
    let expandsRoot: Bool
    switch value {
    case .object(let d): expandsRoot = !d.isEmpty
    case .array(let a): expandsRoot = !a.isEmpty
    default: expandsRoot = false
    }
    _expanded = State(initialValue: expandsRoot ? ["root"] : [])
  }

  var body: some View {
    _TreeNode(
      value: value,
      level: level,
      path: "root",
      keyLabel: nil,
      expanded: $expanded
    )
  }
}

// MARK: - _TreeNode (private recursive node)

/// A single tree node. Renders one row — `[disclosure] [key :] value/summary` —
/// and, when an expandable node is open, its children stacked BELOW it and
/// indented one level. The key (or `[index]`) belongs to this node's own row,
/// not to a horizontal wrapper around it, so nested containers grow downward
/// (like reactotron-core-ui's TreeView) instead of marching off to the right.
private struct _TreeNode: View {
  let value: JSONValue
  let level: Int
  let path: String
  /// The object key or `[index]` this node sits under, or nil at the root.
  let keyLabel: String?
  @Binding var expanded: Set<String>

  private var isExpandable: Bool {
    switch value {
    case .array, .object: true
    default: false
    }
  }

  private var isExpanded: Bool {
    expanded.contains(path)
  }

  @State private var isCopyHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      row
      if isExpandable && isExpanded {
        children
      }
    }
  }

  // MARK: Row

  @ViewBuilder
  private var row: some View {
    // The disclosure/label part toggles expansion via a tap gesture (NOT a
    // Button), so the sibling Copy button — which IS a Button — actually
    // receives its taps. A Button nested inside a Button never fires in
    // SwiftUI (the outer one swallows the tap), which is why an earlier
    // version's Copy button did nothing.
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        disclosureIndicator
        if let keyLabel {
          Text(keyLabel)
            .font(Theme.font())
            .foregroundStyle(Theme.tag)
            .lineLimit(1)
          Text(":")
            .font(Theme.font())
            .foregroundStyle(Theme.foregroundDark)
        }
        rowContent
      }
      .contentShape(Rectangle())
      .onTapGesture {
        guard isExpandable else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
          if isExpanded { expanded.remove(path) } else { expanded.insert(path) }
        }
      }

      // Copy button on expandable (object/array) nodes — port of
      // reactotron-core-ui TreeView's per-node `ButtonCopy`. Always visible
      // (source only dims it slightly on hover), copies the node's pretty JSON.
      if isExpandable {
        copyButton
      }
    }
    .padding(.leading, CGFloat(level) * 14)
  }

  private var copyButton: some View {
    Button {
      copyToClipboard(prettyJSON(value))
    } label: {
      Text("Copy")
        .font(Theme.font(10))
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.highlight))
        .foregroundStyle(Theme.background)
        .opacity(isCopyHovering ? 0.85 : 1)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isCopyHovering = $0 }
    .help("Copy to clipboard")
  }

  @ViewBuilder
  private var disclosureIndicator: some View {
    if isExpandable {
      Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Theme.foregroundDark)
        .frame(width: 12)
    } else {
      Spacer().frame(width: 12)
    }
  }

  @ViewBuilder
  private var rowContent: some View {
    switch value {
    case .object(let dict):
      if isExpanded {
        label("{ \(dict.count) keys }", color: Theme.foregroundDark)
      } else {
        label(treePreview(value), color: Theme.foregroundDark)
      }
    case .array(let items):
      if isExpanded {
        label("[ \(items.count) items ]", color: Theme.foregroundDark)
      } else {
        label(treePreview(value), color: Theme.foregroundDark)
      }
    case .string(let s):
      label("\"\(s)\"", color: Theme.string)
    case .number(let n):
      if n.isNaN {
        label("NaN", color: Theme.constant)
      } else {
        label(numberString(n), color: Theme.constant)
      }
    case .bool(let b):
      label(b ? "true" : "false", color: Theme.constant)
    case .null:
      label("null", color: Theme.constant)
    }
  }

  private func label(_ text: String, color: Color) -> some View {
    Text(text)
      .font(Theme.font())
      .foregroundStyle(color)
      .lineLimit(1)
      .textSelection(.enabled)
  }

  // MARK: Children (stacked below, indented one level)

  @ViewBuilder
  private var children: some View {
    switch value {
    case .object(let dict):
      let keys = dict.keys.sorted()
      ForEach(keys, id: \.self) { key in
        if let child = dict[key] {
          _TreeNode(
            value: child,
            level: level + 1,
            path: "\(path).\(key)",
            keyLabel: key,
            expanded: $expanded
          )
        }
      }
    case .array(let items):
      ForEach(Array(items.enumerated()), id: \.offset) { index, child in
        _TreeNode(
          value: child,
          level: level + 1,
          path: "\(path)[\(index)]",
          keyLabel: "[\(index)]",
          expanded: $expanded
        )
      }
    default:
      EmptyView()
    }
  }

  // MARK: Helpers

  private func numberString(_ n: Double) -> String {
    n.truncatingRemainder(dividingBy: 1) == 0
      ? String(Int(n))
      : String(n)
  }
}
