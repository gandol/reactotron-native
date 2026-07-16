import SwiftUI

enum Page: String, CaseIterable {
  case home, timeline
  case stateSubscriptions, stateSnapshots
  case nativeOverlay, nativeStorybook
  case customCommands, help
}

@MainActor @Observable
final class AppModel {
  var currentPage: Page = .home
  var sidebarVisible = true
}
