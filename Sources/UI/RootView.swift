import SwiftUI

/// Port of `App.tsx`'s top-level layout: sidebar + page content + footer.
struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        SideBar()
        pageView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Footer()
    }
    .background(Theme.background)
    .sheet(item: $model.activeModal) { modal in
      modalView(for: modal)
    }
    .task {
      model.startServer()
    }
  }

  /// Routes per `App.tsx`'s `<Routes>` (ported across Tasks 8–14).
  @ViewBuilder private var pageView: some View {
    switch model.currentPage {
    case .home: HomePage()
    case .timeline: TimelinePage()
    case .stateSubscriptions: SubscriptionsPage()
    case .stateSnapshots: SnapshotsPage()
    case .nativeOverlay: OverlayPage()
    case .nativeStorybook: StorybookPage()
    case .customCommands: CustomCommandsPage()
    case .help: HelpPage()
    }
  }

  /// `.mcpSettings` gets a labeled placeholder sheet; other modal cases are
  /// filled in by the tasks that own their triggering UI.
  @ViewBuilder
  private func modalView(for modal: Modal) -> some View {
    switch modal {
    case .mcpSettings:
      Text("MCP Settings")
        .foregroundStyle(Theme.foreground)
        .padding()
        .frame(minWidth: 320, minHeight: 200)
        .background(Theme.background)
    case .timelineFilter:
      TimelineFilterModal(onClose: { model.activeModal = nil })
    case .dispatchAction:
      DispatchActionModal(
        onClose: { model.activeModal = nil },
        onDispatch: { action in
          model.sendCommand(type: "state.action.dispatch", payload: .object(["action": action]))
        }
      )
    case .subscriptionAdd:
      SubscriptionAddModal(
        onClose: { model.activeModal = nil },
        onSubscribe: { path in
          model.server.stateValuesSubscribe(path: path)
          model.activeModal = nil
        }
      )
    case .snapshotRename(let snapshot):
      SnapshotRenameModal(
        snapshot: snapshot,
        onClose: { model.activeModal = nil },
        onRename: { name in
          model.stateUI.renameSnapshot(snapshot, to: name)
          model.activeModal = nil
        }
      )
    }
  }
}
