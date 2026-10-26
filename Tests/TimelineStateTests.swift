import XCTest
@testable import Reactotron

/// Port of `contexts/Timeline/useTimeline.test.ts`'s defaults/persistence
/// cases, run against an isolated `UserDefaults` suite instead of
/// `localStorage`.
@MainActor
final class TimelineStateTests: XCTestCase {
  private let suiteName = "TimelineStateTests"
  private var defaults: UserDefaults!

  override func setUp() async throws {
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func testDefaults() {
    let state = TimelineState(defaults: defaults)
    XCTAssertFalse(state.isSearchOpen)
    XCTAssertEqual(state.search, "")
    XCTAssertFalse(state.isReversed)
    XCTAssertEqual(state.hiddenCommands, [])
    // Loading on init does not write (the source's mount effect only reads).
    XCTAssertNil(defaults.string(forKey: TimelineState.reversedOrderKey))
  }

  func testLoadsReversedOrder() {
    defaults.set("reversed", forKey: TimelineState.reversedOrderKey)
    XCTAssertTrue(TimelineState(defaults: defaults).isReversed)
  }

  func testLoadsRegularOrder() {
    defaults.set("regular", forKey: TimelineState.reversedOrderKey)
    XCTAssertFalse(TimelineState(defaults: defaults).isReversed)
  }

  func testToggleReverseWritesReversedThenRegular() {
    let state = TimelineState(defaults: defaults)
    state.isReversed.toggle()
    XCTAssertEqual(defaults.string(forKey: TimelineState.reversedOrderKey), "reversed")
    state.isReversed.toggle()
    XCTAssertEqual(defaults.string(forKey: TimelineState.reversedOrderKey), "regular")
  }

  func testReversedOrderSurvivesRelaunch() {
    TimelineState(defaults: defaults).isReversed = true
    XCTAssertTrue(TimelineState(defaults: defaults).isReversed)
  }

  func testHiddenCommandsRoundTrip() {
    TimelineState(defaults: defaults).hiddenCommands = ["log", "client.intro"]
    XCTAssertEqual(TimelineState(defaults: defaults).hiddenCommands, ["log", "client.intro"])
  }

  func testSearchStateIsNotPersisted() {
    let state = TimelineState(defaults: defaults)
    state.isSearchOpen = true
    state.search = "hello"
    let relaunched = TimelineState(defaults: defaults)
    XCTAssertFalse(relaunched.isSearchOpen)
    XCTAssertEqual(relaunched.search, "")
  }
}
