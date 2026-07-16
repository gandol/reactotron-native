import SwiftUI

/// Port of `StateActionCompleteCommand/index.tsx`.
///
/// Diff sourcing: source reads `payload.diff` — `StateActionCompletePayload`
/// nests `diff` inside the payload (`reactotron-redux/sendAction.ts` sends
/// `{ name, action, ms, diff }` as one object). This codebase's `Command.diff`
/// is instead populated from a top-level `diff` key on the wire envelope
/// (`ReactotronServer.swift` reads `WireMessage.diff`, a sibling of
/// `payload`), which real reactotron-redux traffic never sends — so
/// `command.diff` alone would never be populated by an actual client. This
/// view checks both `command.diff` and `command.payload["diff"]` so the Diff
/// tab works either way, without touching the existing wire-parsing code
/// (out of scope for this task — flagged in the task report for a future
/// fix at the parsing layer).
///
/// Scope note: source's second toolbar button (`MdCode`, "Edit and dispatch
/// this action") opens a dialog to hand-edit the action JSON before
/// dispatching (`openDispatchDialog`). This ports the "Repeat this action"
/// replay button only, per the brief's explicit toolbar requirement; the
/// edit-and-dispatch dialog is a larger, separate modal-flow feature.
struct StateActionCompleteCommandView: View {
  let command: Command
  @Environment(AppModel.self) private var model
  @State private var showDiff = false

  var body: some View {
    let rowModel = TimelineRowModel.resolve(command)
    let action = command.payload["action"]
    let diffValue = resolvedDiff
    let hasDiff = diffValue != nil && diffValue?.isNull == false

    BaseCommandView(
      title: rowModel.title,
      date: command.date,
      preview: rowModel.preview,
      important: command.important,
      toolbar: [
        TimelineToolbarAction(icon: .mdRepeat, tip: "Repeat this action.") {
          replay(action: action)
        }
      ]
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text(rowModel.preview)
          .font(Theme.font(12))
          .foregroundStyle(Theme.bold)
          .textSelection(.enabled)

        if hasDiff {
          HStack(spacing: 12) {
            tabButton("Preview", isActive: !showDiff) { showDiff = false }
            tabButton("Diff", isActive: showDiff) { showDiff = true }
          }
        }

        if hasDiff, showDiff {
          TreeViewDiff(diff: diffValue)
        } else if let action {
          TreeView(value: jsonAwareValue(action))
        }
      }
    }
  }

  private var resolvedDiff: JSONValue? {
    if let d = command.diff, !d.isNull { return d }
    return command.payload["diff"]
  }

  private func tabButton(_ text: String, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(text)
        .font(Theme.font(12))
        .foregroundStyle(isActive ? Theme.bold : Theme.foregroundDark)
    }
    .buttonStyle(.plain)
  }

  private func replay(action: JSONValue?) {
    model.sendCommand(type: "state.action.dispatch", payload: .object(["action": action ?? .null]))
  }
}
