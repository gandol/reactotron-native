import Foundation

struct WireMessage: Decodable {
  let type: String
  let payload: JSONValue?
  let important: JSONValue?
  let deltaTime: Double?
  let date: String?
  let diff: JSONValue?
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
