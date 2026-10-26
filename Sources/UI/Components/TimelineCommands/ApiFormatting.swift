import Foundation

/// Ports of `reactotron-core-ui/src/utils/api-to-curl.ts` and
/// `api-to-markdown.ts`, used by the ApiResponse command's copy toolbar
/// (Copy as cURL / Copy as markdown).

/// Right-pad `str` with `chr` up to `length` (port of `pad.ts` rightPad).
private func rightPad(_ str: String, _ length: Int, _ chr: Character = " ") -> String {
  let pad = max(0, length - str.count)
  return str + String(repeating: chr, count: pad)
}

/// Compact single-line JSON for a JSONValue string, mirroring
/// `JSON.stringify(JSON.parse(data))` — i.e. re-encode without whitespace.
private func compactJSONString(_ value: JSONValue) -> String? {
  value.encodedString()
}

/// Port of `apiRequestToCurl(payload)`.
func apiRequestToCurl(_ payload: JSONValue) -> String {
  let request = payload["request"] ?? .object([:])
  let method = request["method"]?.stringValue
  let url = request["url"]?.stringValue ?? ""
  let headers = request["headers"]?.objectValue ?? [:]
  let data = request["data"]

  var output: [String] = []
  if method == "GET" {
    output.append("curl")
  } else {
    output.append("curl -X \(method ?? "") ")
  }
  // Object key order in JS is insertion order; we sort for determinism.
  for (header, value) in headers.sorted(by: { $0.key < $1.key }) {
    let v = value.stringValue ?? stringifyScalar(value)
    output.append(" -H \"\(header):\(v)\"")
  }
  output.append(" \(url)")

  if let data, data.isTruthy {
    var parsedData: String
    if let s = data.stringValue {
      // Try to normalize a JSON string into compact JSON; fall back to raw.
      if let reparsed = JSONValue.parse(Data(s.utf8)), let compact = compactJSONString(reparsed) {
        parsedData = compact
      } else {
        parsedData = s
      }
    } else {
      parsedData = compactJSONString(data) ?? ""
    }
    output.append(" -d '\(parsedData)'")
  }
  return output.joined()
}

/// Renders a header/param object as a fixed-width markdown table (port of
/// the private `tableToMarkdown`). Keys sorted, like `apiRequestToCurl`.
private func tableToMarkdown(_ table: JSONObject) -> String {
  let entries = table.sorted { $0.key < $1.key }.map { ($0.key, $0.value.stringValue ?? stringifyScalar($0.value)) }
  var keyLength = 0
  var valueLength = 0
  for (k, v) in entries {
    keyLength = max(keyLength, k.count)
    valueLength = max(valueLength, v.count)
  }
  var lines: [String] = []
  lines.append("\(rightPad("key", keyLength)) | \(rightPad("value", valueLength))")
  lines.append("\(String(repeating: "-", count: keyLength)) | \(String(repeating: "-", count: valueLength))")
  for (k, v) in entries {
    lines.append("\(rightPad(k, keyLength)) | \(rightPad(v, valueLength))")
  }
  return lines.joined(separator: "\n")
}

/// Pretty (2-space) JSON for a JSONValue, matching `JSON.stringify(x, null, 2)`
/// except that keys stay sorted, as they were before `JSONWriter`.
private func pretty2(_ value: JSONValue) -> String {
  JSONWriter.pretty(value, sortedKeys: true)
}

/// Port of `apiToMarkdown(payload)`.
func apiToMarkdown(_ payload: JSONValue) -> String {
  var lines: [String] = []
  let request = payload["request"] ?? .object([:])

  lines.append("# Request")
  lines.append("")
  lines.append("### Endpoint")
  lines.append("")
  let method = request["method"]?.stringValue ?? ""
  let url = request["url"]?.stringValue ?? ""
  lines.append("`\(method)` \(url)".trimmingCharacters(in: .whitespaces))

  if let duration = payload["duration"]?.numberValue {
    lines.append("")
    lines.append("### Duration")
    lines.append("")
    lines.append("`\(Int(duration))` ms")
  }

  if let dataVal = request["data"], dataVal.isTruthy {
    var data = dataVal.stringValue ?? pretty2(dataVal)
    if let s = dataVal.stringValue, let reparsed = JSONValue.parse(Data(s.utf8)) {
      data = pretty2(reparsed)
    }
    if !data.isEmpty {
      lines.append("")
      lines.append("### Data Sent")
      lines.append("")
      lines.append("```json")
      lines.append(data)
      lines.append("```")
    }
  }

  if let headers = request["headers"]?.objectValue, !headers.isEmpty {
    lines.append("")
    lines.append("### Headers")
    lines.append("")
    lines.append(tableToMarkdown(headers))
  }

  if let response = payload["response"], response.isTruthy {
    lines.append("")
    lines.append("# Response")

    if let status = response["status"], status.isTruthy {
      lines.append("")
      lines.append("### Status Code")
      lines.append("")
      lines.append("`\(response["status"].flatMap { $0.numberValue.map { String(Int($0)) } } ?? "")`")
    }

    if let bodyVal = response["body"], bodyVal.isTruthy {
      var body = bodyVal.stringValue ?? pretty2(bodyVal)
      if let s = bodyVal.stringValue, let reparsed = JSONValue.parse(Data(s.utf8)) {
        body = pretty2(reparsed)
      } else if bodyVal.stringValue == nil {
        body = pretty2(bodyVal)
      }
      if !body.isEmpty {
        lines.append("")
        lines.append("### Data Received")
        lines.append("")
        lines.append("```json")
        lines.append(body)
        lines.append("```")
      }
    }

    if let headers = response["headers"]?.objectValue, !headers.isEmpty {
      lines.append("")
      lines.append("### Headers")
      lines.append("")
      lines.append(tableToMarkdown(headers))
    }
  }

  lines.append("")
  return lines.joined(separator: "\n")
}

/// Minimal scalar-to-string for header/param values that aren't strings.
private func stringifyScalar(_ value: JSONValue?) -> String {
  switch value {
  case .string(let s): return s
  case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
  case .bool(let b): return b ? "true" : "false"
  case .null, .none: return ""
  default: return value?.encodedString() ?? ""
  }
}

