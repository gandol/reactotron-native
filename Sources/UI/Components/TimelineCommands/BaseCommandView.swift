import SwiftUI
import AppKit

/// One toolbar action shown while a row is expanded. Port of the
/// `toolbar: { icon, tip, onClick }[]` prop on `TimelineCommand` —
/// `BaseCommand.tsx`'s `ActionButton`s.
///
/// Source shows the toolbar only when `isOpen` (`{isOpen && toolbar && (...)}`
/// in `components/TimelineCommand/index.tsx`), not on hover. `BaseCommandView`
/// matches that.
struct TimelineToolbarAction {
  let icon: IconName
  let tip: String
  let action: () -> Void
}

/// Port of `reactotron-core-ui`'s `TimelineCommand` (the collapsed/expanded
/// row chrome) + the `important`-tinting half of `BaseCommand.tsx`'s
/// `TitleText`. Owns its own expand/collapse state, mirroring
/// `buildTimelineCommand`'s per-row `useState(startOpen)`.
///
/// Layout is a direct port of `TopBarContainer`: timestamp, a fixed-width
/// title tag, then either the one-line preview (collapsed) or the toolbar +
/// spacer (expanded), then the disclosure chevron. Tapping anywhere in the
/// top bar toggles `isOpen`, matching `TopBarContainer`'s
/// `onClick={() => setIsOpen(!isOpen)}`.
struct BaseCommandView<Content: View>: View {
  let title: String
  let date: Date
  let preview: String
  var titleColor: Color = .clear
  var important: Bool = false
  var isTagged: Bool = false
  var responseStatusCode: Int? = nil
  var toolbar: [TimelineToolbarAction] = []
  var startOpen: Bool = false
  @ViewBuilder var content: () -> Content

  @State private var isOpen: Bool

  init(
    title: String,
    date: Date,
    preview: String,
    titleColor: Color = .clear,
    important: Bool = false,
    isTagged: Bool = false,
    responseStatusCode: Int? = nil,
    toolbar: [TimelineToolbarAction] = [],
    startOpen: Bool = false,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.date = date
    self.preview = preview
    self.titleColor = titleColor
    self.important = important
    self.isTagged = isTagged
    self.responseStatusCode = responseStatusCode
    self.toolbar = toolbar
    self.startOpen = startOpen
    self.content = content
    _isOpen = State(initialValue: startOpen)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      topBar
      if isOpen {
        content()
          .padding(.horizontal, 40)
          .padding(.bottom, 30)
      }
    }
    .background(isOpen ? Theme.backgroundSubtleLight : Theme.background)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Theme.line).frame(height: 1)
    }
  }

  private var topBar: some View {
    HStack(alignment: .top, spacing: 0) {
      Timestamp(date: date)
        .padding(.trailing, 10)
        .padding(.top, 4)

      titleTag
        .frame(width: 168, alignment: .leading)

      if !isOpen {
        Text(preview)
          .font(Theme.font())
          .foregroundStyle(Theme.highlight)
          .lineLimit(1)
          .truncationMode(.tail)
          .padding(.top, 4)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if isOpen, !toolbar.isEmpty {
        HStack(spacing: 2) {
          ForEach(Array(toolbar.enumerated()), id: \.offset) { _, item in
            Button {
              item.action()
            } label: {
              Icon(item.icon, size: 18, color: Theme.foreground)
                .padding(4)
            }
            .buttonStyle(.plain)
            .help(item.tip)
          }
        }
      }

      if isOpen {
        Spacer(minLength: 0)
      }

      Icon(isOpen ? .mdExpandLess : .mdExpandMore, size: 20, color: Theme.backgroundHighlight)
        .padding(.top, 2)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 15)
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.15)) { isOpen.toggle() }
    }
  }

  private var titleTag: some View {
    HStack(spacing: 4) {
      if isTagged {
        Icon(.mdLabel, size: 14, color: tagForeground)
      }
      Text(statusSuffixedTitle)
        .font(Theme.font())
        .lineLimit(1)
    }
    .foregroundStyle(tagForeground)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 4).fill(tagBackground))
  }

  private var statusSuffixedTitle: String {
    if let responseStatusCode { return "\(title) (\(responseStatusCode))" }
    return title
  }

  /// `$isImportant ? theme.tagComplement : theme.tag` — but when a per-type
  /// resolver supplies a non-clear `titleColor` (WARNING/ERROR log tint,
  /// a native addition — see `TimelineRowModel`'s doc comment) it wins over
  /// the plain default, while `important` always wins over both, matching
  /// source's precedence.
  private var tagForeground: Color {
    if important { return Theme.tagComplement }
    return titleColor == .clear ? Theme.tag : titleColor
  }

  /// `$isImportant ? theme.tag : "transparent"`.
  private var tagBackground: Color {
    important ? Theme.tag : .clear
  }
}

// MARK: - Clipboard

/// NSPasteboard copy helper shared by every timeline command's toolbar
/// (`copyToClipboard` prop, wired to Electron's `clipboard.writeText` at the
/// app root). Must run on the main actor — `NSPasteboard` is main-thread-only.
@MainActor
func copyToClipboard(_ text: String) {
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.setString(text, forType: .string)
}

/// Pretty-printed, key-sorted JSON text for clipboard copies — nicer than
/// `JSONValue.encodedString()`'s compact output for pasting into an editor
/// (source uses `JSON.stringify(x, null, 2)` for the same buttons). Falls
/// back to the compact encoding, and then to an empty string, rather than
/// crashing on values `JSONEncoder` can't represent.
func prettyJSON(_ value: JSONValue) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) {
    return s
  }
  return value.encodedString() ?? ""
}

/// Mirrors `components/ContentView`'s `try { checkValue = JSON.parse(value) }
/// catch { checkValue = value }`: several payload fields arrive as a
/// JSON-encoded *string* rather than already-parsed JSON (HTTP response
/// bodies, saved `request.data`). Parsing it first lets `TreeView` show real
/// structure instead of one opaque string leaf. Non-string values, and
/// strings that aren't valid JSON, pass through unchanged.
func jsonAwareValue(_ value: JSONValue) -> JSONValue {
  guard case .string(let s) = value, let data = s.data(using: .utf8),
        let parsed = JSONValue.parse(data) else { return value }
  return parsed
}
