import SwiftUI

/// Per-view parse cache for lazy `.raw` payload subtrees (no upstream
/// equivalent — upstream values are always parsed; see `RawJSON`).
///
/// Held as `@State private var box = MaterializedJSON()` by views that render
/// a value's structure (`TreeView`'s nodes, `ContentValueView`). Timeline row
/// bodies only exist while the row is expanded (`BaseCommandView` builds
/// `content()` only when open), so the parse lives exactly as long as the
/// user is looking at it and is freed on collapse. Deliberately not
/// observable: resolving never invalidates a view.
@MainActor
final class MaterializedJSON {
  private var source: RawJSON?
  private var parsed: JSONValue = .null

  /// `value` itself unless it's `.raw`; otherwise its parse, computed once
  /// per `RawJSON` instance for this box's lifetime.
  func resolve(_ value: JSONValue) -> JSONValue {
    guard case .raw(let raw) = value else { return value }
    if source !== raw {
      source = raw
      parsed = raw.materialize()
    }
    return parsed
  }
}

/// Renders `content` with `value` resolved through its own
/// `MaterializedJSON`, so a lazy `.raw` value (a log's `stack`, a saga's
/// `children`) is parsed once per view lifetime instead of on every redraw
/// of the row that builds it. Place it inside a row's expanded content so
/// the parse is freed when the row collapses.
struct MaterializedView<Content: View>: View {
  let value: JSONValue
  @ViewBuilder let content: (JSONValue) -> Content

  @State private var box = MaterializedJSON()

  var body: some View {
    content(box.resolve(value))
  }
}
