import Foundation
import Observation

enum ServerStatus: String { case stopped, portUnavailable, started }

@MainActor @Observable
final class SessionConnection: Identifiable {
  let clientId: String
  var connection: Connection    // latest intro data
  var commands: [Command] = []  // newest first
  var connected = true
  nonisolated var id: String { clientId }

  init(clientId: String, connection: Connection) {
    self.clientId = clientId
    self.connection = connection
  }
}

@MainActor @Observable
final class SessionStore {
  var serverStatus: ServerStatus = .stopped
  var connections: [SessionConnection] = []
  var selectedClientId: String?
  var selectedConnection: SessionConnection? { connections.first { $0.clientId == selectedClientId } }
  private var orphanedCommands: [Command] = []
  var commandHistoryLimit = 500

  func serverStarted() {
    serverStatus = .started
  }

  func serverStopped() {
    serverStatus = .stopped
  }

  func portUnavailable() {
    serverStatus = .portUnavailable
  }

  func connectionEstablished(_ connection: Connection) {
    // If a SessionConnection with same clientId exists, mark connected and update connection
    if let idx = connections.firstIndex(where: { $0.clientId == connection.clientId }) {
      connections[idx].connected = true
      connections[idx].connection = connection
    } else {
      // Otherwise, append new
      connections.append(SessionConnection(clientId: connection.clientId, connection: connection))
    }

    // Move orphaned commands whose connectionId matches this connection's id into its commands
    if let idx = connections.firstIndex(where: { $0.clientId == connection.clientId }) {
      let matching = orphanedCommands.filter { $0.connectionId == connection.id }
      for cmd in matching {
        connections[idx].commands.append(cmd)
      }
      orphanedCommands.removeAll { $0.connectionId == connection.id }
    }

    // If exactly one connected connection exists, auto-select it
    let connectedCount = connections.filter { $0.connected }.count
    if connectedCount == 1 {
      selectedClientId = connections.first(where: { $0.connected })?.clientId
    }

    // Set serverStatus to started
    serverStatus = .started
  }

  func connectionDisconnected(_ connection: Connection) {
    // Mark connected = false (keep it and its commands)
    if let idx = connections.firstIndex(where: { $0.clientId == connection.clientId }) {
      connections[idx].connected = false

      // If it was selected, select first still-connected connection, else nil
      if selectedClientId == connection.clientId {
        if let firstConnected = connections.first(where: { $0.connected }) {
          selectedClientId = firstConnected.clientId
        } else {
          selectedClientId = nil
        }
      }
    }
  }

  func commandReceived(_ command: Command) {
    // No clientId -> push to orphanedCommands
    if command.clientId == nil {
      orphanedCommands.append(command)
      return
    }

    // Unknown clientId -> log and drop
    guard let idx = connections.firstIndex(where: { $0.clientId == command.clientId }) else {
      NSLog("Received command for unknown clientId: \(command.clientId ?? "nil")")
      return
    }

    // Prepend and trim to commandHistoryLimit
    connections[idx].commands.insert(command, at: 0)
    if connections[idx].commands.count > commandHistoryLimit {
      connections[idx].commands = Array(connections[idx].commands.prefix(commandHistoryLimit))
    }
  }

  func clearSelectedConnectionCommands() {
    if let idx = connections.firstIndex(where: { $0.clientId == selectedClientId }) {
      connections[idx].commands.removeAll()
    }
  }

  func selectConnection(_ clientId: String) {
    // Only if that clientId exists
    if connections.contains(where: { $0.clientId == clientId }) {
      selectedClientId = clientId
    }
  }
}
