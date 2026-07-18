import Foundation

/// Parses `adb devices` output into ready-to-tunnel serials.
///
/// Port of the parsing done in `AndroidDeviceHelp.tsx`'s `device-list`
/// IPC handler (reactotron-app renderer): normalize line endings, trim,
/// split into lines, drop the first line (`List of devices attached`),
/// then split each remaining line on a tab into `[id, state]`.
///
/// The Electron renderer keeps every state (it just displays them), since
/// the reverse tunnel there is a manual, per-device button click. This
/// port auto-reverses every device on every refresh (see
/// `AndroidDeviceManager`), so — unlike the Electron source — the parser
/// filters to `state == "device"`: `offline`, `unauthorized`, and
/// `no permissions` devices can't accept `adb reverse` and would just
/// fail noisily on every device-list change.
///
/// Pulled out as a free function (no process/IO) so it's directly
/// testable without spawning `adb` or a device.
enum AndroidDeviceParser {
  static func parseDevices(_ output: String) -> [String] {
    let normalized = output
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return [] }

    var lines = normalized.components(separatedBy: "\n")
    lines.removeFirst() // "List of devices attached" header line.

    return lines.compactMap { line in
      let parts = line.components(separatedBy: "\t")
      guard parts.count >= 2 else { return nil }
      let serial = parts[0].trimmingCharacters(in: .whitespaces)
      let state = parts[1].trimmingCharacters(in: .whitespaces)
      guard !serial.isEmpty, state == "device" else { return nil }
      return serial
    }
  }
}

/// Where the `adb` binary was resolved from.
enum AdbLocation: Equatable {
  /// Invoke through `/usr/bin/env adb`, letting the environment's PATH
  /// resolve it fresh on every call — mirrors Electron's
  /// `spawn("adb", [...], { shell: true })`.
  case path
  /// An explicit absolute path, found under `$ANDROID_HOME/platform-tools`
  /// or `$ANDROID_SDK_ROOT/platform-tools`. utils.ts itself never reads
  /// either variable (it relies solely on the shell's PATH), but a
  /// GUI-launched macOS app's PATH is typically far narrower than an
  /// interactive shell's, so this fallback exists to avoid a needless
  /// "adb not found" notice on machines that do have the SDK installed.
  case explicit(String)
}

/// Mirrors reactotron-app's Electron main-process `adb` integration
/// (`apps/reactotron-app/src/main/utils.ts` + `AndroidDeviceHelp.tsx`):
/// list Android devices via `adb devices`, `adb reverse` a tcp tunnel per
/// device so an on-device Reactotron client can reach the Mac's server,
/// and keep a long-running `adb track-devices` process running so
/// plugging/unplugging a device re-applies the pass.
///
/// All adb process/IO work happens on `queue`; `onNotice` is invoked from
/// that queue, so callers (AppModel) must hop to the main actor
/// themselves — this type is intentionally not MainActor-bound so it
/// never blocks the UI on process spawns or pipe reads.
final class AndroidDeviceManager: @unchecked Sendable {
  /// Invoked with a human-readable, dismissible notice when adb is
  /// unavailable or a spawn fails. Mirrors Electron's
  /// `dialog.showMessageBox` warning — never fatal, shown at most once
  /// per `start()`.
  var onNotice: @Sendable (String) -> Void = { _ in }

  private let queue = DispatchQueue(label: "com.reactotron.android")

  // MARK: - queue-confined state
  private var trackProcess: Process?
  private var noticeShown = false
  private var stopped = true

  func start(serverPort: Int) {
    queue.async { [weak self] in
      guard let self else { return }
      // Idempotent: a caller retrying start() (e.g. SideBar's port-unavailable
      // retry) must never leave a prior track-devices process running
      // unreachable by stop(). Tear down any existing one before spawning.
      self.teardownTrackProcess()
      self.stopped = false
      self.noticeShown = false
      self.runInitialPassAndTrack(serverPort: serverPort)
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      self.stopped = true
      self.teardownTrackProcess()
    }
  }

  /// Terminates and releases the current track-devices process, if any.
  /// Queue-confined — always called from within a `queue.async` block, so
  /// this is the single synchronized place `trackProcess` is torn down.
  private func teardownTrackProcess() {
    if let pipe = trackProcess?.standardOutput as? Pipe {
      pipe.fileHandleForReading.readabilityHandler = nil
    }
    trackProcess?.terminate()
    trackProcess = nil
  }

  // MARK: - Pass orchestration (queue-confined)

  private func runInitialPassAndTrack(serverPort: Int) {
    guard let location = Self.resolveAdb() else {
      emitNoticeOnce(
        "Error occurred running adb: adb was not found. Install Android platform-tools and "
          + "ensure adb is on your PATH, or set ANDROID_HOME."
      )
      return
    }

    refreshDevicesAndReverse(location: location, serverPort: serverPort)
    startTrackDevices(location: location, serverPort: serverPort)
  }

  private func refreshDevicesAndReverse(location: AdbLocation, serverPort: Int) {
    guard let output = Self.runAdb(location, ["devices"]) else {
      emitNoticeOnce("Error occurred running adb devices.")
      return
    }
    let serials = AndroidDeviceParser.parseDevices(output)
    for serial in serials {
      _ = Self.runAdb(location, ["-s", serial, "reverse", "tcp:\(serverPort)", "tcp:\(serverPort)"])
    }
  }

  private func startTrackDevices(location: AdbLocation, serverPort: Int) {
    let process = Self.makeProcess(location, arguments: ["track-devices"])
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe() // Electron only logs stderr to console; we discard it.

    process.terminationHandler = { [weak self] proc in
      guard let self else { return }
      self.queue.async {
        // Identity check, not just `stopped`: a repeat start() tears down
        // and replaces `trackProcess` before this fires, so an old
        // process's own termination must not be mistaken for the new
        // process (or any process) having crashed.
        guard self.trackProcess === proc else { return }
        if proc.terminationStatus != 0 {
          self.emitNoticeOnce("adb track-devices exited unexpectedly.")
        }
      }
    }

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        // Clear on the serial queue (not this callback thread) so every
        // mutation touching track-devices process/pipe state is
        // synchronized through one place.
        self?.queue.async { handle.readabilityHandler = nil }
        return
      }
      guard let self else { return }
      self.queue.async {
        guard !self.stopped else { return }
        self.refreshDevicesAndReverse(location: location, serverPort: serverPort)
      }
    }

    do {
      try process.run()
      trackProcess = process
    } catch {
      emitNoticeOnce("Error occurred running adb track-devices.\n\(error.localizedDescription)")
    }
  }

  private func emitNoticeOnce(_ message: String) {
    guard !noticeShown else { return }
    noticeShown = true
    onNotice(message)
  }

  // MARK: - adb resolution & spawning (stateless, safe off-queue too)

  /// Tries PATH first (`/usr/bin/env adb version`); falls back to
  /// `$ANDROID_HOME/platform-tools/adb`, then
  /// `$ANDROID_SDK_ROOT/platform-tools/adb`. Neither env var appears in
  /// utils.ts — this fallback is a deliberate addition for the native
  /// app, documented in the task report.
  static func resolveAdb() -> AdbLocation? {
    if probeAdbViaPATH() {
      return .path
    }
    if let explicitPath = resolveAdbViaAndroidHome() {
      return .explicit(explicitPath)
    }
    return nil
  }

  private static func probeAdbViaPATH() -> Bool {
    let process = makeProcess(.path, arguments: ["version"])
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return false
    }
    // Read before waiting to avoid deadlock if adb fills the pipe buffer
    // (mirrors runAdb below). This runs synchronously on `queue` at the
    // top of every start(), so a hang here would stall the whole manager.
    _ = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0
  }

  private static func resolveAdbViaAndroidHome() -> String? {
    let env = ProcessInfo.processInfo.environment
    for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
      guard let root = env[key], !root.isEmpty else { continue }
      let candidate = (root as NSString).appendingPathComponent("platform-tools/adb")
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  private static func makeProcess(_ location: AdbLocation, arguments: [String]) -> Process {
    let process = Process()
    switch location {
    case .path:
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["adb"] + arguments
    case .explicit(let path):
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
    }
    return process
  }

  /// Runs `adb <args>` synchronously, returning captured stdout, or nil on
  /// spawn failure. Best-effort: a non-zero exit (e.g. `reverse` against an
  /// offline device) still returns whatever stdout was produced.
  @discardableResult
  private static func runAdb(_ location: AdbLocation, _ args: [String]) -> String? {
    let process = makeProcess(location, arguments: args)
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return nil
    }
    // Read before waiting to avoid deadlock if adb fills the pipe buffer.
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)
  }
}
