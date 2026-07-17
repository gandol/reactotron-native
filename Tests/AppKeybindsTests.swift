import XCTest
import SwiftUI
@testable import Reactotron

// MARK: - AppKeybinds table
//
// Verifies the canonical keybinding table (`Sources/App/AppCommands.swift`)
// against `KeybindHandler.tsx`'s `keyMap` — the macOS `command+…` sequences,
// names, and group membership/order it was ported from.

final class AppKeybindsTests: XCTestCase {

  func testAllTwelveSourceBindingsPresent() {
    XCTAssertEqual(AppKeybinds.all.count, 12)
  }

  func testGroupsMatchSourceOrderAndMembership() {
    let groups = AppKeybinds.grouped
    XCTAssertEqual(groups.map(\.name), ["Application", "Navigation", "Timeline", "State"])
    XCTAssertEqual(groups.map { $0.keybinds.count }, [2, 6, 1, 3])
  }

  func testToggleSidebarSequence() {
    let kb = AppKeybinds.toggleSidebar
    XCTAssertEqual(kb.tokens, ["command", "shift", "s"])
    XCTAssertEqual(kb.modifiers, [.command, .shift])
    XCTAssertEqual(kb.key, KeyEquivalent("s"))
  }

  func testOpenHelpTabUsesLiteralQuestionMarkToken() {
    // Source sequence is literally "command+?" (`tokens` has no "shift"
    // entry) — kept verbatim for HelpPage's display chips. `modifiers` still
    // derives [.command, .shift] though, since "?" requires Shift to type
    // and SwiftUI drops shortcuts missing that from `modifiers` entirely
    // (confirmed against the running app; see the doc comment on
    // `AppKeybind.modifiers`).
    let kb = AppKeybinds.openHelpTab
    XCTAssertEqual(kb.tokens, ["command", "?"])
    XCTAssertEqual(kb.modifiers, [.command, .shift])
    XCTAssertEqual(kb.key, KeyEquivalent("?"))
  }

  func testTakeSnapshotIsCommandSOnlyNoShift() {
    // Distinguishes it from ToggleSidebar's ⌘⇧S.
    let kb = AppKeybinds.takeSnapshot
    XCTAssertEqual(kb.tokens, ["command", "s"])
    XCTAssertEqual(kb.modifiers, .command)
    XCTAssertEqual(kb.group, "State")
  }

  func testNavigationTabSequencesAreCommandPlusDigit() {
    let expected: [(AppKeybind, String)] = [
      (AppKeybinds.openHomeTab, "1"),
      (AppKeybinds.openTimelineTab, "2"),
      (AppKeybinds.openStateTab, "3"),
      (AppKeybinds.openReactNativeTab, "4"),
      (AppKeybinds.openCustomCommandsTab, "5"),
    ]
    for (kb, digit) in expected {
      XCTAssertEqual(kb.tokens, ["command", digit])
      XCTAssertEqual(kb.modifiers, .command)
    }
  }
}

// MARK: - appVersionString

final class AppVersionStringTests: XCTestCase {
  func testReturnsShortVersionStringWhenPresent() {
    XCTAssertEqual(appVersionString(infoDictionary: ["CFBundleShortVersionString": "3.11.0"]), "3.11.0")
  }

  func testFallsBackWhenMissing() {
    XCTAssertEqual(appVersionString(infoDictionary: [:]), "0.0.0")
  }

  func testFallsBackWhenNil() {
    XCTAssertEqual(appVersionString(infoDictionary: nil), "0.0.0")
  }

  func testFallsBackWhenEmptyString() {
    XCTAssertEqual(appVersionString(infoDictionary: ["CFBundleShortVersionString": ""]), "0.0.0")
  }
}
