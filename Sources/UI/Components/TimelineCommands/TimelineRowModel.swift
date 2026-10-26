import SwiftUI
import Foundation

// MARK: - TimelineRowModel — pure resolver for title/preview/color derivation

/// Maps a `Command` to display metadata (title, preview, titleColor).
///
/// Source of truth: each case is ported from the corresponding TSX command in
/// `reactotron-core-ui/src/timelineCommands/`. Every branch below was checked
/// against that source (not just the task-brief summary table) — see
/// `.superpowers/sdd/task-10-report.md` for the list of mismatches found and
/// fixed between the brief's table and the actual TSX behavior.
///
/// `titleColor` deliberately tints WARNING/ERROR log rows (`Theme.warning` /
/// `Theme.tag`). This is a native-UX addition, not a straight port: the web
/// reference's title tag color depends only on `command.important`
/// (`components/TimelineCommand/index.tsx`'s `TitleText`), never on log
/// level — `LogCommand` renders "DEBUG"/"WARNING"/"ERROR"/"LOG" in the same
/// uncolored tag. `important` tinting itself is applied by `BaseCommandView`
/// (using `Command.important` directly), matching the reference's precedence
/// where importance always overrides.
///
/// Unknown/unhandled types (including `state.backup.response` and
/// `customCommand.register`/`unregister`, which the real
/// `timelineCommandResolver` in `index.ts` does NOT map — they're consumed
/// by the Snapshots/Custom-Commands panels instead and never reach the
/// timeline) get a best-effort title/preview here for testability, but
/// `TimelineCommandRow` does not render a row for them at all, matching
/// `timelineCommandResolver` returning `null` + the caller's `return null`.
struct TimelineRowModel {
  let title: String
  let preview: String
  let titleColor: Color

  /// Pure resolver — no side effects, safe on any payload shape.
  static func resolve(_ command: Command) -> TimelineRowModel {
    let p = command.payload
    switch command.type {

    // ---- client.intro (ClientIntroCommand/index.tsx) ----
    case "client.intro":
      return TimelineRowModel(title: "CONNECTION", preview: p["name"]?.stringValue ?? "", titleColor: .clear)

    // ---- log (LogCommand/index.tsx) ----
    case "log":
      return resolveLog(payload: p)

    // ---- api.response (ApiResponseCommand/index.tsx) ----
    case "api.response":
      return resolveApiResponse(payload: p)

    // ---- state.action.complete (StateActionCompleteCommand/index.tsx) ----
    case "state.action.complete":
      return resolveStateActionComplete(payload: p)

    // ---- state.values.change (StateValuesChangeCommand/index.tsx) ----
    case "state.values.change":
      return resolveStateValuesChange(payload: p)

    // ---- state.values.response (StateValuesResponseCommand/index.tsx) ----
    case "state.values.response":
      return TimelineRowModel(title: "STATE", preview: "", titleColor: .clear)

    // ---- state.keys.response (StateKeysResponseCommand/index.tsx) ----
    case "state.keys.response":
      return TimelineRowModel(title: "STATE KEYS", preview: "", titleColor: .clear)

    // ---- state.backup.response — NOT in timelineCommandResolver; see doc comment ----
    case "state.backup.response":
      return TimelineRowModel(title: "SNAPSHOT", preview: "Snapshot", titleColor: .clear)

    // ---- asyncStorage.mutation (AsyncStorageMutationCommand/index.tsx) ----
    case "asyncStorage.mutation":
      return resolveAsyncStorageMutation(payload: p)

    // ---- saga.task.complete (SagaTaskCompleteCommand/Stateless.tsx) ----
    case "saga.task.complete":
      return resolveSagaTaskComplete(payload: p)

    // ---- benchmark.report (BenchmarkReportCommand/index.tsx) ----
    case "benchmark.report":
      return resolveBenchmarkReport(payload: p)

    // ---- display (DisplayCommand/index.tsx) ----
    case "display":
      return resolveDisplay(payload: p)

    // ---- image (ImageCommand/index.tsx) ----
    case "image":
      return resolveImage(payload: p)

    // ---- customCommand.register / unregister — NOT in timelineCommandResolver either; see doc comment ----
    case "customCommand.register", "customCommand.unregister":
      return resolveDisplay(payload: p)

    // ---- unknown ----
    default:
      return TimelineRowModel(title: command.type, preview: "", titleColor: .clear)
    }
  }

  // MARK: - Per-type resolvers

  /// Port of `LogCommand`'s `getLevelName` + `getPreview`.
  private static func resolveLog(payload: JSONValue) -> TimelineRowModel {
    let obj = payload.objectValue
    let level = obj?["level"]?.stringValue ?? ""

    // getLevelName: debug->DEBUG, warn->WARNING, error->ERROR, else->LOG.
    let title: String
    let color: Color
    switch level {
    case "debug":
      title = "DEBUG"
      color = .clear
    case "warn":
      title = "WARNING"
      color = Theme.warning
    case "error":
      title = "ERROR"
      color = Theme.tag
    default:
      title = "LOG"
      color = .clear
    }

    return TimelineRowModel(title: title, preview: logPreview(obj?["message"]), titleColor: color)
  }

  /// Port of `LogCommand.getPreview`. String messages are sliced to 500
  /// chars (matching source exactly); object/array messages get a compact
  /// `{ key: value, … }` preview of the first 5 entries. Source picks "first
  /// 5" by JS insertion order and truncates string values to 80 chars; we
  /// sort keys instead — a documented deviation. (`JSONObject` now keeps
  /// insertion order, so this could follow source; that display change is
  /// deliberately left for its own change.)
  private static func logPreview(_ message: JSONValue?) -> String {
    guard let message else { return "" }
    switch message {
    case .null:
      return "null"
    case .string(let s):
      return String(s.prefix(500))
    case .number(let n):
      return numberText(n)
    case .bool(let b):
      return b ? "true" : "false"
    case .object(let dict):
      return compactObjectPreview(dict)
    case .array(let items):
      return compactArrayPreview(items)
    case .raw(let r):
      // `message` is on the lazy-parse spine, so this isn't reached in
      // practice; stay correct anyway.
      return logPreview(r.materialize())
    }
  }

  private static func compactObjectPreview(_ dict: JSONObject) -> String {
    let sortedPairs = dict.sorted { $0.key < $1.key }
    let shown = sortedPairs.prefix(5)
    let parts = shown.map { "\($0.key): \(compactValueText($0.value))" }
    let suffix = sortedPairs.count > shown.count ? ", …" : ""
    return "{ \(parts.joined(separator: ", "))\(suffix) }"
  }

  private static func compactArrayPreview(_ items: [JSONValue]) -> String {
    let shown = items.prefix(5)
    let parts = shown.map { compactValueText($0) }
    let suffix = items.count > shown.count ? ", …" : ""
    return "[ \(parts.joined(separator: ", "))\(suffix) ]"
  }

  private static func compactValueText(_ v: JSONValue) -> String {
    switch v {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let n): return numberText(n)
    case .string(let s): return "'\(s.count > 80 ? String(s.prefix(80)) + "…" : s)'"
    case .array, .object, .raw: return "{...}"
    }
  }

  private static func numberText(_ n: Double) -> String {
    n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
  }

  /// Port of `ApiResponseCommand`'s preview composition:
  /// `[method.toUpperCase(), cleanedUrl, operationName].filter(Boolean).join(" ")`.
  /// Status code and duration are NOT part of the preview in source — status
  /// is shown as a separate `(NNN)` suffix next to the title
  /// (`responseStatusCode` prop on `TimelineCommand`) and duration only
  /// appears in the expanded body's summary table. `ApiResponseCommandView`
  /// reads those fields directly from `command.payload` rather than via
  /// this struct.
  private static func resolveApiResponse(payload: JSONValue) -> TimelineRowModel {
    let request = payload["request"]
    let method = (request?["method"]?.stringValue ?? "").uppercased()
    let url = request?["url"]?.stringValue ?? ""
    let cleanedUrl = cleanApiUrl(url)
    let operationName = graphqlOperationName(request?["data"])

    let preview = [method, cleanedUrl, operationName]
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    return TimelineRowModel(title: "API RESPONSE", preview: preview, titleColor: .clear)
  }

  /// `request.url.replace(/^http(s):\/\/[^/]+/i, "").replace(/\?.*$/i, "")`.
  /// Source's regex literally requires "https" (the `(s)` capture group has
  /// no `?`, so plain `http://` URLs are NOT stripped there — almost
  /// certainly an upstream typo). We strip both schemes since that's
  /// obviously the intent and is strictly safer for a preview string.
  private static func cleanApiUrl(_ url: String) -> String {
    var result = url
    if let range = result.range(of: #"^https?://[^/]+"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    if let qIndex = result.firstIndex(of: "?") {
      result = String(result[..<qIndex])
    }
    return result
  }

  /// `formatOperationName`: parses `request.data` as JSON and reads `.operationName`.
  private static func graphqlOperationName(_ data: JSONValue?) -> String {
    guard let s = data?.stringValue, let d = s.data(using: .utf8) else { return "" }
    guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return "" }
    guard let name = obj["operationName"] else { return "" }
    return String(describing: name)
  }

  /// Port: `payload: { name, action, ms, diff }` (`reactotron-redux/sendAction.ts`) —
  /// `name` (not `action.type`) is what `StateActionCompleteCommand` shows as
  /// the preview. `name` is always `action.type` in practice, but reading it
  /// directly matches source and is robust even if `action` isn't an object.
  private static func resolveStateActionComplete(payload: JSONValue) -> TimelineRowModel {
    TimelineRowModel(title: "ACTION", preview: payload["name"]?.stringValue ?? "", titleColor: .clear)
  }

  /// Port of `StateValuesChangeCommand`: `hasX = !!payload.x && !Array.isArray(payload.x)`,
  /// then `"N changed" "N added" "N removed"` (only present buckets, space-joined,
  /// in that exact order). Title is "SUBSCRIPTIONS" (plural) — the salvaged
  /// draft had "SUBSCRIPTION" (singular) and summed a nonexistent `changes`
  /// array; both are fixed here.
  private static func resolveStateValuesChange(payload: JSONValue) -> TimelineRowModel {
    let obj = payload.objectValue
    var parts: [String] = []
    if isTruthyNonArray(obj?["changed"]) {
      parts.append("\(obj?["changed"]?.objectValue?.count ?? 0) changed")
    }
    if isTruthyNonArray(obj?["added"]) {
      parts.append("\(obj?["added"]?.objectValue?.count ?? 0) added")
    }
    if isTruthyNonArray(obj?["removed"]) {
      parts.append("\(obj?["removed"]?.objectValue?.count ?? 0) removed")
    }
    return TimelineRowModel(title: "SUBSCRIPTIONS", preview: parts.joined(separator: " "), titleColor: .clear)
  }

  private static func isTruthyNonArray(_ v: JSONValue?) -> Bool {
    guard let v else { return false }
    if v.isArray { return false }
    return v.isTruthy
  }

  /// Port of `AsyncStorageMutationCommand` — matches source's flat
  /// `{ action, data: { key } }` shape exactly, no fix needed.
  private static func resolveAsyncStorageMutation(payload: JSONValue) -> TimelineRowModel {
    let obj = payload.objectValue
    let action = obj?["action"]?.stringValue ?? ""

    let preview: String
    if ["setItem", "removeItem", "mergeItem"].contains(action),
       let key = obj?["data"]?["key"]?.stringValue {
      preview = "\(action): \(key)"
    } else {
      preview = action
    }

    return TimelineRowModel(title: "ASYNC STORAGE", preview: preview, titleColor: .clear)
  }

  /// Port of `Stateless.tsx`'s `${payload.triggerType} in ${payload.duration}ms` —
  /// matches source exactly (both fields are required/always-sent per
  /// `SagaTaskCompletePayload`).
  private static func resolveSagaTaskComplete(payload: JSONValue) -> TimelineRowModel {
    let obj = payload.objectValue
    let triggerType = obj?["triggerType"]?.stringValue ?? ""
    let duration = obj?["duration"]?.numberValue.map { Int($0) } ?? 0
    return TimelineRowModel(title: "SAGA", preview: "\(triggerType) in \(duration)ms", titleColor: .clear)
  }

  /// Port of `BenchmarkReportCommand`: total duration = last step's `time`,
  /// preview = `${title} in ${(total/1000).toFixed(3)}s` — matches source.
  private static func resolveBenchmarkReport(payload: JSONValue) -> TimelineRowModel {
    let obj = payload.objectValue
    let title = obj?["title"]?.stringValue ?? "Benchmark"

    var totalDuration: Double = 0
    if let steps = obj?["steps"]?.arrayValue, let last = steps.last,
       let lastTime = last["time"]?.numberValue {
      totalDuration = lastTime
    }

    let totalSeconds = String(format: "%.3f", totalDuration / 1000)
    return TimelineRowModel(title: "BENCHMARK", preview: "\(title) in \(totalSeconds)s", titleColor: .clear)
  }

  /// Port of `DisplayCommand`: `title={payload.name || "DISPLAY"}` — JS `||`
  /// treats `""` as falsy too, so an explicitly-empty name also falls back.
  private static func resolveDisplay(payload: JSONValue) -> TimelineRowModel {
    let obj = payload.objectValue
    let name = obj?["name"]?.stringValue
    let title = (name?.isEmpty == false) ? name! : "DISPLAY"
    let preview = obj?["preview"]?.stringValue ?? ""
    return TimelineRowModel(title: title, preview: preview, titleColor: .clear)
  }

  /// Port of `ImageCommand`: preview is `payload.preview`, NOT `payload.uri`
  /// (uri is only used for the actual `<Image>` in the expanded body).
  private static func resolveImage(payload: JSONValue) -> TimelineRowModel {
    let preview = payload.objectValue?["preview"]?.stringValue ?? ""
    return TimelineRowModel(title: "IMAGE", preview: preview, titleColor: .clear)
  }
}
