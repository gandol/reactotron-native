import SwiftUI

/// Dark sheet container — port of `reactotron-core-ui`'s `components/Modal`
/// (`react-modal` configured with the theme's overlay/panel colors). Reused by
/// every custom-content modal case in `Modal` (the `RootView.Modal` enum), each
/// of which supplies its own `title` + body via `content`.
///
/// Layout parity with the source's inline styles:
/// - Overlay: full-bleed `Theme.modalOverlay`, centered content, 40pt padding.
/// - Panel: `Theme.background`, 4pt corner radius, 20pt padding, 500pt wide,
///   monospaced theme font, `Theme.foreground` text color.
/// - Title row: 24pt, `Theme.heading`, left-aligned, normal weight (`<h1>` reset).
/// - Keystrokes row: an "ESC" chip (`Theme.backgroundHighlight` background) +
///   "Close" label, 13pt, `Theme.foreground`, `additionalKeystrokes` alongside.
///
/// Dismissal: clicking the overlay (outside the panel) or pressing ESC calls
/// `onClose` — matching `react-modal`'s defaults (`shouldCloseOnOverlayClick`
/// and `shouldCloseOnEsc` both default `true`). The panel itself swallows taps
/// so interacting with its content doesn't also dismiss it.
struct ModalChrome<Content: View, AdditionalKeystrokes: View>: View {
  let title: String
  let onClose: () -> Void
  @ViewBuilder let content: () -> Content
  @ViewBuilder let additionalKeystrokes: () -> AdditionalKeystrokes

  init(
    title: String,
    onClose: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder additionalKeystrokes: @escaping () -> AdditionalKeystrokes = { EmptyView() }
  ) {
    self.title = title
    self.onClose = onClose
    self.content = content
    self.additionalKeystrokes = additionalKeystrokes
  }

  var body: some View {
    ZStack {
      Theme.modalOverlay
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onClose() }

      panel
        .padding(40)
    }
    .onExitCommand { onClose() }
  }

  private var panel: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(Theme.font(24))
        .fontWeight(.regular)
        .foregroundStyle(Theme.heading)

      content()
        .padding(.top, 12)

      HStack(spacing: 10) {
        HStack(spacing: 8) {
          Text("ESC")
            .font(Theme.font(13))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundHighlight))
          Text("Close")
            .font(Theme.font(13))
            .foregroundStyle(Theme.foreground)
        }

        additionalKeystrokes()
      }
      .padding(.top, 20)
    }
    .padding(20)
    .frame(width: 500)
    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.background))
    .foregroundStyle(Theme.foreground)
    .contentShape(Rectangle())
    .onTapGesture {}  // swallow taps so they don't fall through to the overlay's close handler
  }
}
