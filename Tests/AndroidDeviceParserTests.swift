import XCTest
@testable import Reactotron

/// Covers `AndroidDeviceParser.parseDevices`, the pure logic pulled out of
/// `AndroidDeviceManager` so it's testable without spawning `adb`.
/// Reference behavior: `AndroidDeviceHelp.tsx`'s `device-list` handler
/// (reactotron-app), which normalizes line endings, trims, drops the
/// first line, then splits each remaining line on a tab into `[id, state]`.
final class AndroidDeviceParserTests: XCTestCase {
  /// A single device in the ready `device` state is parsed out.
  func testNormalDeviceLineParsed() {
    let output = "List of devices attached\nemulator-5554\tdevice\n"

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), ["emulator-5554"])
  }

  /// Multiple ready devices are all returned, in order.
  func testMultipleDeviceLinesParsed() {
    let output = "List of devices attached\nemulator-5554\tdevice\n1234567890ABCDEF\tdevice\n"

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), ["emulator-5554", "1234567890ABCDEF"])
  }

  /// The `List of devices attached` header is dropped positionally (like
  /// the source's `rawDevices.shift()`), regardless of its exact text.
  func testHeaderLineIgnored() {
    let output = "List of devices attached\nAB123\tdevice\n"
    let parsed = AndroidDeviceParser.parseDevices(output)

    XCTAssertEqual(parsed, ["AB123"])
    XCTAssertFalse(parsed.contains("List of devices attached"))
  }

  /// No devices connected: only the header line is present.
  func testHeaderOnlyProducesEmptyList() {
    let output = "List of devices attached\n"

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), [])
  }

  /// Fully empty stdout (e.g. adb produced nothing) never crashes and
  /// yields no devices.
  func testEmptyOutputProducesEmptyList() {
    XCTAssertEqual(AndroidDeviceParser.parseDevices(""), [])
    XCTAssertEqual(AndroidDeviceParser.parseDevices("   \n  "), [])
  }

  /// `offline`, `unauthorized`, and `no permissions` devices are filtered
  /// out: only `device`-state entries are eligible for `adb reverse`.
  func testNonReadyStatesFiltered() {
    let output = """
    List of devices attached
    emulator-5554\toffline
    1234567890ABCDEF\tunauthorized
    ZZ999\tno permissions (missing udev rules?)
    AB123\tdevice
    """

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), ["AB123"])
  }

  /// CRLF line endings and trailing whitespace/blank lines are handled.
  func testCRLFAndTrailingWhitespaceHandled() {
    let output = "List of devices attached\r\nemulator-5554\tdevice\r\n\r\n"

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), ["emulator-5554"])
  }

  /// A device line with no tab (malformed/partial output) is skipped
  /// rather than crashing the parse.
  func testMalformedLineWithoutTabIsSkipped() {
    let output = "List of devices attached\nnot-a-device-line\nAB123\tdevice\n"

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), ["AB123"])
  }

  /// All-offline output (a common state right after a device reboots)
  /// yields no reversible serials.
  func testAllOfflineProducesEmptyList() {
    let output = "List of devices attached\nemulator-5554\toffline\n"

    XCTAssertEqual(AndroidDeviceParser.parseDevices(output), [])
  }
}
