import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
  private static let d = UserDefaults.standard

  var serverPort: Int { didSet { Self.d.set(serverPort, forKey: "serverPort") } }
  var commandHistory: Int { didSet { Self.d.set(commandHistory, forKey: "commandHistory") } }
  var mcpPort: Int { didSet { Self.d.set(mcpPort, forKey: "mcpPort") } }
  var mcpRedactionSensitiveKeys: [String] { didSet { Self.d.set(mcpRedactionSensitiveKeys, forKey: "mcpRedactionSensitiveKeys") } }
  var mcpRedactionStatePathPatterns: [String] { didSet { Self.d.set(mcpRedactionStatePathPatterns, forKey: "mcpRedactionStatePathPatterns") } }
  var mcpRedactionValuePatterns: [String] { didSet { Self.d.set(mcpRedactionValuePatterns, forKey: "mcpRedactionValuePatterns") } }
  var mcpAllowClientDisable: Bool { didSet { Self.d.set(mcpAllowClientDisable, forKey: "mcpAllowClientDisable") } }
  var mcpAllowClientRemoveRules: Bool { didSet { Self.d.set(mcpAllowClientRemoveRules, forKey: "mcpAllowClientRemoveRules") } }

  init() {
    serverPort = Self.d.object(forKey: "serverPort") as? Int ?? 9090
    commandHistory = Self.d.object(forKey: "commandHistory") as? Int ?? 500
    mcpPort = Self.d.object(forKey: "mcpPort") as? Int ?? 4567
    // Defaults from Redaction (config.ts seeds these from DEFAULT_REDACTION_RULES).
    mcpRedactionSensitiveKeys = Self.d.stringArray(forKey: "mcpRedactionSensitiveKeys") ?? Redaction.defaultSensitiveKeys
    mcpRedactionStatePathPatterns = Self.d.stringArray(forKey: "mcpRedactionStatePathPatterns") ?? Redaction.defaultStatePathPatterns
    mcpRedactionValuePatterns = Self.d.stringArray(forKey: "mcpRedactionValuePatterns") ?? Redaction.defaultValuePatterns
    mcpAllowClientDisable = Self.d.object(forKey: "mcpAllowClientDisable") as? Bool ?? false
    mcpAllowClientRemoveRules = Self.d.object(forKey: "mcpAllowClientRemoveRules") as? Bool ?? false
  }
}
