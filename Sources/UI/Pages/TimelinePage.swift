import SwiftUI
import AppKit

/// Port of `pages/timeline/index.tsx`'s `Timeline`.
///
/// Behavior verified against source, notably:
/// - **Clear** (`MdDeleteSweep`) calls `clearCommands()`, which the Standalone
///   app wires to `clearSelectedConnectionCommands` (`contexts/Standalone/
///   index.tsx`'s `<ReactotronBrain clearCommands={clearSelectedConnectionCommands}>`).
///   That handler only dispatches a local `ClearConnectionCommands` reducer
///   action (`useStandalone.ts`) — it does **not** call `sendCommand("clear", ...)`
///   or otherwise notify the connected client. So Clear here only empties the
///   local store via `AppModel.session.clearSelectedConnectionCommands()`.
/// - **Export** (`MdDownload`) serializes the *raw, unfiltered* `commands` array
///   (the same value `downloadLog` closes over — `ReactotronContext.commands`,
///   which is `selectedConnection.commands`), not the search/filter/reverse view.
/// - The search bar's label reads "Search" (not "Filter:") per the actual
///   `SearchLabel` JSX — the task brief said "Filter:" but the source disagrees;
///   source governs.
/// - The search field is debounced 300ms (port of `useDebouncedSearchInput`):
///   `searchText` is the field's local text, updated on every keystroke, and
///   `TimelineState.search` (which drives `filterCommands`) only receives it
///   after 300ms without typing (lodash `debounce`'s trailing call).
struct TimelinePage: View {
  @Environment(AppModel.self) private var model
  @FocusState private var searchFieldFocused: Bool
  /// `useDebouncedSearchInput`'s local `searchString`, seeded from the
  /// committed `search` on appear (the source's `useState(initialValue)`).
  @State private var searchText = ""
  @State private var searchDebounce: Task<Void, Never>?

  private var commands: [Command] { model.session.selectedConnection?.commands ?? [] }

  private var displayedCommands: [Command] {
    let filtered = filterCommands(
      commands, search: model.timeline.search, hidden: model.timeline.hiddenCommands
    )
    return model.timeline.isReversed ? filtered.reversed() : filtered
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Timeline", actions: headerActions)

      if model.timeline.isSearchOpen {
        searchBar
      }

      if displayedCommands.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(displayedCommands) { command in
              TimelineCommandRow(command: command)
            }
          }
        }
      }
    }
    .onAppear { searchText = model.timeline.search }
    .onChange(of: searchText) { _, newValue in scheduleSearchCommit(newValue) }
  }

  /// Trailing-edge 300ms debounce: each keystroke cancels the pending commit.
  private func scheduleSearchCommit(_ value: String) {
    searchDebounce?.cancel()
    searchDebounce = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled, model.timeline.search != value else { return }
      model.timeline.search = value
    }
  }

  // MARK: - Header

  private var headerActions: [HeaderAction] {
    [
      (icon: .mdDownload, tip: "Export Log", onTap: exportLog),
      (icon: .mdSearch, tip: "Search", onTap: { model.timeline.isSearchOpen.toggle() }),
      (icon: .mdFilterList, tip: "Filter", onTap: { model.activeModal = .timelineFilter }),
      (icon: .mdSwapVert, tip: "Reverse Order", onTap: { model.timeline.isReversed.toggle() }),
      (icon: .mdDeleteSweep, tip: "Clear", onTap: { model.session.clearSelectedConnectionCommands() }),
    ]
  }

  // MARK: - Search bar

  private var searchBar: some View {
    // Bind directly to the `TimelineState` instance (not through `$model`):
    // `AppModel.timeline` is a `let`, so `$model.timeline.search` can't form a
    // writable nested path — but `TimelineState` is itself `@Observable`, so
    // wrapping the instance directly works regardless.
    @Bindable var timelineState = model.timeline

    return HStack(spacing: 0) {
      Text("Search")
        .font(Theme.font(14))
        .foregroundStyle(Theme.foregroundDark)
        .padding(.horizontal, 10)

      TextField("", text: $searchText)
        .textFieldStyle(.plain)
        .font(Theme.font(14))
        .foregroundStyle(Theme.foregroundDark)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundSubtleDark))
        .focused($searchFieldFocused)
        .onAppear { searchFieldFocused = true }

      Button {
        // Like the source, this checks the committed (debounced) `search`, not
        // the field text. Small divergence: the source's `setSearch("")` leaves
        // its local `searchString` (and any pending debounced call) alone, so
        // stale text stays in the box; here the field and pending commit are
        // cleared too so the box matches the cleared filter.
        if timelineState.search.isEmpty {
          timelineState.isSearchOpen = false
        } else {
          searchDebounce?.cancel()
          searchText = ""
          timelineState.search = ""
        }
      } label: {
        Icon(.faTimes, size: 24, color: Theme.foregroundLight)
          .padding(10)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 4)
    .padding(.bottom, 10)
    .padding(.trailing, 10)
  }

  // MARK: - Export

  /// Port of `downloadLog`: writes the raw, unfiltered command list for the
  /// selected connection to `~/Downloads/timeline-log-<epochMillis>.json`.
  private func exportLog() {
    let json = JSONValue.array(commands.map(Self.exportedJSON))
    guard let data = try? JSONEncoder().encode(json) else { return }

    let downloadsDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Downloads")
    let epochMillis = Int64(Date().timeIntervalSince1970 * 1000)
    let url = downloadsDir.appendingPathComponent("timeline-log-\(epochMillis).json")
    try? data.write(to: url)
  }

  private static let exportDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  /// `Command` isn't `Codable` (it's a client-side model, not a wire type), so
  /// this rebuilds the same shape `JSON.stringify(command)` would produce —
  /// matching the field names in `reactotron-core-contract`'s `Command`
  /// interface, with `date` as an ISO-8601 string (`Date.prototype.toJSON`).
  private static func exportedJSON(_ command: Command) -> JSONValue {
    var fields: [String: JSONValue] = [
      "type": .string(command.type),
      "connectionId": .number(Double(command.connectionId)),
      "messageId": .number(Double(command.messageId)),
      "date": .string(exportDateFormatter.string(from: command.date)),
      "deltaTime": .number(command.deltaTime),
      "important": .bool(command.important),
      "payload": command.payload,
    ]
    if let clientId = command.clientId { fields["clientId"] = .string(clientId) }
    if let diff = command.diff { fields["diff"] = diff }
    return .object(fields)
  }

  // MARK: - Empty state

  private var emptyState: some View {
    EmptyState(icon: .mdReorder, title: "No Activity") {
      VStack(spacing: 0) {
        Text("Once your app connects and starts sending events, they will appear here.")
          .font(Theme.font())
          .padding(.horizontal, 40)

        Button(action: openQuickStartDocs) {
          Text("Check out the quick start guide here!")
            .font(Theme.font())
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundLighter))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)

        Rectangle()
          .fill(Theme.foregroundDark)
          .frame(height: 1)
          .padding(.horizontal, 10)
          .padding(.vertical, 40)

        RandomJoke()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func openQuickStartDocs() {
    NSWorkspace.shared.open(URL(string: "https://docs.infinite.red/reactotron/quick-start/react-native/")!)
  }
}

// MARK: - RandomJoke

/// Port of `reactotron-core-ui`'s `components/RandomJoke` — a static joke
/// list (copied verbatim, including the source's trailing whitespace in one
/// setup line) with one picked at random per view identity, matching the
/// source's `useRef` + mount-only `useEffect` (pick once, stable across
/// re-renders).
struct RandomJoke: View {
  private static let jokes: [(setup: String, punchline: String)] = [
    ("Why was the JavaScript developer sad?", "Because he didn't Node how to Express himself."),
    ("How does a debugger break up a fight?", "It steps in."),
    ("Why do programmers prefer dark mode?", "Because light attracts bugs!"),
    ("Why did the developer go broke?", "Because he lost his domain in a bet!"),
    ("Why did the programmer quit his job?", "Because he didn't get arrays!"),
    ("How do you comfort a JavaScript bug?", "You console it."),
    ("Why don't programmers like nature?", "It has too many bugs."),
    ("What's a debugger's favorite music?      ", "Break beats"),
    ("Why don't debuggers get along with compilers?", "They always point out each other's mistakes."),
    ("Why was the debugger bad at hide and seek?", "It always showed where the bugs were hiding."),
  ]

  @State private var index = Int.random(in: 0..<RandomJoke.jokes.count)

  var body: some View {
    VStack(spacing: 5) {
      Text(Self.jokes[index].setup)
        .font(Theme.font(14, weight: .bold))
        .foregroundStyle(Theme.foregroundDark)
      Text(Self.jokes[index].punchline)
        .font(Theme.font(14))
        .italic()
        .foregroundStyle(Theme.foregroundDark)
    }
  }
}
