import Foundation

/// Port of `reactotron-mcp/src/redaction.ts`. Deep-walks a `JSONValue` and
/// replaces sensitive data with `[REDACTED]`:
/// - object keys matching `sensitiveKeys` (case-insensitive) → `[REDACTED]`
/// - state paths matching `statePathPatterns` (exact, or `prefix.*` wildcard) → `[REDACTED]`
/// - string values: JSON-encoded strings are parsed/redacted/re-stringified,
///   URL query and form-encoded param values whose names are sensitive are
///   redacted, and any substring matched by a `valuePatterns` regex is replaced.
enum Redaction {
  static let REDACTED = "[REDACTED]"

  // Verbatim from `DEFAULT_REDACTION_RULES.sensitiveKeys` (redaction.ts).
  static let defaultSensitiveKeys: [String] = [
    // Credentials
    "password", "passwd", "pwd",
    "secret", "client_secret", "clientsecret",
    "credentials", "ssn", "creditcard",
    "privatekey", "private_key",
    // API keys
    "apikey", "api_key", "x-api-key",
    // Auth tokens
    "accesstoken", "access_token",
    "refreshtoken", "refresh_token",
    "idtoken", "id_token",
    "token", "bearer", "jwt",
    // Session / CSRF
    "session", "sessionid", "session_id",
    "csrf", "xsrf", "csrf_token", "xsrf_token",
    // HTTP headers
    "authorization", "cookie", "set-cookie", "proxy-authorization",
    "x-auth-token", "x-csrf-token", "x-xsrf-token", "csrf-token",
    "x-forwarded-for", "x-real-ip",
  ]

  // Verbatim from `DEFAULT_REDACTION_RULES.statePathPatterns` (redaction.ts).
  static let defaultStatePathPatterns: [String] = []

  // Verbatim from `DEFAULT_REDACTION_RULES.valuePatterns` (redaction.ts).
  static let defaultValuePatterns: [String] = [
    // Bearer tokens
    "Bearer\\s+[A-Za-z0-9\\-._~+/]+=*",
    // JWTs (header.payload[.signature])
    "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}",
    // OpenAI-style keys (also matches our legacy "sk-..." pattern)
    "sk-[a-zA-Z0-9_-]{20,}",
    // Anthropic API keys
    "sk-ant-[a-zA-Z0-9_-]{20,}",
    // GitHub PATs / fine-grained tokens
    "gh[pousr]_[A-Za-z0-9]{30,}",
    // Slack tokens
    "xox[bpoas]-[a-zA-Z0-9\\-]{10,}",
    // AWS access key IDs
    "AKIA[0-9A-Z]{16}",
    // Google API keys
    "AIza[0-9A-Za-z\\-_]{35}",
    // Stripe keys (live/test, secret/publishable/restricted)
    "(?:sk|pk|rk)_(?:test|live)_[A-Za-z0-9]{24,}",
    // PEM-encoded private key blocks (RSA, EC, DSA, OPENSSH, or generic)
    "-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----[\\s\\S]+?-----END (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----",
  ]

  struct Rules: Equatable, Sendable {
    var sensitiveKeys: [String]
    var statePathPatterns: [String]
    var valuePatterns: [String]

    static let defaults = Rules(
      sensitiveKeys: defaultSensitiveKeys,
      statePathPatterns: defaultStatePathPatterns,
      valuePatterns: defaultValuePatterns
    )
  }

  /// Deep-walk `value` and return a redacted copy. `currentPath` anchors
  /// `statePathPatterns` (pass `""` for a full tree, or a dot path when the
  /// value is a subtree rooted at that path).
  static func redact(_ value: JSONValue, rules: Rules, currentPath: String = "") -> JSONValue {
    let parsed = ParsedRules(rules)
    return redactValue(value, parsed: parsed, currentPath: currentPath, jsonDepth: 0)
  }

  // MARK: - Walk

  private static let maxJSONStringDepth = 5
  private static let maxJSONParseLength = 1_000_000

  private static func redactValue(
    _ data: JSONValue, parsed: ParsedRules, currentPath: String, jsonDepth: Int
  ) -> JSONValue {
    switch data {
    case .null, .bool, .number:
      return data
    case .string(let s):
      return .string(redactString(s, parsed: parsed, jsonDepth: jsonDepth))
    case .array(let arr):
      if !parsed.trackPaths {
        return .array(arr.map { redactValue($0, parsed: parsed, currentPath: "", jsonDepth: jsonDepth) })
      }
      return .array(arr.enumerated().map { index, item in
        let childPath = currentPath.isEmpty ? String(index) : "\(currentPath).\(index)"
        return redactValue(item, parsed: parsed, currentPath: childPath, jsonDepth: jsonDepth)
      })
    case .object(let obj):
      return redactObject(obj, parsed: parsed, currentPath: currentPath, jsonDepth: jsonDepth)
    case .raw(let r):
      // Lazy wire subtree: parse it and redact the parse. The result never
      // contains `.raw`, so raw wire bytes can't leave the process unredacted.
      return redactValue(r.materialize(), parsed: parsed, currentPath: currentPath, jsonDepth: jsonDepth)
    }
  }

  /// Rebuilds the object in its original key order (keys are already unique,
  /// so pairs are appended without a lookup).
  private static func redactObject(
    _ obj: JSONObject, parsed: ParsedRules, currentPath: String, jsonDepth: Int
  ) -> JSONValue {
    var result = JSONObject()
    result.reserveCapacity(obj.count)
    for (key, value) in obj {
      // Common case first — most keys aren't path-pattern matches.
      if parsed.sensitiveKeysLower.contains(key.lowercased()) {
        result.appendUnchecked(key: key, value: .string(REDACTED))
        continue
      }
      if parsed.trackPaths {
        let childPath = currentPath.isEmpty ? key : "\(currentPath).\(key)"
        if matchesStatePath(childPath, parsed.statePathPatterns) {
          result.appendUnchecked(key: key, value: .string(REDACTED))
          continue
        }
        result.appendUnchecked(
          key: key, value: redactValue(value, parsed: parsed, currentPath: childPath, jsonDepth: jsonDepth))
      } else {
        result.appendUnchecked(
          key: key, value: redactValue(value, parsed: parsed, currentPath: "", jsonDepth: jsonDepth))
      }
    }
    return .object(result)
  }

  private static func redactString(_ value: String, parsed: ParsedRules, jsonDepth: Int) -> String {
    var result = value

    // Detect JSON strings and redact their contents by parsing → redacting →
    // re-stringifying. Guarded by depth (nested JSON layers) and size limits.
    if jsonDepth < maxJSONStringDepth, result.count <= maxJSONParseLength {
      let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
      if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
        || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
        if let parsedJSON = JSONValue.parse(Data(result.utf8)), parsedJSON.isObjectOrArray {
          let inner = redactValue(parsedJSON, parsed: parsed, currentPath: "", jsonDepth: jsonDepth + 1)
          return inner.encodedString() ?? result
        }
      }
    }

    // Redact URL query / form-encoded param values whose names are sensitive.
    if !parsed.sensitiveKeysLower.isEmpty {
      if result.contains("?") {
        result = redactUrlQueryParams(result, parsed.sensitiveKeysLower)
      } else if looksLikeFormEncoded(result) {
        result = redactFormEncodedParams(result, parsed.sensitiveKeysLower)
      }
    }

    // Replace any substrings matched by a value pattern.
    if let regex = parsed.combinedValueRegex {
      let range = NSRange(result.startIndex..<result.endIndex, in: result)
      result = regex.stringByReplacingMatches(
        in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: REDACTED)
      )
    }
    return result
  }

  private static func matchesStatePath(_ currentPath: String, _ patterns: [String]) -> Bool {
    for pattern in patterns {
      if pattern.hasSuffix(".*") {
        let prefix = String(pattern.dropLast(2))
        // "auth.tokens.*" matches "auth.tokens.access" but NOT "auth.tokens".
        if currentPath.hasPrefix(prefix + "."), currentPath.count > prefix.count + 1 {
          return true
        }
      } else if currentPath == pattern {
        return true
      }
    }
    return false
  }

  // MARK: - Form / URL param redaction

  // `^k=v(&k=v)*$` — avoids false positives on prose like "x=5".
  private static let formEncodedRegex = try? NSRegularExpression(
    pattern: #"^[\w.\-+~*\[\]%]+=[^&]*(?:&[\w.\-+~*\[\]%]+=[^&]*)*$"#
  )

  private static func looksLikeFormEncoded(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 8192, let regex = formEncodedRegex else { return false }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.firstMatch(in: value, range: range) != nil
  }

  private static func redactFormEncodedParams(_ value: String, _ sensitiveKeysLower: Set<String>) -> String {
    value.split(separator: "&", omittingEmptySubsequences: false).map { param -> String in
      guard let eq = param.firstIndex(of: "=") else { return String(param) }
      let name = param[param.startIndex..<eq]
      if sensitiveKeysLower.contains(name.lowercased()) {
        return "\(name)=\(REDACTED)"
      }
      return String(param)
    }.joined(separator: "&")
  }

  private static func redactUrlQueryParams(_ value: String, _ sensitiveKeysLower: Set<String>) -> String {
    guard let q = value.firstIndex(of: "?") else { return value }
    let base = value[value.startIndex...q]
    let afterQ = value[value.index(after: q)...]

    // Handle a fragment after the query string.
    let queryPart: Substring
    let fragment: Substring
    if let hash = afterQ.firstIndex(of: "#") {
      queryPart = afterQ[afterQ.startIndex..<hash]
      fragment = afterQ[hash...]
    } else {
      queryPart = afterQ
      fragment = afterQ[afterQ.endIndex...]
    }

    let redactedParams = queryPart.split(separator: "&", omittingEmptySubsequences: false).map { param -> String in
      guard let eq = param.firstIndex(of: "=") else { return String(param) }
      let name = param[param.startIndex..<eq]
      if sensitiveKeysLower.contains(name.lowercased()) {
        return "\(name)=\(REDACTED)"
      }
      return String(param)
    }.joined(separator: "&")

    return String(base) + redactedParams + String(fragment)
  }
}

/// Precomputed form of a `Rules` object, reused across one `redact` call.
private struct ParsedRules {
  let sensitiveKeysLower: Set<String>
  /// All value patterns folded into one alternation; `nil` when none are valid.
  let combinedValueRegex: NSRegularExpression?
  let statePathPatterns: [String]
  let trackPaths: Bool

  init(_ rules: Redaction.Rules) {
    sensitiveKeysLower = Set(rules.sensitiveKeys.map { $0.lowercased() })
    combinedValueRegex = Self.compile(rules.valuePatterns)
    statePathPatterns = rules.statePathPatterns
    trackPaths = !rules.statePathPatterns.isEmpty
  }

  /// Validate each pattern individually so one bad regex doesn't kill the rest,
  /// then fold the survivors into a single alternation for one-pass matching.
  private static func compile(_ patterns: [String]) -> NSRegularExpression? {
    var valid: [String] = []
    for pattern in patterns where (try? NSRegularExpression(pattern: pattern)) != nil {
      valid.append(pattern)
    }
    guard !valid.isEmpty else { return nil }
    let combined = valid.map { "(?:\($0))" }.joined(separator: "|")
    return try? NSRegularExpression(pattern: combined)
  }
}

extension JSONValue {
  var isObjectOrArray: Bool {
    switch self {
    case .object, .array, .raw: true
    default: false
    }
  }
}
