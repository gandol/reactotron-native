import SwiftUI

/// Pure helper that produces the collapsed-node preview string for a `JSONValue`.
/// Used by `TreeView` for collapsed rows and exposed for unit testing.
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
    let parts = dict.keys.sorted().map { "\($0): …" }
    return "{\(parts.joined(separator: ", "))}"
  }
}

// MARK: - TreeView

/// Recursive disclosure tree for arbitrary JSON.  Expansion state is keyed by
/// the JSON path (dot-separated for objects, bracket-indexed for arrays).
struct TreeView: View {
  let value: JSONValue
  let level: Int
  let path: String

  @State private var expanded: Set<String> = []

  init(value: JSONValue, level: Int = 0, path: String = "root") {
    self.value = value
    self.level = level
    self.path = path
  }

  private var isExpandable: Bool {
    switch value {
    case .array, .object: true
    default: false
    }
  }

  private var isExpanded: Bool {
    expanded.contains(path)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      row
      if isExpandable && isExpanded {
        children
      }
    }
  }

  // MARK: Row

  private var row: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.15)) {
        if isExpanded {
          expanded.remove(path)
        } else {
          expanded.insert(path)
        }
      }
    } label: {
      HStack(spacing: 4) {
        disclosureIndicator
        rowContent
      }
      .padding(.leading, CGFloat(level) * 15)
    }
    .buttonStyle(.plain)
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
        label("{ \(dict.count) keys }", color: Theme.tag)
      } else {
        label(treePreview(value), color: Theme.foregroundDark)
      }
    case .array(let items):
      if isExpanded {
        label("[ \(items.count) items ]", color: Theme.tag)
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
  }

  // MARK: Children

  @ViewBuilder
  private var children: some View {
    switch value {
    case .object(let dict):
      ForEach(Array(dict.keys.sorted().enumerated()), id: \.offset) { _, key in
        if let child = dict[key] {
          HStack(spacing: 4) {
            Text(key)
              .font(Theme.font())
              .foregroundStyle(Theme.tag)
              .lineLimit(1)
            Text(":")
              .font(Theme.font())
              .foregroundStyle(Theme.foregroundDark)
            TreeView(value: child, level: level + 1, path: "\(path).\(key)")
          }
          .padding(.leading, CGFloat(level) * 15)
        }
      }
    case .array(let items):
      ForEach(Array(items.enumerated()), id: \.offset) { index, child in
        HStack(spacing: 4) {
          Text("[\(index)]")
            .font(Theme.font())
            .foregroundStyle(Theme.tag)
            .lineLimit(1)
          Text(":")
            .font(Theme.font())
            .foregroundStyle(Theme.foregroundDark)
          TreeView(value: child, level: level + 1, path: "\(path)[\(index)]")
        }
        .padding(.leading, CGFloat(level) * 15)
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
