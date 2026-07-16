import SwiftUI

/// Port of `pages/state/Subscriptions.tsx`.
///
/// `subscriptionValues` (path/value pairs) come from `AppModel.stateUI`,
/// which replaces its list wholesale on every `state.values.change` command
/// — see `StateUIStore`'s doc comment for the exact wire shape and the
/// multi-client scoping caveat.
struct SubscriptionsPage: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(tabs: stateHeaderTabs(model: model, active: .stateSubscriptions), actions: headerActions)

      if model.stateUI.subscriptionValues.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(model.stateUI.subscriptionValues.enumerated()), id: \.offset) { _, pair in
              SubscriptionRow(path: pair.path, value: pair.value) {
                model.server.stateValuesUnsubscribe(path: pair.path)
              }
            }
          }
        }
      }
    }
  }

  // MARK: - Header

  private var headerActions: [HeaderAction] {
    [
      (icon: .mdAdd, tip: "Add", onTap: { model.activeModal = .subscriptionAdd }),
      (icon: .mdDeleteSweep, tip: "Clear", onTap: { model.server.stateValuesClearSubscriptions() }),
    ]
  }

  // MARK: - Empty state

  /// Verbatim source copy, minus the trailing dynamic keybind badge
  /// (`KeybindKeys`) — the global "Open Subscription Modal" shortcut is wired
  /// in Task 14, so this names the header's Add button instead.
  private var emptyState: some View {
    EmptyState(icon: .mdNotificationsNone, title: "No Subscriptions") {
      Text("You can subscribe to state changes in your redux or mobx-state-tree store by pressing the Add button above.")
        .font(Theme.font())
    }
  }
}

// MARK: - Shared State tab header

/// Port of the tab row repeated verbatim by both `Subscriptions.tsx` and
/// `Snapshots.tsx` — navigates between the two State pages.
@MainActor
func stateHeaderTabs(model: AppModel, active: Page) -> [HeaderTab] {
  [
    (
      text: "Subscriptions", icon: .mdNotificationsNone, isActive: active == .stateSubscriptions,
      onTap: { model.currentPage = .stateSubscriptions }
    ),
    (
      text: "Snapshots", icon: .mdImportExport, isActive: active == .stateSnapshots,
      onTap: { model.currentPage = .stateSnapshots }
    ),
  ]
}

// MARK: - Subscription row

/// Port of `Subscriptions.tsx`'s per-row layout (`SubscriptionPath` +
/// `SubscriptionValue` + `SubscriptionRemove`). The source's `flex: 0.3` /
/// `flex: 0.7` split is approximated with a fixed-width path column rather
/// than a `GeometryReader`-computed proportion, since `TreeView`'s per-node
/// expansion gives the row a dynamic height `GeometryReader` can't feed back
/// into cleanly. Delete is always present (matching the source) but only
/// visible/tappable on hover, per the task brief — an intentional UI
/// refinement over the source's always-visible icon.
private struct SubscriptionRow: View {
  let path: String
  let value: JSONValue
  let onRemove: () -> Void

  @State private var hovering = false

  var body: some View {
    HStack(alignment: .top, spacing: 20) {
      Text(path)
        .font(Theme.font())
        .foregroundStyle(Theme.tag)
        .textSelection(.enabled)
        .frame(width: 200, alignment: .leading)

      TreeView(value: value)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onRemove) {
        Icon(.mdDelete, size: 24, color: Theme.foreground)
      }
      .buttonStyle(.plain)
      .opacity(hovering ? 1 : 0)
      .allowsHitTesting(hovering)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 15)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Theme.line).frame(height: 1)
    }
    .onHover { hovering = $0 }
  }
}
