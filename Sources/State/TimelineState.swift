import Foundation
import Observation

/// Reactotron's per-timeline UI state — search, filter-modal toggle, row order,
/// and hidden command types. Port of `contexts/Timeline/useTimeline.ts`'s reducer
/// state (the `TimelineContext` fields the Timeline page reads/writes).
///
/// `isReversed` and `hiddenCommands` persist to `UserDefaults`, mirroring the
/// source's two `localStorage` keys (`StorageKey.ReversedOrder` /
/// `StorageKey.HiddenCommands`): both are loaded in `init` (the source's
/// mount-only `useEffect`, which reads but does not write), and each is written
/// back whenever it changes (`toggleReverse` stores `"reversed"`/`"regular"`;
/// `setHiddenCommands` stores the list). `isSearchOpen`/`search` reset on each
/// launch, same as the source's in-memory `useReducer` state for those fields.
@MainActor @Observable
final class TimelineState {
  private static let hiddenCommandsKey = "hiddenCommands"
  /// Same key and `"reversed"`/`"regular"` values as `useTimeline.ts`'s
  /// `StorageKey.ReversedOrder`.
  static let reversedOrderKey = "ReactotronTimelineReversedOrder"

  @ObservationIgnored private let defaults: UserDefaults

  var isSearchOpen = false
  var search = ""

  /// Port of `toggleReverse`'s `localStorage.setItem(StorageKey.ReversedOrder,
  /// isReversed ? "reversed" : "regular")`.
  var isReversed: Bool {
    didSet {
      defaults.set(isReversed ? "reversed" : "regular", forKey: Self.reversedOrderKey)
    }
  }

  var hiddenCommands: Set<String> {
    didSet {
      defaults.set(Array(hiddenCommands), forKey: Self.hiddenCommandsKey)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // `useTimeline.ts` mount effect: anything other than "reversed" ⇒ regular.
    isReversed = defaults.string(forKey: Self.reversedOrderKey) == "reversed"
    let stored = defaults.stringArray(forKey: Self.hiddenCommandsKey) ?? []
    hiddenCommands = Set(stored)
  }
}

// MARK: - filterCommands (port of reactotron-core-ui/src/utils/filterCommands/index.ts)
//
// Verified against the source's co-located `filterCommands.test.ts`. Behavior,
// field-for-field:
//   1. `filterSearch`: trims `search`; empty ⇒ returns all commands unchanged.
//      Otherwise builds a case-insensitive regex from the (regex-escaped) search
//      text — with the *first* whitespace character in it swapped for `.` (a
//      literal port of the source's non-global `.replace(/\s/, ".")`) — and
//      tests it against 9 fixed "paths" per command: `type`,
//      `payload.message`, `payload.preview`, `payload.name`, `payload.path`,
//      `payload.triggerType`, `payload.description`, `payload.request.url`,
//      `payload.request.data`. A value only participates if it's JS-truthy;
//      strings are tested directly, everything else is `JSON.stringify`d first.
//      Two extra special cases, ported verbatim (including their quirk of
//      testing the regex against a *literal* string rather than the command's
//      own data): `log` commands also match when the search term itself
//      matches "debug"/"warning"/"error"; `client.intro` commands also match
//      when the search term matches "connection".
//   2. `filterHidden`: empty `hidden` ⇒ returns all commands unchanged;
//      otherwise drops any command whose `type` is in `hidden`.
//   3. `filterCommands` = `filterHidden(filterSearch(commands, search), hidden)`.

private let regexSpecialChars: Set<Character> = [
  ".", "*", "+", "?", "^", "$", "{", "}", "(", ")", "|", "[", "]", "\\",
]

/// Port of `utils/escape-regex.ts`'s `escapeRegex`.
func escapeRegexForSearch(_ str: String) -> String {
  var result = ""
  result.reserveCapacity(str.count)
  for ch in str {
    if regexSpecialChars.contains(ch) { result.append("\\") }
    result.append(ch)
  }
  return result
}

/// Builds the case-insensitive search regex, or `nil` for an empty/whitespace-only
/// search (meaning: no filtering). Port of the `RegExp` construction in
/// `filterSearch` — `new RegExp(escapeRegex(trimmedSearch).replace(/\s/, "."), "i")`.
private func buildTimelineSearchRegex(_ search: String) -> NSRegularExpression? {
  let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  var escaped = escapeRegexForSearch(trimmed)
  if let idx = escaped.firstIndex(where: { $0.isWhitespace }) {
    escaped.replaceSubrange(idx...idx, with: ".")
  }
  return try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive])
}

/// Port of the inline `matching(value)` closure in `filterSearch`: falsy values
/// (JS truthiness — `JSONValue.isTruthy` mirrors this exactly) never match;
/// strings are tested directly; anything else is JSON-serialized first.
///
/// `JSON.stringify` here is `JSONWriter.stringify`: insertion key order (the
/// parser keeps wire order), JS number spelling, `/` left unescaped — so a
/// search like `/users` hits an object-valued `payload.message` such as
/// `{"path":"/users/1"}`, and a search spanning two adjacent keys
/// (`"b":2,"a"`) matches exactly when it would upstream.
///
/// Lazy `.raw` payload subtrees (`RawJSON`) are searched without parsing:
/// on these paths the wire parser only leaves a subtree raw when its bytes
/// are canonical and need no repair — then they *are*
/// `JSON.stringify(JSON.parse(bytes))` (`LazyJSONPolicy`); anything else
/// (pretty-printed sender, `\/` escapes, non-JS number spelling, repair
/// markers, duplicate keys) is parsed at receive time, so the text is the
/// same either way. Residual, only reachable by a non-JS client:
/// integer-like keys keep wire order (JS would hoist them).
private func timelineSearchMatches(_ value: JSONValue?, regex: NSRegularExpression) -> Bool {
  guard let value, value.isTruthy else { return false }

  let text: String
  if case .string(let s) = value {
    text = s
  } else {
    text = JSONWriter.stringify(value)
  }

  let range = NSRange(text.startIndex..., in: text)
  return regex.firstMatch(in: text, options: [], range: range) != nil
}

/// The 9 `COMMON_MATCHING_PATHS` from the source, evaluated against one command.
private func commonMatchingValues(for command: Command) -> [JSONValue?] {
  [
    .string(command.type),
    command.payload["message"],
    command.payload["preview"],
    command.payload["name"],
    command.payload["path"],
    command.payload["triggerType"],
    command.payload["description"],
    command.payload["request"]?["url"],
    command.payload["request"]?["data"],
  ]
}

/// Port of `filterCommands/index.ts`'s exported `filterSearch`.
func filterSearch(_ commands: [Command], search: String) -> [Command] {
  guard let regex = buildTimelineSearchRegex(search) else { return commands }

  return commands.filter { command in
    if commonMatchingValues(for: command).contains(where: { timelineSearchMatches($0, regex: regex) }) {
      return true
    }
    if command.type == "log",
      timelineSearchMatches(.string("debug"), regex: regex)
        || timelineSearchMatches(.string("warning"), regex: regex)
        || timelineSearchMatches(.string("error"), regex: regex) {
      return true
    }
    if command.type == "client.intro", timelineSearchMatches(.string("connection"), regex: regex) {
      return true
    }
    return false
  }
}

/// Port of `filterCommands/index.ts`'s exported `filterHidden`.
func filterHidden(_ commands: [Command], hidden: Set<String>) -> [Command] {
  guard !hidden.isEmpty else { return commands }
  return commands.filter { !hidden.contains($0.type) }
}

/// Pure port of `filterCommands/index.ts`'s default export.
func filterCommands(_ commands: [Command], search: String, hidden: Set<String>) -> [Command] {
  filterHidden(filterSearch(commands, search: search), hidden: hidden)
}
