import SwiftUI

enum Page: String, CaseIterable {
  case home, timeline
  case stateSubscriptions, stateSnapshots
  case nativeOverlay, nativeStorybook
  case customCommands, help
}

/// Modal presented over `RootView` via `.sheet(item:)`.
enum Modal: Identifiable {
  /// Optional seed text pre-fills the JSON editor — used by the timeline's
  /// per-action "Edit and dispatch this action" toolbar button (source's
  /// `openDispatchDialog`). nil opens the empty-seed dialog (⌘D).
  case dispatchAction(seed: String? = nil)
  case timelineFilter
  case snapshotRename(SnapshotItem)
  case subscriptionAdd
  case mcpSettings

  var id: String {
    switch self {
    case .dispatchAction: "dispatchAction"
    case .timelineFilter: "timelineFilter"
    case .snapshotRename(let item): "snapshotRename-\(item.id)"
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

  /// Non-fatal Android/adb notice (adb missing, spawn failure, …), shown as
  /// a dismissible alert by `RootView`. Equivalent of Electron's
  /// `dialog.showMessageBox` warning in `utils.ts`.
  var androidNotice: String?

  let settings = SettingsStore()
  let session = SessionStore()
  let server = ReactotronServer()
  let timeline = TimelineState()
  let stateUI = StateUIStore()
  let mcp = McpServer()
  let android = AndroidDeviceManager()

  init() {
    session.commandHistoryLimit = settings.commandHistory
    mcp.attach(server: server)
    mcp.rules = Redaction.Rules(
      sensitiveKeys: settings.mcpRedactionSensitiveKeys,
      statePathPatterns: settings.mcpRedactionStatePathPatterns,
      valuePatterns: settings.mcpRedactionValuePatterns
    )
    wireServerEvents()
    android.onNotice = { [weak self] message in
      Task { @MainActor in self?.androidNotice = message }
    }
  }

  /// Toggle the MCP server (Footer chip / button). Replaces the Task 7
  /// `mcpRunning` placeholder with the real `McpServer`.
  func toggleMcp() {
    if mcp.running {
      mcp.stop()
    } else {
      mcp.start(port: settings.mcpPort)
    }
  }

  /// Persist the redaction settings and push them live into the running MCP
  /// server (port of Standalone's `updateMcpRedactionConfig`).
  func updateMcpRules(sensitiveKeys: [String], statePathPatterns: [String], valuePatterns: [String]) {
    settings.mcpRedactionSensitiveKeys = sensitiveKeys
    settings.mcpRedactionStatePathPatterns = statePathPatterns
    settings.mcpRedactionValuePatterns = valuePatterns
    mcp.rules = Redaction.Rules(
      sensitiveKeys: sensitiveKeys,
      statePathPatterns: statePathPatterns,
      valuePatterns: valuePatterns
    )
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
      // Buffer into MCP on the server queue, NOT the main actor: the buffer is
      // guarded by a lock that MCP request handlers hold while snapshotting and
      // redacting up to 500 commands. Hopping this to @MainActor made the UI
      // contend with those handlers for that lock, freezing the app whenever an
      // MCP client read the timeline while traffic was flowing.
      self?.mcp.core.buffer(cmd)
      Task { @MainActor in
        self?.session.commandReceived(cmd)
        self?.stateUI.handle(command: cmd)
      }
    }
  }

  func startServer() {
    server.start(port: UInt16(settings.serverPort))
    android.start(serverPort: settings.serverPort)
  }

  func stopServer() {
    server.stop()
    android.stop()
  }

  /// Equivalent of Electron's sendCommand — targets the selected client.
  func sendCommand(type: String, payload: JSONValue) {
    server.send(type: type, payload: payload, clientId: session.selectedClientId)
  }
}
