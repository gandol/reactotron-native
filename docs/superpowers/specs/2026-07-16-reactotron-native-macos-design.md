# Reactotron Native macOS — Design

**Date:** 2026-07-16
**Status:** Approved (pending user spec review)

## Goal

A native macOS Swift replacement for the Electron Reactotron desktop app with
identical UI, functionality, and wire protocol. Existing Reactotron clients
(`reactotron-react-native`, `reactotron-react-js`, plugins) must connect and
work **without any modification**.

Reference implementation (source of truth for all behavior, colors, layout):
`/Volumes/samsung/new_mac/opensource/reactotron`

## Scope

**In scope (full parity, single deliverable):**
- WebSocket server — full port of `reactotron-core-server` behavior
- All UI pages: Home (connections + welcome), Timeline, State (Subscriptions,
  Snapshots), React Native (Overlay, Storybook), Custom Commands, Help
- All modals: Dispatch Action, Timeline Filter, Snapshot Rename,
  Subscription Add, MCP Settings
- All 14 timeline command renderers with JSON TreeView
- Keybindings, native menu bar, footer, sidebar toggle
- MCP server (port of `reactotron-mcp`): streamable HTTP, tools, resources,
  redaction config
- Android adb integration (`adb devices`, `adb reverse`, `adb track-devices`)

**Out of scope:**
- Auto-update (Sparkle) — explicitly excluded
- Windows/Linux
- Code signing / notarization / distribution (local builds only for v1)

## Technology decisions

| Concern | Choice | Rationale |
|---|---|---|
| UI | SwiftUI, macOS 14+, Swift 6 | Replicates the flexbox-style dark panel UI with far less code than AppKit |
| WebSocket server | Network.framework (`NWListener` + `NWProtocolWebSocket`) | Native, zero dependencies, sufficient for local dev-tool traffic |
| MCP server | Official `modelcontextprotocol/swift-sdk` via SwiftPM; **fallback**: hand-rolled minimal streamable-HTTP JSON-RPC endpoint if the SDK's server-side HTTP transport is inadequate | Protocol correctness with minimal work |
| adb | `Foundation.Process` spawning `adb` | Same approach as Electron (`child_process.spawn`) |
| Settings persistence | `UserDefaults` | Native equivalent of `electron-store` |
| Project generation | XcodeGen (`project.yml`) → `xcodebuild` | Already installed; reproducible, no checked-in pbxproj churn |

## Architecture

```
Sources/
├── App/            ReactotronApp entry, window config, menu bar, keybind routing
├── Core/
│   ├── Server/     ReactotronServer, Command, JSONValue, SerializationRepair
│   ├── MCP/        McpServer, Redaction, McpTools, McpResources
│   └── Android/    AndroidDeviceManager
└── UI/
    ├── Theme/      Theme.swift (verbatim port of core-ui themes.ts)
    ├── Components/ SideBar, SideBarButton, Footer, ConnectionSelector, Header,
    │               TreeView, TreeViewDiff, TimelineCommandViews (14 types),
    │               ActionButton, Checkbox, EmptyState, Timestamp, Tooltip, RandomJoke
    ├── Pages/      HomePage (connections/welcome), TimelinePage, SubscriptionsPage,
    │               SnapshotsPage, OverlayPage, StorybookPage, CustomCommandsPage, HelpPage
    └── Modals/     DispatchActionModal, TimelineFilterModal, SnapshotRenameModal,
                    SubscriptionAddModal, McpSettingsModal
```

### Concurrency model

- `ReactotronServer` owns network I/O on a dedicated `DispatchQueue`.
- All state consumed by UI lives in `@Observable` stores on `@MainActor`;
  server events are forwarded via `Task { @MainActor in ... }`.
- `SessionStore` (MainActor): connections, selected connection, command list,
  subscriptions, snapshots, custom commands.
- `SettingsStore` (MainActor): UserDefaults-backed settings (below).

### Settings (UserDefaults keys, defaults mirror `config.ts`)

| Key | Default |
|---|---|
| `serverPort` | 9090 |
| `commandHistory` (max commands kept) | 500 |
| `mcpPort` | 4567 |
| `mcpRedactionSensitiveKeys` | `DEFAULT_REDACTION_RULES.sensitiveKeys` |
| `mcpRedactionStatePathPatterns` | `DEFAULT_REDACTION_RULES.statePathPatterns` |
| `mcpRedactionValuePatterns` | `DEFAULT_REDACTION_RULES.valuePatterns` |
| `mcpAllowClientDisable` | per `DEFAULT_SERVER_CONFIG` |
| `mcpAllowClientRemoveRules` | per `DEFAULT_SERVER_CONFIG` |

## Wire protocol (100% compatibility, port of `reactotron-core-server.ts`)

### Message format

All messages are JSON text frames over WebSocket:
`{ type, payload, important?, deltaTime?, date?, diff? }`.
Inbound messages get `connectionId`, monotonically increasing `messageId`,
parsed `date` (fallback: now), and `clientId` attached.

### Connection lifecycle

1. Client connects → stored as *partial connection*
   `{id: connectionId++, address, socket}`; emit `connect`.
2. Client sends `client.intro` with its config payload:
   - `payload.address` is set from the socket's remote address.
   - If payload has no `clientId`: server generates a GUID
     (`s4()` pattern, format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) and sends
     `{type: "setClientId", payload: <guid>}` back.
   - If payload has a `clientId` that matches existing live sockets: those old
     sockets are closed after a 500 ms delay and their connections removed
     (no `disconnect` emit for the superseded entry beyond socket close handling).
   - Connection object = intro payload merged with
     `{id, address, clientId, diff}`; emit `connectionEstablished`.
3. Every inbound message → emit `command` with the full command.
4. Socket close → remove from partial + main lists, drop that client's
   registered custom commands, emit `disconnect`.

### Server-side bookkeeping on specific inbound types

- `state.values.change` → `subscriptions = payload.changes[].path`
- `customCommand.register` / `customCommand.unregister` → per-clientId registry
- `state.backup.response` → snapshot captured (named, timestamped) in UI store
- `clear` → clears timeline

### Inbound command types (all must render in Timeline)

`client.intro`, `log` (debug/warn/error levels), `api.response`,
`state.action.complete`, `state.values.change`, `state.values.response`,
`state.keys.response`, `state.backup.response`, `asyncStorage.mutation`,
`saga.task.complete`, `benchmark.report`, `display`, `image`, `clear`,
`customCommand.register`, `customCommand.unregister`. Unknown types render
via the generic/display fallback renderer, same as core-ui.

### Outbound (server → client) commands

`setClientId`, `state.values.subscribe` (paths array),
`state.values.request`, `state.keys.request`, `state.backup.request`,
`state.restore.request`, `state.action.dispatch`, `storybook`,
`overlay`, `devtools.open`, `devtools.reload`, `custom`.
`send(type, payload, clientId?)` targets one client when `clientId` given,
otherwise broadcasts to all OPEN sockets.

### Keepalive & errors

- Ping every 30 s to all clients.
- Port in use → `portUnavailable` state; UI shows the same error treatment as
  the Electron app and lets the user change the port and retry.
- Malformed JSON payloads pass through the **serialization repair** step
  (port of `repair-serialization.ts` — fixes `Function`/`undefined`/circular
  markers); unparseable frames are dropped.

### TLS note

`reactotron-core-server` optionally supports `wss` with cert files. v1 ships
**ws only** (parity with default usage); the options surface is left in the
server API so wss can be added later without redesign.

## Data model

```swift
enum JSONValue: Sendable, Codable { null, bool, number, string, array, object }

struct Command: Identifiable, Sendable {
  let type: String
  let connectionId: Int
  let messageId: Int        // Identifiable id
  let date: Date
  let deltaTime: Double
  let important: Bool
  let payload: JSONValue
  let clientId: String?
  let diff: JSONValue?
}

struct Connection: Identifiable, Sendable {
  let id: Int
  let clientId: String
  let address: String
  // intro payload fields: name, platform, platformVersion, environment,
  // reactotronVersion, osRelease, windowWidth/Height, etc. (kept as JSONValue
  // + typed accessors for the fields the UI displays)
}
```

Command history is capped at `commandHistory` (default 500), oldest dropped.

## UI specification

Global: fixed dark theme — **verbatim color values from
`reactotron-core-ui/src/themes.ts`** (not macOS system theme). Monospace font
for code/JSON. Layout: left sidebar (collapsible) + main content + footer,
mirroring `App.tsx` structure.

- **SideBar**: buttons Home, Timeline, State, React Native, Custom Commands,
  Help — same icons: embed the original react-icons SVG path data and render
  via a minimal SVG-path→`SwiftUI.Path` parser (exact visual parity, no
  dependency), active highlighting, hidden when toggled.
- **Footer**: port display + MCP status + connection selector
  (per `Footer`/`ConnectionSelector` components).
- **HomePage**: welcome screen when no connections (logo, instructions),
  connection list when connected (port of `home/index.tsx` + `welcome.tsx`).
- **TimelinePage**: reverse-chronological command list; header with search
  toggle, filter (modal, hide per command type), reverse order, clear;
  per-command expandable rows (`TimelineCommand` per type, `BaseCommand`
  chrome: timestamp, title, preview, important tint); JSON payload rendering
  via TreeView with expand/collapse. `api.response` renderer includes
  request/response/headers tabs as in `ApiResponseCommand`.
- **SubscriptionsPage**: subscribed state paths + live values; add
  (Cmd+N modal), remove, clear all; sends `state.values.subscribe`.
- **SnapshotsPage**: capture snapshot (`state.backup.request`), list, rename
  (modal), restore (`state.restore.request`), delete.
- **OverlayPage**: image URL/params form → `overlay` command.
- **StorybookPage**: toggle storybook mode → `storybook` command.
- **CustomCommandsPage**: cards from client-registered commands with arg
  inputs → sends `custom` command with args.
- **HelpPage**: links, keybinding reference, random joke — port of `help/`.
- **Modals**: SwiftUI sheets styled to match core-ui `Modal` (dark panel,
  title, ESC to close).

### Keybindings (from `KeybindHandler.tsx`)

| Binding | Action |
|---|---|
| ⌘⇧S | Toggle sidebar |
| ⌘⇧L | Toggle timeline search |
| ⌘1…⌘5 | Home / Timeline / State / React Native / Custom Commands |
| ⌘? | Help |
| ⌘K | Clear timeline |
| ⌘N | New subscription modal (on State page) |
| ⌘D | Dispatch action modal (on State/Timeline per original) |

(Exact final list re-verified against `KeybindHandler.tsx` during implementation.)

### Menu bar

Native macOS menu replicating `main/menu.ts` entries (About, quit, edit
standard items, view/navigation shortcuts, help links).

## MCP server (port of `reactotron-mcp`)

- Streamable HTTP MCP endpoint on `mcpPort` (default 4567), start/stop from UI.
- Command ring buffer: last 500 commands.
- **Tools**: `dispatch_action`, `request_state`, `request_state_keys`,
  `swap_state`, `send_custom_command`, `list_custom_commands`, `show_overlay`,
  `clear_timeline`, `subscribe_state`, `unsubscribe_state`.
- **Resources**: `reactotron://timeline`, `reactotron://timeline/{type}`,
  `reactotron://state/current`, `reactotron://network/log` (+ any others found
  in `resources.ts` during implementation).
- **Redaction**: port of `redaction.ts` — sensitive key list, state path
  patterns, value regex patterns, client disable/remove-rules permissions;
  editable at runtime via McpSettingsModal, persisted to settings.

## Android adb integration (port of `main/utils.ts`)

- On demand & at startup: `adb devices` to list devices.
- `adb reverse tcp:<serverPort> tcp:<serverPort>` per device so Android
  devices/emulators reach the server.
- `adb track-devices` long-running process to react to device plug/unplug;
  re-apply reverse on new devices.
- `adb` missing from PATH → non-fatal: log + unobtrusive UI notice
  (Electron shows a dialog; we match with a dismissible alert).

## Error handling summary

| Failure | Behavior |
|---|---|
| Server port in use | `portUnavailable` UI state, edit port + retry |
| Malformed client JSON | repair step; drop frame if still unparseable |
| Client socket error | log, treat as close |
| adb absent/errors | non-fatal, log + notice |
| MCP port in use | MCP shows error state; Reactotron server unaffected |

## Testing

- **Unit (XCTest)**: handshake incl. clientId reuse/close-after-500ms and
  setClientId; serialization repair; Command decoding for every inbound type;
  history cap; subscription bookkeeping; redaction rules; MCP JSON-RPC
  (initialize, tools/list, tools/call, resources/read).
- **Integration**: in-process fake WebSocket client (URLSessionWebSocketTask
  against the running NWListener) driving full connect→intro→commands flows.
- **E2E (manual)**: run `apps/example-app` from the reference repo against
  the native app; verify every page against the Electron app side by side.

## Build & tooling

- `project.yml` (XcodeGen) → `Reactotron.xcodeproj`; app target macOS 14+,
  Swift 6 strict concurrency; test target.
- `xcodebuild -scheme Reactotron build test` must pass.
- Only third-party dependency (if used): `modelcontextprotocol/swift-sdk`.

## Implementation order

Full parity ships as one deliverable, built in this order (each step
verifiable against the real example app):

1. Skeleton: XcodeGen project, app shell, theme, JSONValue/Command models.
2. Core server: NWListener WS server, handshake, events, repair, tests.
3. Shell UI: sidebar, footer, navigation, Home page (welcome + connections).
4. Timeline: TreeView, BaseCommand chrome, all 14 renderers, search/filter/
   reverse/clear, filter modal.
5. State: subscriptions page + modal, snapshots page + rename modal,
   dispatch action modal.
6. React Native pages (overlay, storybook) + Custom Commands page.
7. Help page, keybindings, menu bar.
8. MCP server + settings modal + footer status.
9. adb integration.
10. Side-by-side parity pass vs Electron app + final tests.
