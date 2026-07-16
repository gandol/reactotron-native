import SwiftUI

/// Port of `reactotron-core-ui`'s `modals/SnapshotRenameModal`. Prefills the
/// text field with the snapshot's current name on appear (source's
/// `onAfterOpen`), submits on Enter, and — matching the source, which never
/// calls `onClose` from its own Enter handler — leaves closing to the caller
/// (`SnapshotsPage`'s `onRename`, mirroring `useSnapshots.ts`'s rename
/// reducer action which also flips `isSnapshotRenameModalOpen` to false as a
/// side effect of the rename itself).
struct SnapshotRenameModal: View {
  let snapshot: SnapshotItem
  let onClose: () -> Void
  let onRename: (String) -> Void

  @State private var name = ""
  @FocusState private var focused: Bool

  var body: some View {
    ModalChrome(title: "Rename Snapshot", onClose: onClose) {
      VStack(alignment: .leading, spacing: 0) {
        Text("NAME")
          .font(Theme.font(13))
          .foregroundStyle(Theme.heading)

        TextField("", text: $name)
          .textFieldStyle(.plain)
          .font(Theme.font(25))
          .foregroundStyle(Theme.foregroundLight)
          .padding(.vertical, 8)
          .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
          }
          .focused($focused)
          .onSubmit(handleSubmit)
      }
    } additionalKeystrokes: {
      KeystrokeContainer {
        Keystroke("ENTER")
        Text("Save")
          .font(Theme.font(13))
          .foregroundStyle(Theme.foreground)
      }
    }
    .onAppear {
      name = snapshot.name
      focused = true
    }
  }

  private func handleSubmit() {
    onRename(name)
    name = ""
  }
}
