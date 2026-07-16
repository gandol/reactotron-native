import SwiftUI

/// Port of `pages/state/Snapshots.tsx`.
struct SnapshotsPage: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(tabs: stateHeaderTabs(model: model, active: .stateSnapshots), actions: headerActions)

      if model.stateUI.snapshots.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.stateUI.snapshots) { snapshot in
              SnapshotRow(
                snapshot: snapshot,
                onRestore: { restore(snapshot) },
                onRename: { model.activeModal = .snapshotRename(snapshot) },
                onRemove: { model.stateUI.removeSnapshot(snapshot) }
              )
            }
          }
        }
      }
    }
  }

  // MARK: - Header

  /// Icons/tips verified against `Snapshots.tsx`'s actual header actions —
  /// the task brief names `MdAdd`/"capture" for the second action, but the
  /// source uses `MdFileDownload`/"Add Snapshot"; source governs.
  private var headerActions: [HeaderAction] {
    [
      (icon: .mdCallReceived, tip: "Copy all snapshots to clipboard", onTap: copyAllToClipboard),
      (icon: .mdFileDownload, tip: "Add Snapshot", onTap: { model.sendCommand(type: "state.backup.request", payload: .object([:])) }),
    ]
  }

  private func copyAllToClipboard() {
    let json = JSONValue.array(model.stateUI.snapshots.map(snapshotJSON))
    copyToClipboard(prettyJSON(json))
  }

  // MARK: - Restore

  /// `state.restore.request` payload verified against
  /// `useSnapshots.ts`'s `restoreSnapshot`: `{ state: snapshot.state }`.
  private func restore(_ snapshot: SnapshotItem) {
    model.sendCommand(type: "state.restore.request", payload: .object(["state": snapshot.state]))
  }

  // MARK: - Empty state

  private var emptyState: some View {
    EmptyState(icon: .mdImportExport, title: "No Snapshots") {
      Text("To take a snapshot of your current redux or mobx-state-tree store, press the Download button in the top right corner of this window.")
        .font(Theme.font())
    }
  }
}

// MARK: - Snapshot row

/// Port of `Snapshots.tsx`'s `SnapshotItem` component: a clickable header row
/// (name + 4 actions) that toggles a `TreeView` preview of `snapshot.state`
/// below it. Follows `BaseCommandView`'s established pattern for this exact
/// shape — `.onTapGesture` on the row container toggling `isOpen`, with
/// sibling `Button`s for the per-row actions (not nested inside another
/// `Button`).
private struct SnapshotRow: View {
  let snapshot: SnapshotItem
  let onRestore: () -> Void
  let onRename: () -> Void
  let onRemove: () -> Void

  @State private var isOpen = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Text(snapshot.name)
          .font(Theme.font())
          .foregroundStyle(Theme.tag)
          .frame(maxWidth: .infinity, alignment: .leading)

        actionButton(.mdCallReceived, tip: "Copy to clipboard", action: copySnapshotToClipboard)
        actionButton(.mdFileUpload, tip: "Restore Snapshot", action: onRestore)
        actionButton(.mdCreate, tip: "Rename Snapshot", action: onRename)
        actionButton(.mdDelete, tip: "Delete Snapshot", action: onRemove)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 15)
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.15)) { isOpen.toggle() }
      }

      if isOpen {
        TreeView(value: snapshot.state)
          .padding(.horizontal, 40)
          .padding(.vertical, 30)
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(Theme.line).frame(height: 1)
    }
  }

  private func actionButton(_ icon: IconName, tip: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Icon(icon, size: 24, color: Theme.foreground)
    }
    .buttonStyle(.plain)
    .padding(.leading, 10)
    .help(tip)
  }

  private func copySnapshotToClipboard() {
    copyToClipboard(prettyJSON(snapshotJSON(snapshot)))
  }
}

// MARK: - Clipboard JSON shape

/// `JSON.stringify(snapshot)` port — the source's `Snapshot` type is
/// `{ id, name, state }`; `id` here is a `UUID` rather than JS's numeric
/// counter, stringified for the same "identifies this snapshot" purpose.
private func snapshotJSON(_ snapshot: SnapshotItem) -> JSONValue {
  .object(["id": .string(snapshot.id.uuidString), "name": .string(snapshot.name), "state": snapshot.state])
}
