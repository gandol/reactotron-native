# Reactotron (native macOS)

A native macOS Swift/SwiftUI port of [Reactotron](https://github.com/infinitered/reactotron), the
desktop app used to inspect React Native / React apps during development. This is a from-scratch
rewrite of the Electron `reactotron-app` — same wire protocol, same port, same UI concepts — with
no Electron, no Node.js runtime, and no third-party dependencies. It talks to unmodified
`reactotron-react-native`, `reactotron-react-js`, and reactotron-plugin clients exactly the way the
Electron app does: those libraries need zero changes to connect to this app instead.

This is **not** a pixel-perfect clone of the Electron UI. It targets behavioral / protocol parity
first. See [Known limitations](#known-limitations--not-yet-at-parity) below for an honest account of
where it currently differs, and the parity report at
`.superpowers/sdd/task-17-report.md` (gitignored, local to the build machine) for the full
verification trail.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 26+ (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

No CocoaPods, no Swift Package Manager dependencies, no npm/Node.js. The whole app is Foundation +
Network + SwiftUI + AppKit + ImageIO, all from the system SDK.

## Build & run

```sh
xcodegen                                                        # generates Reactotron.xcodeproj (gitignored)
xcodebuild -project Reactotron.xcodeproj -scheme Reactotron build
open build/Debug/Reactotron.app   # or: open the app xcodebuild placed in DerivedData
```

Or open `Reactotron.xcodeproj` in Xcode after running `xcodegen` and hit Run (⌘R).

`xcodegen` must be re-run any time `project.yml` changes or new source files are added — the
generated `.xcodeproj` is gitignored on purpose (see `.gitignore`), so a fresh checkout has no
project file until you generate one.

### Running tests

```sh
xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test
```

This runs the full `ReactotronTests` XCTest bundle (unit tests only — wire-protocol parsing, JSON
value handling, timeline row resolution, redaction rules, MCP JSON-RPC handling, state store logic,
keybinding tables, Android device-list parsing, and more). As of this writing: **149 tests, all
passing.**

## How clients connect

Nothing changes on the client side. Point `reactotron-react-native`, `reactotron-react-js`, or any
`reactotron-core-client`-based plugin at the same host/port you'd use for the Electron app:

- Default port: **9090** (configurable in-app; persisted via `UserDefaults`)
- Protocol: plain `ws://` (JSON messages framed as WebSocket text frames) — see
  [Out of scope](#out-of-scope) for why there's no `wss://`/TLS variant
- On `client.intro`, the server assigns and returns a `clientId` (via `setClientId`) unless the
  client already supplies one, exactly like `reactotron-core-server`
- **Android**: when the server starts, the app automatically runs `adb reverse tcp:<port>
  tcp:<port>` for every currently-attached device and keeps it in sync as devices are plugged in or
  removed (`adb track-devices`), so an Android emulator/device reaches `localhost:9090` the same way
  it does against the Electron app. If `adb` isn't found on `PATH` or under `$ANDROID_HOME` /
  `$ANDROID_SDK_ROOT`, the app shows a non-fatal notice and continues running — Android reverse-proxy
  wiring is best-effort, not a hard requirement to use the rest of the app.

Multiple simultaneous clients are supported; a connection selector in the footer switches which
client's timeline/state you're viewing.

## MCP (Model Context Protocol) server

An optional built-in MCP server lets an AI coding assistant (Claude Code, Claude Desktop, etc.)
inspect and drive a connected app directly, without a human relaying timeline events by hand.

- Toggle on/off from the footer chip (or the MCP settings modal)
- Default port: **4567** (configurable), endpoint: `http://localhost:4567/mcp`
- Transport: a minimal HTTP/1.1 JSON-RPC server (`MinimalHTTPServer`) implementing just enough of
  the MCP "streamable HTTP" transport for a request/response exchange — `POST /mcp` with a
  JSON-RPC 2.0 body, `OPTIONS` for CORS preflight, `DELETE` as a no-op session teardown
- **10 tools**: `dispatch_action`, `request_state`, `request_state_keys`, `swap_state`,
  `send_custom_command`, `list_custom_commands`, `show_overlay`, `clear_timeline`,
  `subscribe_state`, `unsubscribe_state`
- **4 resources**: `reactotron://timeline` (summarized, newest-first), `reactotron://state/current`
  (latest cached state snapshot), `reactotron://network/log` (captured HTTP traffic), plus the
  `reactotron://timeline/{type}` resource template for full, type-filtered payloads
- **Redaction**: every tool result and resource read is passed through a redaction pass before it
  leaves the process — 40 default sensitive object-key names (passwords, tokens, cookies, auth
  headers, …), 10 default value-pattern regexes (Bearer tokens, JWTs, OpenAI/Anthropic/GitHub/
  Slack/AWS/Google/Stripe key shapes, PEM private-key blocks), plus a user-editable state-path
  redaction list — all configurable from the MCP settings modal and persisted across relaunch

To add it to an MCP client, point it at `http://localhost:4567/mcp` as a streamable-HTTP MCP server
(no auth, localhost-only — there's no bearer-token/API-key gate on the endpoint itself; redaction is
the safety net for what leaves the process, not an access-control layer on who can call it).

## Feature list (pages / capabilities at parity)

- **Home** — welcome screen, connection list, auto-select on single connection
- **Timeline** — all 12 wire-command renderers (log, api.response, state.action.complete + diff
  view, state.values.change/response, state.keys.response, display, image, benchmark.report,
  saga.task.complete, asyncStorage.mutation, client.intro), search, filter modal, reverse order,
  clear, export-to-file
- **State → Subscriptions** — add/remove path subscriptions, live-updating values
- **State → Snapshots** — capture, rename, restore state backups
- **React Native → Overlay** — image-overlay controls (opacity, sizing, margins, alignment)
- **React Native → Storybook** — storybook toggle controls
- **Custom Commands** — list and execute commands registered by the connected client, including
  typed argument forms
- **Help** — keybinding reference, external links, app version
- **Dispatch Action modal** (⌘D), **Add Subscription modal** (⌘N), **Take Snapshot** (⌘S),
  **Timeline Filter modal**, **Snapshot Rename modal**, **MCP Settings modal**
- Full native menu bar + keyboard shortcuts (12 bindings — sidebar toggle, timeline search, page
  navigation ⌘1–5/⌘?, clear timeline, dispatch/subscribe/snapshot)
- Port-conflict handling (`portUnavailable` state when the configured port is already bound)
- Disconnect / reconnect handling, including the same-`clientId` reconnect path (server closes the
  stale socket ~500ms after the new one completes `client.intro`)

## Known limitations / not yet at parity

Ported honestly, not silently patched over:

- **Timeline `isReversed` is not persisted.** The Electron app saves this to
  `localStorage.ReactotronTimelineReversedOrder`; this app resets to the default order on relaunch.
- **`subscriptionValues` is a single global list**, not scoped per selected connection. With more
  than one simultaneous client, subscription values from all clients are not distinguished the way
  the Electron app (which scopes to `selectedConnection.commands`) does.
- **Storybook branding**: the Electron app's Storybook logo PNG assets are replaced with a
  placeholder icon (no bundled image-asset pipeline was built for this).
- **Overlay / Storybook form state is page-local `@State`**, reset on navigation. The Electron app
  persists this via a React Provider that outlives page navigation.
- **No cross-client resend of overlay/storybook state** to a client that connects after the state
  was set — `sendCommand` only targets the currently selected client at the moment it's sent.
- **Custom Commands page is scoped to the selected connection.** The Electron app shows custom
  commands globally across all connected clients.
- **MCP client-permission toggles are inert.** The settings modal has "allow client to disable
  MCP" / "allow client to remove redaction rules" toggles that persist but are not wired to any
  actual per-client wire opt-out (captioned in the UI as not yet enforced) — redaction is always
  enforced server-side regardless of their state.
- **4 of the upstream MCP server's 8 resources are implemented** (`timeline`, `state/current`,
  `network/log`, and the `timeline/{type}` template) — the other 4 were out of this port's scope.
- **`WireMessage.diff` is parsed as a top-level sibling of `payload`** in the wire envelope. Real
  `reactotron-redux` traffic nests `diff` inside `payload.diff` instead. The timeline's ACTION view
  checks both locations so real client traffic still renders correctly, but the wire parser itself
  could be tightened to read `payload.diff` directly rather than relying on the view-layer
  workaround.
- **No pixel-level visual sign-off against the Electron app.** This port was built and verified in
  a sandboxed environment without Screen Recording or Accessibility permissions, so UI parity was
  checked via passing tests, live protocol round-trips, and code-level comparison against the
  Electron/React source — not side-by-side screenshots. A human at a real display running both apps
  side by side has not yet happened. See `.superpowers/sdd/task-17-report.md` for exactly what was
  and wasn't verified.

### Out of scope

- **Auto-update** (Sparkle or any other updater) — this app has no update mechanism; you rebuild
  from source
- **`wss://` / TLS** — the server only speaks plain `ws://`, matching what `reactotron-core-server`
  needs for local development but excluding secure/remote-tunnel setups

## Zero third-party dependencies

Everything is built on the system SDK: `Foundation` + `Network` (WebSocket server, HTTP/1.1 MCP
transport, `adb` process management), `SwiftUI` + `AppKit` (UI, native menu, keyboard shortcuts),
`Observation` (state stores), `ImageIO` (overlay image sizing). There is no `Package.swift`
dependency list, no CocoaPods `Podfile`, and no bundled JavaScript runtime — the JSON-RPC MCP
transport and the Reactotron wire protocol are both parsed and served with hand-written Swift, not a
vendored SDK.
