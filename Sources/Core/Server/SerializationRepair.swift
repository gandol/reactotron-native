import Foundation

/// Port of reactotron-core-server repair-serialization.ts.
enum SerializationRepair {
  private static let replacements: [String: JSONValue] = [
    "~~~ undefined ~~~": .null,
    "~~~ null ~~~": .null,
    "~~~ false ~~~": .bool(false),
    "~~~ zero ~~~": .number(0),
    "~~~ empty string ~~~": .string(""),
    "~~~ anonymous function ~~~": .string("fn()"),
    "~~~ nan ~~~": .number(.nan),
    "~~~ infinity ~~~": .number(.infinity),
    "~~~ -infinity ~~~": .number(-.infinity),
  ]

  static func repair(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let o): .object(o.mapValues(repairInner))
    case .array(let a): .array(a.map(repairInner))
    default: value  // top-level non-object untouched, per JS early return
    }
  }

  private static func repairInner(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let o): return .object(o.mapValues(repairInner))
    case .array(let a): return .array(a.map(repairInner))
    case .string(let s):
      if let replacement = replacements[s.lowercased()] { return replacement }
      if s.count > 9, s.hasPrefix("~~~ "), s.hasSuffix(" ~~~") {
        return .string(s.replacingOccurrences(of: "~~~", with: ""))
      }
      return value
    default: return value
    }
  }
}
