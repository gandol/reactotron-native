import SwiftUI

/// Port of `pages/customCommands/index.tsx`.
///
/// Scoped to `session.selectedConnection?.customCommands` per the task brief.
/// This is a deliberate divergence from the source, which accumulates custom
/// commands from every connected client into one global, unscoped list
/// (`lib/reactotron-core-ui/src/contexts/CustomCommands/useCustomCommands.ts`
/// subscribes via a global `addCommandListener`, keyed by `clientId` only for
/// bookkeeping) — same "scope to the selected connection" tradeoff already
/// made for `SubscriptionsPage` (see `StateUIStore`'s doc comment for the
/// precedent and its multi-client caveat).
struct CustomCommandsPage: View {
  @Environment(AppModel.self) private var model
  @State private var isSearchOpen = false
  @State private var search = ""

  private var customCommands: [CustomCommand] {
    model.session.selectedConnection?.customCommands ?? []
  }

  private var filteredCustomCommands: [CustomCommand] {
    guard !search.isEmpty else { return customCommands }
    let q = search.lowercased()
    return customCommands.filter {
      $0.command.lowercased().contains(q)
        || ($0.title ?? "").lowercased().contains(q)
        || ($0.description ?? "").lowercased().contains(q)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Custom Commands", actions: headerActions)

      if isSearchOpen {
        searchBar
      }

      if customCommands.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredCustomCommands.enumerated()), id: \.offset) { _, cc in
              CustomCommandCard(customCommand: cc, onSend: sendCustomCommand)
            }
          }
          .padding(.horizontal, 40)
          .padding(.top, 20)
        }
      }
    }
  }

  // MARK: - Header

  private var headerActions: [HeaderAction] {
    [(icon: .mdSearch, tip: "Search", onTap: { isSearchOpen.toggle() })]
  }

  private var searchBar: some View {
    HStack(spacing: 0) {
      Text("Search")
        .font(Theme.font(14))
        .foregroundStyle(Theme.foregroundDark)
        .padding(.horizontal, 10)

      TextField("", text: $search)
        .textFieldStyle(.plain)
        .font(Theme.font(14))
        .foregroundStyle(Theme.foregroundDark)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundSubtleDark))
    }
    .padding(.leading, 10)
    .padding(.trailing, 10)
    .padding(.top, 4)
    .padding(.bottom, 10)
  }

  // MARK: - Send

  /// Port of `CustomCommandsContext`'s `sendCustomCommand`: `sendCommand("custom",
  /// { command, args })`.
  private func sendCustomCommand(_ command: String, _ args: [String: JSONValue]) {
    model.sendCommand(type: "custom", payload: .object(["command": .string(command), "args": .object(args)]))
  }

  // MARK: - Empty state

  private var emptyState: some View {
    EmptyState(icon: .faMagic, title: "No Custom Commands") {
      Text("When your app registers a custom command it will show here!")
        .font(Theme.font())
    }
  }
}

// MARK: - CustomCommandItem

/// Port of `CustomCommandItem`: title/description with fallbacks, one text
/// field per declared arg (each initialized to `""`, matching the source's
/// `useReducer` initializer), and a Send button.
private struct CustomCommandCard: View {
  let customCommand: CustomCommand
  let onSend: (String, [String: JSONValue]) -> Void

  @State private var argValues: [String: String] = [:]

  private var displayTitle: String {
    guard let title = customCommand.title, !title.isEmpty else { return customCommand.command }
    return title
  }

  private var displayDescription: String {
    guard let description = customCommand.description, !description.isEmpty else {
      return "No Description Provided"
    }
    return description
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(displayTitle)
        .font(Theme.font(24))
        .foregroundStyle(Theme.foreground)
        .padding(.bottom, 12)

      Text(displayDescription)
        .font(Theme.font())
        .foregroundStyle(Theme.foreground)
        .padding(.bottom, 12)

      if !customCommand.args.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(customCommand.args, id: \.name) { arg in
            VStack(alignment: .leading, spacing: 8) {
              Text(arg.name)
                .font(Theme.font())
                .foregroundStyle(Theme.foreground)
              TextField(arg.name, text: binding(for: arg.name))
                .textFieldStyle(.plain)
                .font(Theme.font(16))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                .foregroundStyle(Color.black)
            }
          }
        }
        .padding(.bottom, 24)
      }

      Button(action: send) {
        Text("Send Command")
          .font(Theme.font())
          .foregroundStyle(Color.white)
          .frame(width: 200, height: 50)
          .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundLighter))
      }
      .buttonStyle(.plain)
      .padding(.bottom, 24)
    }
  }

  private func binding(for name: String) -> Binding<String> {
    Binding(get: { argValues[name] ?? "" }, set: { argValues[name] = $0 })
  }

  /// Port of `sendCustomCommand(customCommand.command, state)` — `state` is the
  /// reducer's arg map, one key per declared arg, defaulting to `""`.
  private func send() {
    var args: [String: JSONValue] = [:]
    for arg in customCommand.args {
      args[arg.name] = .string(argValues[arg.name] ?? "")
    }
    onSend(customCommand.command, args)
  }
}
