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

  /// Routes per `App.tsx`'s `<Routes>` — real pages land in Tasks 8–13; every
  /// case here is a placeholder until its task ports the corresponding view.
  @ViewBuilder private var pageView: some View {
    switch model.currentPage {
    case .home: Text("Home")  // Task 8
    case .timeline: Text("Timeline")  // Task 9
    case .stateSubscriptions: Text("State Subscriptions")  // Task 10
    case .stateSnapshots: Text("State Snapshots")  // Task 12
    case .nativeOverlay: Text("React Native Overlay")  // Task 13
    case .nativeStorybook: Text("React Native Storybook")  // Task 13
    case .customCommands: Text("Custom Commands")  // Task 11
    case .help: Text("Help")  // Task 14
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
    case .dispatchAction, .timelineFilter, .snapshotRename, .subscriptionAdd:
      EmptyView()
    }
  }
}
