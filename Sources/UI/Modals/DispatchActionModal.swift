import SwiftUI

/// Port of `reactotron-core-ui`'s `modals/DispatchActionModal`.
///
/// The source parses the textarea's contents with `eval("(" + action + ")")`
/// — permissive JS-object-literal syntax (unquoted keys, single quotes) but
/// unsafe and prone to silently throwing on typos. This port instead parses
/// strict JSON (via `JSONValue.parse`) and surfaces failures as an inline
/// error message rather than an uncaught exception, per the task brief.
/// Submitting on success closes the modal itself (matching the source's own
/// `onDispatchAction(actualAction); setAction(""); onClose()` inside its Enter
/// handler) — unlike `SubscriptionAddModal`/`SnapshotRenameModal`, which leave
/// closing to the caller.
struct DispatchActionModal: View {
  /// Non-nil when opened via the timeline's per-action "Edit and dispatch this
  /// action" button — pre-fills the editor with that action's JSON. nil (⌘D)
  /// starts from the empty skeleton below.
  var seedText: String?
  let onClose: () -> Void
  let onDispatch: (JSONValue) -> Void

  private static let emptySeed = "{\n  \"type\": \"\"\n}"

  @State private var text: String
  @State private var errorMessage: String?
  @FocusState private var focused: Bool

  init(seedText: String? = nil, onClose: @escaping () -> Void, onDispatch: @escaping (JSONValue) -> Void) {
    self.seedText = seedText
    self.onClose = onClose
    self.onDispatch = onDispatch
    _text = State(initialValue: seedText ?? Self.emptySeed)
  }

  var body: some View {
    ModalChrome(title: "Dispatch Action", onClose: onClose) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Create an action that will be dispatched to the client to run.")
          .font(Theme.font())
          .foregroundStyle(Theme.foreground)

        VStack(alignment: .leading, spacing: 0) {
          Text("ACTION")
            .font(Theme.font(13))
            .foregroundStyle(Theme.heading)

          TextEditor(text: $text)
            .font(Theme.font(16))
            .foregroundStyle(Theme.foregroundLight)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(minHeight: 40, idealHeight: 150, maxHeight: 300)
            .overlay(alignment: .bottom) {
              Rectangle().fill(Theme.line).frame(height: 1)
            }
            .focused($focused)

          if let errorMessage {
            Text(errorMessage)
              .font(Theme.font(12))
              .foregroundStyle(Theme.warning)
              .padding(.top, 4)
          }
        }
        .padding(.top, 15)
      }
    } additionalKeystrokes: {
      KeystrokeContainer {
        Keystroke("⌘ + ENTER")
        Text("Dispatch")
          .font(Theme.font(13))
          .foregroundStyle(Theme.foreground)
      }
    }
    .onAppear { focused = true }
    .overlay(alignment: .topTrailing) {
      // Invisible button carrying the ⌘+Return shortcut — SwiftUI's
      // `TextEditor` doesn't expose an onKeyDown/onSubmit hook the way
      // `TextField` does, so the source's textarea-scoped `onKeyDown` handler
      // becomes a modal-wide keyboard shortcut instead.
      Button(action: handleDispatch) { EmptyView() }
        .keyboardShortcut(.return, modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
    }
  }

  private func handleDispatch() {
    guard let data = text.data(using: .utf8), let parsed = JSONValue.parse(data) else {
      errorMessage = "Invalid JSON — couldn't parse the action."
      return
    }
    errorMessage = nil
    onDispatch(parsed)
    text = ""
    onClose()
  }
}
