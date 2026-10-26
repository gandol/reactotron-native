import Foundation

/// The incoming frame envelope (`reactotron-core-server.ts`'s
/// `const { type, important, payload, deltaTime = 0, date } = JSON.parse(incoming)`,
/// plus the `diff` sibling some clients send).
struct WireMessage {
  let type: String
  let payload: JSONValue?
  let important: JSONValue?
  let deltaTime: Double?
  let date: String?
  let diff: JSONValue?

  /// Parses one frame with `JSONParser` (ordered keys, so payload objects
  /// keep the client's key order). Keeps the acceptance rules the former
  /// synthesized `Decodable` had, so exactly the same frames are dropped:
  /// the top level must be an object with a string `type`; `deltaTime`, when
  /// present and non-null, must be a number and `date` a string; `payload`,
  /// `important` and `diff` take any JSON, with `null` read as absent;
  /// unknown keys are ignored; a duplicate envelope key takes the last value.
  ///
  /// With a `lazy` policy, large subtrees of `payload` / `diff` stay as
  /// `.raw` bytes (`LazyJSONPolicy`); acceptance is unaffected.
  init?(data: Data, lazy: LazyJSONPolicy? = nil) {
    guard case .object(let envelope)? = JSONParser.parse(data, lazy: lazy),
      case .string(let type)? = envelope["type"]
    else { return nil }

    switch envelope["deltaTime"] {
    case nil, .null?: deltaTime = nil
    case .number(let n)?: deltaTime = n
    default: return nil
    }
    switch envelope["date"] {
    case nil, .null?: date = nil
    case .string(let s)?: date = s
    default: return nil
    }

    func nonNull(_ v: JSONValue?) -> JSONValue? {
      if case .null? = v { return nil }
      return v
    }
    self.type = type
    payload = nonNull(envelope["payload"])
    important = nonNull(envelope["important"])
    diff = nonNull(envelope["diff"])
  }
}

struct Command: Identifiable, Sendable, Equatable {
  var id: Int { messageId }
  let type: String
  let connectionId: Int
  let messageId: Int
  let date: Date
  let deltaTime: Double
  let important: Bool
  var payload: JSONValue
  var clientId: String?
  let diff: JSONValue?
}

struct Connection: Identifiable, Sendable, Equatable {
  let id: Int
  let clientId: String
  let address: String
  let intro: JSONValue

  var platform: String { intro["platform"]?.stringValue ?? "" }
  var name: String? { intro["name"]?.stringValue }
  var platformVersion: String? { intro["platformVersion"]?.stringValue }
  var osRelease: String? { intro["osRelease"]?.stringValue }
  var reactotronLibraryName: String? { intro["reactotronLibraryName"]?.stringValue }
  var reactotronLibraryVersion: String? { intro["reactotronLibraryVersion"]?.stringValue }
}

struct CustomCommand: Identifiable, Sendable, Equatable {
  let id: Int
  let clientId: String
  let command: String
  let title: String?
  let description: String?
  let args: [CustomCommandArg]
}

struct CustomCommandArg: Sendable, Equatable {
  let name: String
  let type: String
}

extension CustomCommand {
  /// Stable per-(client, command) identity, decoupled from list position or
  /// the array's `id: Int` (which is only unique per-client, and — per
  /// `reactotron-core-server.ts`'s unconditional `list.push` — not even
  /// guaranteed unique within a client on a duplicate register). Use this
  /// for SwiftUI `ForEach` identity so a `CustomCommandCard`'s local arg
  /// text (`@State`) stays bound to its command rather than to a list
  /// index — an index can point at a different command after a search
  /// filters the list or an earlier command unregisters and later ones
  /// shift down. Matches the source's React key: `${cc.clientId}-${cc.id}`
  /// (`customCommands/index.tsx:215`).
  var stableID: String { "\(clientId)-\(id)" }

  /// Parses a `customCommand.register` payload (`reactotron-core-contract`'s
  /// `CustomCommandRegisterPayload`: `{ id: number, command: string, title?,
  /// description?, args?: [{ name, type }] }`) into a `CustomCommand`, scoped
  /// to the connection it arrived on (the wire payload itself carries no
  /// `clientId` — that's a property of the enclosing `Command`).
  init?(registerPayload payload: JSONValue, clientId: String) {
    guard let idValue = payload["id"]?.numberValue,
      let command = payload["command"]?.stringValue
    else { return nil }
    self.id = Int(idValue)
    self.clientId = clientId
    self.command = command
    self.title = payload["title"]?.stringValue
    self.description = payload["description"]?.stringValue
    self.args = (payload["args"]?.arrayValue ?? []).compactMap { arg in
      guard let name = arg["name"]?.stringValue else { return nil }
      return CustomCommandArg(name: name, type: arg["type"]?.stringValue ?? "")
    }
  }
}

nonisolated(unsafe) private let isoWithFraction: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}()

nonisolated(unsafe) private let isoPlain = ISO8601DateFormatter()

func parseCommandDate(_ s: String?) -> Date {
  guard let s else { return Date() }
  return isoWithFraction.date(from: s) ?? isoPlain.date(from: s) ?? Date()
}
