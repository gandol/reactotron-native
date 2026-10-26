import SwiftUI
import AppKit

// MARK: - Keybinding table

/// One entry from `KeybindHandler.tsx`'s `keyMap` — kept as a single canonical
/// table so `AppCommands` (the native menu's keyboard shortcuts, below) and
/// `HelpPage` (the keystrokes reference grid — a port of `help/index.tsx`'s
/// `Keybinds()`, which reads the very same `keyMap` back out via
/// `getApplicationKeyMap()`) read from one source, exactly as the TS `keyMap`
/// object feeds both `GlobalHotKeys` and `getApplicationKeyMap()`.
///
/// Only the `command+…` sequence of each source entry is kept — the parallel
/// `ctrl+…` sequence is the Windows/Linux binding and has no macOS
/// equivalent, per the task brief.
struct AppKeybind: Identifiable {
  let id: String
  let name: String
  let group: String
  /// `+`-split tokens of the source's `command+…` sequence, e.g.
  /// `["command", "shift", "s"]` for `ToggleSidebar`.
  let tokens: [String]

  /// `?` needs Shift to type on a US layout, but SwiftUI's `.keyboardShortcut`
  /// silently drops the whole shortcut if that's not spelled out in
  /// `modifiers` — confirmed by inspecting the built app's menu bar via the
  /// Accessibility API: `OpenHelpTab` (`tokens: ["command", "?"]`, no literal
  /// `"shift"` token) showed no `AXMenuItemCmdChar` at all until `.shift` was
  /// added here. `tokens` itself stays a verbatim copy of the source sequence
  /// for `HelpPage`'s display chips — only this derived modifier set adds the
  /// implied Shift.
  var modifiers: EventModifiers {
    tokens.contains("shift") || tokens.last == "?" ? [.command, .shift] : .command
  }
  var key: KeyEquivalent { KeyEquivalent(Character(tokens.last!)) }
}

/// Verbatim port of `KeybindHandler.tsx`'s `keyMap`, macOS (`command+…`)
/// sequences only. Order matches the source object's property order, which
/// is also the order `help/index.tsx`'s `groupedKeyMap` reduce encounters
/// them in (JS preserves object insertion order) — so `grouped` below
/// reproduces the same group order and membership as the source Help page.
enum AppKeybinds {
  static let toggleSidebar = AppKeybind(
    id: "ToggleSidebar", name: "Toggle Sidebar", group: "Application",
    tokens: ["command", "shift", "s"]
  )
  static let toggleSearch = AppKeybind(
    id: "ToggleSearch", name: "Toggle Timeline Search", group: "Application",
    tokens: ["command", "shift", "l"]
  )
  static let openHomeTab = AppKeybind(
    id: "OpenHomeTab", name: "Home tab", group: "Navigation", tokens: ["command", "1"]
  )
  static let openTimelineTab = AppKeybind(
    id: "OpenTimelineTab", name: "Timeline tab", group: "Navigation", tokens: ["command", "2"]
  )
  static let openStateTab = AppKeybind(
    id: "OpenStateTab", name: "State tab", group: "Navigation", tokens: ["command", "3"]
  )
  static let openReactNativeTab = AppKeybind(
    id: "OpenReactNativeTab", name: "React Native tab", group: "Navigation", tokens: ["command", "4"]
  )
  static let openCustomCommandsTab = AppKeybind(
    id: "OpenCustomCommandsTab", name: "Custom Commands tab", group: "Navigation", tokens: ["command", "5"]
  )
  /// Source sequence is literally `"command+?"` (not `"command+shift+/"`) —
  /// kept verbatim; `?` already implies Shift on a US layout.
  static let openHelpTab = AppKeybind(
    id: "OpenHelpTab", name: "Help tab", group: "Navigation", tokens: ["command", "?"]
  )
  static let clearTimeline = AppKeybind(
    id: "ClearTimeline", name: "Clear Timeline", group: "Timeline", tokens: ["command", "k"]
  )
  static let openSubscriptionModal = AppKeybind(
    id: "OpenSubscriptionModal", name: "Open Subscription modal", group: "State", tokens: ["command", "n"]
  )
  static let openDispatchModal = AppKeybind(
    id: "OpenDispatchModal", name: "Open Dispatch modal", group: "State", tokens: ["command", "d"]
  )
  /// Not in the task brief's keybinding table, but present in the source
  /// `keyMap` (`TakeSnapshot`, group `"State"`) — added per the brief's
  /// instruction to verify against `KeybindHandler.tsx` and adjust for any
  /// difference. Wired to the same `state.backup.request` command
  /// `SnapshotsPage`'s "Add Snapshot" header action sends (the closest
  /// existing equivalent of the source's `createSnapshot()`).
  static let takeSnapshot = AppKeybind(
    id: "TakeSnapshot", name: "Take snapshot", group: "State", tokens: ["command", "s"]
  )

  static let all: [AppKeybind] = [
    toggleSidebar, toggleSearch,
    openHomeTab, openTimelineTab, openStateTab, openReactNativeTab, openCustomCommandsTab, openHelpTab,
    clearTimeline,
    openSubscriptionModal, openDispatchModal, takeSnapshot,
  ]

  /// Grouped in first-seen order — port of `help/index.tsx`'s `Keybinds()`
  /// `groupedKeyMap` reduce.
  static let grouped: [(name: String, keybinds: [AppKeybind])] = {
    var order: [String] = []
    var byGroup: [String: [AppKeybind]] = [:]
    for kb in all {
      if byGroup[kb.group] == nil { order.append(kb.group) }
      byGroup[kb.group, default: []].append(kb)
    }
    return order.map { (name: $0, keybinds: byGroup[$0]!) }
  }()
}

// MARK: - AppCommands

/// Port of both `KeybindHandler.tsx` (global keyboard shortcuts) and
/// `main/menu.ts` (the native application menu) — a SwiftUI `.keyboardShortcut`
/// attached to a menu item is exactly how AppKit surfaces a working global
/// shortcut *and* a discoverable menu entry at once, so this one `Commands`
/// conformance satisfies both source files.
///
/// Not ported from `menu.ts` (source governs, but these have no equivalent —
/// or are provided for free — in this app):
/// - The app menu's "About Reactotron"/"Quit" (⌘Q), the Edit menu's standard
///   Undo/Redo/Cut/Copy/Paste/Select All, and the Window menu's
///   Minimize/Close/Bring All to Front are all supplied automatically by
///   AppKit for any SwiftUI `App` — no code needed.
/// - "Preferences" (`configStore.openInEditor()`) has no equivalent: there is
///   no settings-file-in-editor concept here, and no Settings UI exists yet
///   to open instead (the brief's menu scope is just About/Quit for the app
///   menu, so this is intentionally omitted, not silently dropped).
/// - "Toggle Full Screen"/"Toggle Developer Tools"/zoom items in `buildViewMenu`
///   are Electron/BrowserWindow-specific (dev tools has no equivalent without
///   a WebView; full screen is already available via the standard macOS
///   green-button/Window menu).
///
/// Beyond `menu.ts` (which predates several of `KeybindHandler.tsx`'s
/// shortcuts — they only ever existed as invisible `react-hotkeys` bindings
/// with no native menu entry): the "Timeline" and "State" menus below are new
/// top-level menus, not present in `menu.ts`, added so every keybinding in
/// the table above gets a discoverable, labeled home — matching the task's
/// instruction that the menu/keybinding mechanism be unified.
struct AppCommands: Commands {
  let model: AppModel

  var body: some Commands {
    // Reactotron has no multi-window concept; freed up so `OpenSubscriptionModal`
    // below can claim ⌘N without colliding with the default "New Window".
    CommandGroup(replacing: .newItem) {}

    // Named "Navigate", not "View": AppKit treats a menu literally titled
    // "View" as the system-reserved window-tabbing menu and auto-populates
    // it with "Show Tab Bar"/"Enter Full Screen", discarding any custom
    // items placed there (confirmed by inspecting the running app's menu
    // bar via the Accessibility API — a `CommandMenu("View")` produced two
    // *separate* "View" menu-bar entries, both showing only the standard
    // tab items, with the sidebar/page-navigation buttons appearing in
    // neither). Renaming sidesteps the collision while keeping the same
    // sidebar-toggle + page-navigation content the brief describes as "View".
    CommandMenu("Navigate") {
      commandButton(AppKeybinds.toggleSidebar, label: "Toggle Sidebar") {
        model.sidebarVisible.toggle()
      }
      commandButton(AppKeybinds.toggleSearch, label: "Toggle Timeline Search", action: toggleTimelineSearch)

      Divider()

      commandButton(AppKeybinds.openHomeTab, label: "Home") { model.currentPage = .home }
      commandButton(AppKeybinds.openTimelineTab, label: "Timeline") { model.currentPage = .timeline }
      commandButton(AppKeybinds.openStateTab, label: "State") { model.currentPage = .stateSubscriptions }
      commandButton(AppKeybinds.openReactNativeTab, label: "React Native") { model.currentPage = .nativeOverlay }
      commandButton(AppKeybinds.openCustomCommandsTab, label: "Custom Commands") { model.currentPage = .customCommands }
      commandButton(AppKeybinds.openHelpTab, label: "Help") { model.currentPage = .help }
    }

    CommandMenu("Timeline") {
      commandButton(AppKeybinds.clearTimeline, label: "Clear Timeline") {
        model.session.clearSelectedConnectionCommands()
      }
    }

    CommandMenu("State") {
      commandButton(AppKeybinds.openSubscriptionModal, label: "Open Subscription Modal") {
        model.activeModal = .subscriptionAdd
      }
      commandButton(AppKeybinds.openDispatchModal, label: "Open Dispatch Modal") {
        model.activeModal = .dispatchAction(seed: nil)
      }
      commandButton(AppKeybinds.takeSnapshot, label: "Take Snapshot") {
        model.sendCommand(type: "state.backup.request", payload: .object([:]))
      }
    }

    // Replaces the default Help menu's search-field item with `menu.ts`'s
    // `buildHelpMenu` entry ("Visit on GitHub") plus the rest of
    // `help/index.tsx`'s external links, so every external link the source
    // app exposes is reachable from the native Help menu too.
    CommandGroup(replacing: .help) {
      Button("Visit on GitHub") { openExternal("https://github.com/infinitered/reactotron") }
      Divider()
      Button("Feedback") { openExternal("https://github.com/infinitered/reactotron/issues/new") }
      Button("Updates") { openExternal("https://github.com/infinitered/reactotron/releases") }
      Button("@reactotron on Twitter") { openExternal("https://twitter.com/reactotron") }
    }
  }

  /// Wraps a menu `Button` with its `AppKeybind`'s shortcut — the single
  /// mechanism that makes the binding both work globally and show up,
  /// labeled, in the menu bar.
  private func commandButton(_ keybind: AppKeybind, label: String, action: @escaping () -> Void) -> some View {
    Button(label, action: action)
      .keyboardShortcut(keybind.key, modifiers: keybind.modifiers)
  }

  /// Port of `KeybindHandler.tsx`'s `ToggleSearch` handler. The source's
  /// condition is genuinely `window.location.hash === "#/"` — the *Home*
  /// route, not Timeline — so: on Home, it toggles `isSearchOpen` in place
  /// (no navigation, matching `toggleSearch()`); on every other page
  /// (including Timeline itself) it force-opens search (`openSearch()`,
  /// which always sets `isSearchOpen = true`, per `useTimeline.ts`) and
  /// navigates to Timeline. Kept verbatim rather than "fixed" to the more
  /// intuitive "toggle only when already on Timeline" reading.
  private func toggleTimelineSearch() {
    if model.currentPage == .home {
      model.timeline.isSearchOpen.toggle()
    } else {
      model.timeline.isSearchOpen = true
      model.currentPage = .timeline
    }
  }

  private func openExternal(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }
}
