import SwiftUI

enum Page: String, CaseIterable {
  case home, timeline
  case stateSubscriptions, stateSnapshots
  case nativeOverlay, nativeStorybook
  case customCommands, help
}

/// Modal presented over `RootView` via `.sheet(item:)`. Cases beyond
/// `.mcpSettings` are placeholders wired up by later tasks (8–15).
///
/// - Note: `snapshotRename` carries no payload yet — `SnapshotItem` arrives in
///   Task 12, which extends this case with an associated value.
enum Modal: Identifiable {
  case dispatchAction
  case timelineFilter
  case snapshotRename
  case subscriptionAdd
  case mcpSettings

  var id: String {
    switch self {
    case .dispatchAction: "dispatchAction"
    case .timelineFilter: "timelineFilter"
    case .snapshotRename: "snapshotRename"
    case .subscriptionAdd: "subscriptionAdd"
    case .mcpSettings: "mcpSettings"
    }
  }
}

@MainActor @Observable
final class AppModel {
  var currentPage: Page = .home
  var sidebarVisible = true
  var activeModal: Modal?

  /// Display-only until Task 15 wires up the real `McpServer`.
  var mcpRunning = false

  let settings = SettingsStore()
  let session = SessionStore()
  let server = ReactotronServer()

  init() {
    session.commandHistoryLimit = settings.commandHistory
    wireServerEvents()
  }

  private func wireServerEvents() {
    server.events.started = { [weak self] in Task { @MainActor in self?.session.serverStarted() } }
    server.events.stopped = { [weak self] in Task { @MainActor in self?.session.serverStopped() } }
    server.events.portUnavailable = { [weak self] _ in Task { @MainActor in self?.session.portUnavailable() } }
    server.events.connectionEstablished = { [weak self] conn in
      Task { @MainActor in self?.session.connectionEstablished(conn) }
    }
    server.events.disconnect = { [weak self] conn in
      Task { @MainActor in self?.session.connectionDisconnected(conn) }
    }
    server.events.command = { [weak self] cmd in
      Task { @MainActor in self?.session.commandReceived(cmd) }
    }
  }

  func startServer() { server.start(port: UInt16(settings.serverPort)) }
  func stopServer() { server.stop() }

  /// Equivalent of Electron's sendCommand — targets the selected client.
  func sendCommand(type: String, payload: JSONValue) {
    server.send(type: type, payload: payload, clientId: session.selectedClientId)
  }
}
