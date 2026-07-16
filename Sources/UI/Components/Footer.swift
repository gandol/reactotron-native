import SwiftUI

/// Port of `Footer/Stateless.tsx` + `ConnectionSelector/index.tsx`.
///
/// Simplifications for this task (documented, not silent): the connection
/// row shows name/platform/address + a connected dot rather than the full
/// per-platform icon set from `connectionHelpers.ts` (`getIcon`), since that
/// pulls in icons outside Task 7's initial set. The MCP chip is display-only
/// — bound to `AppModel.mcpRunning`, a placeholder until Task 15 wires the
/// real `McpServer`.
struct Footer: View {
  @Environment(AppModel.self) private var model
  @State private var isOpen = false

  private static let mcpGreen = Color(red: 80 / 255, green: 200 / 255, blue: 120 / 255)

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        leftContent
        Spacer(minLength: 0)
        mcpGroup
        expandButton
      }
      .padding(.horizontal, 10)
      .frame(height: isOpen ? 85 : 25)
      .background(Theme.subtleLine)
    }
    .overlay(alignment: .top) {
      Rectangle().fill(Theme.chromeLine).frame(height: 1)
    }
    .shadow(color: Theme.glow, radius: 15, y: -2)
    .animation(.easeOut(duration: 0.15), value: isOpen)
  }

  // MARK: - Left side

  /// Tap-to-expand is scoped to this non-interactive area only — a port of
  /// the TSX `ContentContainer`'s `onClick={() => !isOpen && setIsOpen(true)}`,
  /// where the MCP/expand buttons call `e.stopPropagation()` to opt out.
  /// SwiftUI has no propagation-stopping equivalent that composes safely with
  /// `Button`, so instead of a container-wide `.onTapGesture` (which sat as an
  /// ancestor of `expandButton` and could re-open the footer on the same tap
  /// that just closed it), the gesture lives only on this sibling view —
  /// disjoint from the buttons, so there's no ancestor/descendant conflict.
  @ViewBuilder private var leftContent: some View {
    if isOpen {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 20) {
          ForEach(model.session.connections) { conn in
            ConnectionRow(
              connection: conn,
              isSelected: conn.clientId == model.session.selectedClientId
            ) {
              model.session.selectConnection(conn.clientId)
            }
          }
        }
      }
      .frame(height: 85)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("Port \(model.settings.serverPort) | \(model.session.connections.count) connections")
        collapsedStatusLine
      }
      .font(Theme.font(11))
      .foregroundStyle(Theme.foregroundLight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { isOpen = true }
    }
  }

  @ViewBuilder private var collapsedStatusLine: some View {
    switch model.session.serverStatus {
    case .portUnavailable:
      Text("Port \(model.settings.serverPort) unavailable.")
    case .started:
      if let selected = model.session.selectedConnection {
        Text("\(selected.connection.name ?? "Name unknown") | \(platformSummary(selected.connection))")
      } else {
        Text("Waiting for connection")
      }
    case .stopped:
      Text("Waiting for server to start")
    }
  }

  // MARK: - MCP group

  @ViewBuilder private var mcpGroup: some View {
    HStack(spacing: 2) {
      Button {
        model.mcpRunning.toggle()  // placeholder toggle; Task 15 wires the real McpServer
      } label: {
        HStack(spacing: 6) {
          Circle()
            .fill(model.mcpRunning ? Self.mcpGreen : Theme.foregroundDark)
            .frame(width: 6, height: 6)
          Text(model.mcpRunning ? "MCP :\(model.settings.mcpPort)" : "MCP")
            .font(Theme.font(11))
        }
        .foregroundStyle(model.mcpRunning ? Self.mcpGreen : Theme.foregroundDark)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(model.mcpRunning ? Self.mcpGreen.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(model.mcpRunning ? Self.mcpGreen.opacity(0.4) : Theme.chromeLine, lineWidth: 1))
      }
      .buttonStyle(.plain)

      if model.mcpRunning {
        Button {
          model.activeModal = .mcpSettings
        } label: {
          Icon(.mdSettings, size: 14, color: Theme.foregroundDark)
            .padding(4)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var expandButton: some View {
    Button {
      isOpen.toggle()
    } label: {
      Icon(.mdSwapVert, size: 18, color: Theme.foregroundLight)
    }
    .buttonStyle(.plain)
  }
}

/// Port of `ConnectionSelector/index.tsx`, simplified per Task 7 scope: name,
/// platform, address, and a connected-state dot (no per-platform icon).
private struct ConnectionRow: View {
  let connection: SessionConnection
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        ZStack(alignment: .bottomTrailing) {
          Circle()
            .fill(Theme.backgroundLighter)
            .frame(width: 32, height: 32)
            .overlay(
              Text(platformInitial)
                .font(Theme.font(14))
                .foregroundStyle(Theme.foregroundLight)
            )
          Circle()
            .fill(connection.connected ? Color.green : Theme.foregroundDark)
            .frame(width: 8, height: 8)
            .offset(x: 2, y: 2)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(connection.connection.name ?? "Name unknown")
            .font(Theme.font(12))
            .foregroundStyle(Theme.foregroundLight)
          Text(platformSummary(connection.connection))
            .font(Theme.font(11))
            .foregroundStyle(Theme.foregroundDark)
          Text(connection.connection.address)
            .font(Theme.font(10))
            .foregroundStyle(Theme.foregroundDark)
        }
      }
      .padding(.vertical, 6)
      .padding(.horizontal, isSelected ? 6 : 0)
      .background(isSelected ? Theme.backgroundHighlight.opacity(0.4) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var platformInitial: String {
    connection.connection.platform.first.map { String($0).uppercased() } ?? "?"
  }
}

/// Shared with `ConnectionRow` — a simplified stand-in for `connectionHelpers.ts`'s
/// `getPlatformName`/`getPlatformDetails` (no browser user-agent sniffing).
private func platformSummary(_ c: Connection) -> String {
  var s = c.platform.isEmpty ? "Unknown platform" : c.platform
  if let version = c.platformVersion, !version.isEmpty {
    s += " \(version)"
  }
  return s
}
