# Reactotron Native macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS Swift replacement for the Electron Reactotron app — identical UI, functionality, and wire protocol; existing Reactotron clients connect unchanged.

**Architecture:** SwiftUI app with three layers: `Core/Server` (NWListener WebSocket server porting `reactotron-core-server` byte-for-byte at the protocol level), `Core/MCP` (hand-rolled streamable-HTTP JSON-RPC MCP server porting `reactotron-mcp`), and `UI` (SwiftUI port of the Electron renderer + `reactotron-core-ui`). `@Observable` MainActor stores bridge server events to UI.

**Tech Stack:** Swift 6, SwiftUI, Network.framework, Foundation.Process (adb), UserDefaults, XcodeGen, XCTest. **Zero third-party dependencies** (MCP is hand-rolled minimal streamable-HTTP — the spec's approved fallback, chosen as primary for zero deps).

## Global Constraints

- Deployment target: **macOS 14.0**, Swift 6 (`SWIFT_VERSION: 6.0`).
- **No third-party dependencies.**
- **No App Sandbox** (server accepts inbound connections; spawns `adb` — same trust model as the Electron app).
- Wire protocol must match `reactotron-core-server` exactly; existing clients connect unchanged.
- Reference repo (source of truth for ALL behavior/colors/layout): `/Volumes/samsung/new_mac/opensource/reactotron` — **read the referenced source file before porting each component.**
- Theme color values must be **verbatim** from `lib/reactotron-core-ui/src/themes.ts` (dark theme; the Task 1 Theme.swift below already contains the verbatim values).
- Defaults: `serverPort` 9090, `commandHistory` 500, `mcpPort` 4567.
- All UI state stores are `@MainActor @Observable`; network I/O never on MainActor.
- Every task: build must pass (`xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron build`), tests must pass, then commit.
- Build/test commands (run from repo root `/Volumes/samsung/new_mac/opensource/reactotron-native-macos`):
  - Regenerate project: `xcodegen`
  - Build: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron -configuration Debug build 2>&1 | tail -20`
  - Test: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -30`

## File Structure

```
project.yml                                   XcodeGen manifest
Sources/
├── App/
│   ├── ReactotronApp.swift                   @main, WindowGroup, menu commands
│   └── AppModel.swift                        owns server+stores+mcp+adb, event wiring
├── Core/
│   ├── Server/
│   │   ├── JSONValue.swift                   arbitrary-JSON model
│   │   ├── SerializationRepair.swift         port of repair-serialization.ts
│   │   ├── WireModels.swift                  WireMessage, Command, Connection, CustomCommand
│   │   └── ReactotronServer.swift            NWListener WS server (port of reactotron-core-server.ts)
│   ├── MCP/
│   │   ├── MinimalHTTPServer.swift           HTTP/1.1 request/response on NWListener
│   │   ├── Redaction.swift                   port of redaction.ts
│   │   └── McpServer.swift                   JSON-RPC dispatch, tools, resources (port of reactotron-mcp)
│   └── Android/
│       └── AndroidDeviceManager.swift        port of main/utils.ts adb integration
├── State/
│   ├── SettingsStore.swift                   UserDefaults-backed settings
│   └── SessionStore.swift                    port of useStandalone.ts reducer
└── UI/
    ├── Theme/Theme.swift                     verbatim themes.ts values
    ├── Components/
    │   ├── Icons.swift                       SVG path data + parser → SwiftUI Path
    │   ├── SideBar.swift                     SideBar + SideBarButton
    │   ├── Footer.swift                      Footer + ConnectionSelector
    │   ├── PageHeader.swift                  port of core-ui Header (title + action buttons row)
    │   ├── TreeView.swift                    recursive JSON tree with expand/collapse
    │   ├── Timestamp.swift
    │   ├── EmptyState.swift
    │   └── TimelineCommandViews.swift        BaseCommand chrome + all 14 renderers
    ├── Pages/
    │   ├── HomePage.swift                    welcome + connection list
    │   ├── TimelinePage.swift
    │   ├── SubscriptionsPage.swift
    │   ├── SnapshotsPage.swift
    │   ├── OverlayPage.swift
    │   ├── StorybookPage.swift
    │   ├── CustomCommandsPage.swift
    │   └── HelpPage.swift
    └── Modals/
        ├── ModalChrome.swift                 shared dark-panel sheet styling (port of core-ui Modal)
        ├── DispatchActionModal.swift
        ├── TimelineFilterModal.swift
        ├── SnapshotRenameModal.swift
        ├── SubscriptionAddModal.swift
        └── McpSettingsModal.swift
Tests/
├── JSONValueTests.swift
├── SerializationRepairTests.swift
├── WireModelsTests.swift
├── ReactotronServerTests.swift               integration via URLSessionWebSocketTask
├── SessionStoreTests.swift
├── RedactionTests.swift
└── McpServerTests.swift                      integration via URLSession HTTP
```

Navigation state (current page, sidebar visibility, open modal) lives in `AppModel`. There is no router; pages are an enum switch.

---

### Task 1: Project skeleton + Theme

**Files:**
- Create: `project.yml`, `.gitignore`
- Create: `Sources/App/ReactotronApp.swift`
- Create: `Sources/App/AppModel.swift` (minimal stub, grows later)
- Create: `Sources/UI/Theme/Theme.swift`

**Interfaces:**
- Produces: `Theme` enum with static `Color`/font constants used by every UI task; `AppModel` `@MainActor @Observable` class with `var currentPage: Page` and `var sidebarVisible: Bool`; `Page` enum: `.home, .timeline, .stateSubscriptions, .stateSnapshots, .nativeOverlay, .nativeStorybook, .customCommands, .help`.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
*.xcodeproj
DerivedData/
.DS_Store
build/
```

- [ ] **Step 2: Write `project.yml`**

```yaml
name: Reactotron
options:
  bundleIdPrefix: com.reactotron
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Automatic
targets:
  Reactotron:
    type: application
    platform: macOS
    sources: [Sources]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.reactotron.native
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.developer-tools
        ENABLE_APP_SANDBOX: NO
        ENABLE_HARDENED_RUNTIME: NO
  ReactotronTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: Reactotron
schemes:
  Reactotron:
    build:
      targets:
        Reactotron: all
    test:
      targets:
        - ReactotronTests
```

- [ ] **Step 3: Write `Sources/UI/Theme/Theme.swift`**

Verbatim port of the **dark** theme from `lib/reactotron-core-ui/src/themes.ts` (the app ships dark-only, same as Electron Reactotron in practice — `ReactotronAppProvider` uses dark). hsl/hsla converted exactly.

```swift
import SwiftUI

/// Verbatim port of reactotron-core-ui themes.ts (dark theme).
enum Theme {
  static let background = Color(hex: 0x1E1E1E)
  static let backgroundDarker = Color(hsl: 0, 0, 10.6)
  static let backgroundHighlight = Color(hex: 0x464B50)
  static let backgroundLight = Color(hex: 0xFFFFFF)
  static let backgroundLighter = Color(hex: 0x323537)
  static let backgroundSubtleDark = Color(hsl: 0, 0, 8.2)
  static let backgroundSubtleLight = Color(hsl: 0, 0, 12.4)
  static let bold = Color(hex: 0xF9EE98)
  static let chrome = Color(hsl: 0, 0, 12.9)
  static let chromeLine = Color(hsl: 0, 0, 14.7)
  static let constant = Color(hex: 0xCDA869)
  static let foreground = Color(hex: 0xA7A7A7)
  static let foregroundDark = Color(hex: 0x838184)
  static let foregroundLight = Color(hex: 0xC3C3C3)
  static let glow = Color(hsl: 0, 0, 9.4).opacity(0.8)
  static let heading = Color(hex: 0x7587A6)
  static let highlight = Color(hsl: 290, 3.2, 47.4)
  static let keyword = Color(hex: 0x9B859D)
  static let line = Color(hsl: 204, 4.8, 18.5)
  static let modalOverlay = Color(hsl: 0, 0, 7.1).opacity(0.95)
  static let string = Color(hex: 0x8F9D6A)
  static let subtleLine = Color(hsl: 204, 4.8, 16.5)
  static let support = Color(hex: 0xAFC4DB)
  static let tag = Color(hex: 0xCF6A4C)
  static let tagComplement = Color(hsl: 13.7, 57.7, 91.6)
  static let warning = Color(hex: 0x9B703F)

  /// themes.ts fontFamily: "Fira Code", "SF Mono", ... — SF Mono is the macOS-native member of that stack.
  static func font(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  /// CSS hsl(h, s%, l%) — matches CSS hsl-to-rgb conversion.
  init(hsl h: Double, _ s: Double, _ l: Double) {
    let s = s / 100, l = l / 100
    let c = (1 - abs(2 * l - 1)) * s
    let hp = h / 60
    let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
    let (r1, g1, b1): (Double, Double, Double) =
      switch hp {
      case ..<1: (c, x, 0)
      case ..<2: (x, c, 0)
      case ..<3: (0, c, x)
      case ..<4: (0, x, c)
      case ..<5: (x, 0, c)
      default: (c, 0, x)
      }
    let m = l - c / 2
    self.init(red: r1 + m, green: g1 + m, blue: b1 + m)
  }
}
```

- [ ] **Step 4: Write `Sources/App/AppModel.swift` (stub — grows in Task 7)**

```swift
import SwiftUI

enum Page: String, CaseIterable {
  case home, timeline
  case stateSubscriptions, stateSnapshots
  case nativeOverlay, nativeStorybook
  case customCommands, help
}

@MainActor @Observable
final class AppModel {
  var currentPage: Page = .home
  var sidebarVisible = true
}
```

- [ ] **Step 5: Write `Sources/App/ReactotronApp.swift`**

```swift
import SwiftUI

@main
struct ReactotronApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      Text("Reactotron")
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.background)
        .environment(model)
    }
  }
}
```

- [ ] **Step 6: Generate project and build**

Run: `xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Add an empty `Tests/JSONValueTests.swift` placeholder-free smoke test and run tests**

```swift
import XCTest

final class SmokeTests: XCTestCase {
  func testTruth() { XCTAssertTrue(true) }
}
```

Run: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: project skeleton with XcodeGen and verbatim Reactotron theme"
```

---

### Task 2: JSONValue

**Files:**
- Create: `Sources/Core/Server/JSONValue.swift`
- Test: `Tests/JSONValueTests.swift` (replace smoke test)

**Interfaces:**
- Produces:
  - `enum JSONValue: Codable, Equatable, Sendable` with cases `.null, .bool(Bool), .number(Double), .string(String), .array([JSONValue]), .object([String: JSONValue])`
  - Accessors: `var stringValue: String?`, `var numberValue: Double?`, `var boolValue: Bool?`, `var arrayValue: [JSONValue]?`, `var objectValue: [String: JSONValue]?`, `var isNull: Bool`
  - Subscripts: `subscript(_ key: String) -> JSONValue?`, `subscript(_ index: Int) -> JSONValue?`
  - `var isTruthy: Bool` (JS truthiness: false for null/false/0/"" — used for `important` coercion)
  - `func encodedString() -> String?` (compact JSON; NaN/Infinity encoded as `null` to keep output valid JSON)
  - `static func parse(_ data: Data) -> JSONValue?`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Reactotron

final class JSONValueTests: XCTestCase {
  func testDecodeRoundTrip() throws {
    let json = #"{"a":1,"b":"x","c":true,"d":null,"e":[1,2],"f":{"g":2.5}}"#
    let v = JSONValue.parse(Data(json.utf8))
    XCTAssertEqual(v?["a"], .number(1))
    XCTAssertEqual(v?["b"], .string("x"))
    XCTAssertEqual(v?["c"], .bool(true))
    XCTAssertEqual(v?["d"], .null)
    XCTAssertEqual(v?["e"]?[1], .number(2))
    XCTAssertEqual(v?["f"]?["g"], .number(2.5))
  }

  func testTruthiness() {
    XCTAssertFalse(JSONValue.null.isTruthy)
    XCTAssertFalse(JSONValue.bool(false).isTruthy)
    XCTAssertFalse(JSONValue.number(0).isTruthy)
    XCTAssertFalse(JSONValue.string("").isTruthy)
    XCTAssertTrue(JSONValue.string("x").isTruthy)
    XCTAssertTrue(JSONValue.object([:]).isTruthy)
  }

  func testEncodedStringIsValidJSON() {
    let v = JSONValue.object(["n": .number(.nan), "i": .number(.infinity), "s": .string("ok")])
    let s = v.encodedString()!
    XCTAssertNotNil(JSONValue.parse(Data(s.utf8)))
    XCTAssertTrue(s.contains(#""s":"ok""#))
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -10`
Expected: FAIL — `cannot find 'JSONValue' in scope`

- [ ] **Step 3: Implement `Sources/Core/Server/JSONValue.swift`**

```swift
import Foundation

enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
    else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
    else {
      throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    // JSON has no NaN/Infinity; encode as null (JS JSON.stringify does the same)
    case .number(let n): n.isFinite ? try c.encode(n) : try c.encodeNil()
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  var stringValue: String? { if case .string(let s) = self { s } else { nil } }
  var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
  var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
  var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
  var objectValue: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
  var isNull: Bool { self == .null }

  subscript(_ key: String) -> JSONValue? { objectValue?[key] }
  subscript(_ index: Int) -> JSONValue? {
    guard let a = arrayValue, a.indices.contains(index) else { return nil }
    return a[index]
  }

  /// JS truthiness — false for null, false, 0, NaN, "".
  var isTruthy: Bool {
    switch self {
    case .null: false
    case .bool(let b): b
    case .number(let n): n != 0 && !n.isNaN
    case .string(let s): !s.isEmpty
    case .array, .object: true
    }
  }

  static func parse(_ data: Data) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  func encodedString() -> String? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: JSONValue arbitrary-JSON model"
```

---

### Task 3: SerializationRepair

Port of `lib/reactotron-core-server/src/repair-serialization.ts`. Clients encode falsy/special values as sentinel strings (`"~~~ null ~~~"` etc.); the server decodes them back, recursively, in place.

**Files:**
- Create: `Sources/Core/Server/SerializationRepair.swift`
- Test: `Tests/SerializationRepairTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (Task 2)
- Produces: `enum SerializationRepair { static func repair(_ value: JSONValue) -> JSONValue }`

**Exact semantics from repair-serialization.ts** (behavior to replicate, including quirks):
- Only string values inside objects/arrays are examined (recursion into `.object` and `.array`).
- Lower-cased exact matches replaced: `"~~~ undefined ~~~"` → null (Swift has no undefined), `"~~~ null ~~~"` → null, `"~~~ false ~~~"` → false, `"~~~ zero ~~~"` → 0, `"~~~ empty string ~~~"` → "", `"~~~ anonymous function ~~~"` → `"fn()"`, `"~~~ nan ~~~"` → NaN, `"~~~ infinity ~~~"` → +∞, `"~~~ -infinity ~~~"` → −∞. (JS checks `obj[k].toLowerCase() in replacements` — the table keys are lower-case except the sentinel casing matches anyway; replicate with case-insensitive comparison.)
- Otherwise, strings **longer than 9 chars** starting with `"~~~ "` and ending with `" ~~~"` get every `~~~` removed (spaces remain: `"~~~ fetchData() ~~~"` → `" fetchData() "`).
- A bare top-level string is NOT repaired (JS: `typeof payload !== "object"` returns early).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Reactotron

final class SerializationRepairTests: XCTestCase {
  func testSentinelReplacements() {
    let input = JSONValue.object([
      "u": .string("~~~ undefined ~~~"),
      "n": .string("~~~ null ~~~"),
      "f": .string("~~~ false ~~~"),
      "z": .string("~~~ zero ~~~"),
      "e": .string("~~~ empty string ~~~"),
      "fn": .string("~~~ anonymous function ~~~"),
      "keep": .string("hello"),
    ])
    let out = SerializationRepair.repair(input)
    XCTAssertEqual(out["u"], .null)
    XCTAssertEqual(out["n"], .null)
    XCTAssertEqual(out["f"], .bool(false))
    XCTAssertEqual(out["z"], .number(0))
    XCTAssertEqual(out["e"], .string(""))
    XCTAssertEqual(out["fn"], .string("fn()"))
    XCTAssertEqual(out["keep"], .string("hello"))
  }

  func testNamedFunctionSentinelStripsTildes() {
    let out = SerializationRepair.repair(.object(["f": .string("~~~ fetchData() ~~~")]))
    XCTAssertEqual(out["f"], .string(" fetchData() "))
  }

  func testRecursesIntoArraysAndObjects() {
    let out = SerializationRepair.repair(
      .object(["a": .array([.string("~~~ null ~~~"), .object(["b": .string("~~~ zero ~~~")])])]))
    XCTAssertEqual(out["a"]?[0], .null)
    XCTAssertEqual(out["a"]?[1]?["b"], .number(0))
  }

  func testTopLevelStringUntouched() {
    XCTAssertEqual(SerializationRepair.repair(.string("~~~ null ~~~")), .string("~~~ null ~~~"))
  }

  func testNaNAndInfinity() {
    let out = SerializationRepair.repair(.object([
      "nan": .string("~~~ NaN ~~~"), "inf": .string("~~~ Infinity ~~~"),
      "ninf": .string("~~~ -Infinity ~~~"),
    ]))
    XCTAssertTrue(out["nan"]?.numberValue?.isNaN == true)
    XCTAssertEqual(out["inf"], .number(.infinity))
    XCTAssertEqual(out["ninf"], .number(-.infinity))
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -10`
Expected: FAIL — `cannot find 'SerializationRepair' in scope`

- [ ] **Step 3: Implement `Sources/Core/Server/SerializationRepair.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: serialization repair (port of repair-serialization.ts)"
```

---

### Task 4: Wire models — WireMessage, Command, Connection, CustomCommand

**Files:**
- Create: `Sources/Core/Server/WireModels.swift`
- Test: `Tests/WireModelsTests.swift`

**Interfaces:**
- Consumes: `JSONValue`
- Produces:

```swift
struct WireMessage: Decodable {          // one inbound WS text frame
  let type: String
  let payload: JSONValue?
  let important: JSONValue?              // JS truthiness — coerce via .isTruthy
  let deltaTime: Double?
  let date: String?                      // ISO8601 string or absent
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
  let id: Int                            // connectionId from server
  let clientId: String
  let address: String
  let intro: JSONValue                   // full client.intro payload
  // Typed accessors reading from intro:
  var platform: String { intro["platform"]?.stringValue ?? "" }       // "ios" | "android" | "browser"
  var name: String? { intro["name"]?.stringValue }
  var platformVersion: String? { intro["platformVersion"]?.stringValue }
  var osRelease: String? { intro["osRelease"]?.stringValue }
  var reactotronLibraryName: String? { intro["reactotronLibraryName"]?.stringValue }
  var reactotronLibraryVersion: String? { intro["reactotronLibraryVersion"]?.stringValue }
}

struct CustomCommand: Identifiable, Sendable, Equatable {
  let id: Int                            // payload.id from customCommand.register
  let clientId: String
  let command: String
  let title: String?
  let description: String?
  let args: [CustomCommandArg]           // [{name, type}] — type is "string"
}
struct CustomCommandArg: Sendable, Equatable {
  let name: String
  let type: String
}

/// ISO8601 with fractional seconds, falling back to no-fraction, falling back to now —
/// mirrors extractOrCreateDate in reactotron-core-server.ts.
func parseCommandDate(_ s: String?) -> Date
```

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Reactotron

final class WireModelsTests: XCTestCase {
  func testDecodeWireMessage() throws {
    let json = #"{"type":"log","payload":{"level":"debug","message":"hi"},"important":true,"deltaTime":12,"date":"2026-07-16T10:00:00.000Z"}"#
    let m = try JSONDecoder().decode(WireMessage.self, from: Data(json.utf8))
    XCTAssertEqual(m.type, "log")
    XCTAssertEqual(m.payload?["message"], .string("hi"))
    XCTAssertEqual(m.important?.isTruthy, true)
    XCTAssertEqual(m.deltaTime, 12)
  }

  func testDecodeWireMessageMinimal() throws {
    let m = try JSONDecoder().decode(WireMessage.self, from: Data(#"{"type":"clear"}"#.utf8))
    XCTAssertEqual(m.type, "clear")
    XCTAssertNil(m.payload)
  }

  func testParseCommandDate() {
    XCTAssertEqual(
      parseCommandDate("2026-07-16T10:00:00.000Z").timeIntervalSince1970,
      1_784_196_000, accuracy: 1)
    XCTAssertEqual(
      parseCommandDate("2026-07-16T10:00:00Z").timeIntervalSince1970,
      1_784_196_000, accuracy: 1)
    // invalid → now
    XCTAssertEqual(parseCommandDate("garbage").timeIntervalSinceNow, 0, accuracy: 5)
    XCTAssertEqual(parseCommandDate(nil).timeIntervalSinceNow, 0, accuracy: 5)
  }

  func testConnectionAccessors() {
    let c = Connection(
      id: 1, clientId: "abc", address: "127.0.0.1",
      intro: .object(["platform": .string("ios"), "name": .string("MyApp")]))
    XCTAssertEqual(c.platform, "ios")
    XCTAssertEqual(c.name, "MyApp")
    XCTAssertNil(c.platformVersion)
  }
}
```

**Note:** verify the epoch constant with `date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "2026-07-16T10:00:00Z" +%s` before hardcoding; adjust if it differs.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -10`
Expected: FAIL — `cannot find type 'WireMessage' in scope`

- [ ] **Step 3: Implement `Sources/Core/Server/WireModels.swift`** (exact interfaces above; `parseCommandDate` implementation:)

```swift
import Foundation

private let isoWithFraction: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}()
private let isoPlain = ISO8601DateFormatter()

func parseCommandDate(_ s: String?) -> Date {
  guard let s else { return Date() }
  return isoWithFraction.date(from: s) ?? isoPlain.date(from: s) ?? Date()
}
```

(Structs exactly as in Interfaces block — copy them.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: wire protocol models"
```
---

### Task 5: ReactotronServer (NWListener WebSocket server)

Port of `lib/reactotron-core-server/src/reactotron-core-server.ts` (read it fully first). This is the compatibility-critical core.

**Files:**
- Create: `Sources/Core/Server/ReactotronServer.swift`
- Test: `Tests/ReactotronServerTests.swift`

**Interfaces:**
- Consumes: `JSONValue`, `SerializationRepair`, `WireMessage`, `Command`, `Connection`, `CustomCommand`, `parseCommandDate`
- Produces:

```swift
struct PartialConnection: Sendable { let id: Int; let address: String }

final class ReactotronServer: @unchecked Sendable {
  struct Events {                                   // all invoked on server queue; AppModel hops to MainActor
    var started: @Sendable () -> Void = {}
    var stopped: @Sendable () -> Void = {}
    var connect: @Sendable (PartialConnection) -> Void = { _ in }
    var connectionEstablished: @Sendable (Connection) -> Void = { _ in }
    var command: @Sendable (Command) -> Void = { _ in }
    var disconnect: @Sendable (Connection) -> Void = { _ in }
    var portUnavailable: @Sendable (UInt16) -> Void = { _ in }
  }
  var events: Events { get set }                    // set before start()

  func start(port: UInt16)
  func stop()
  /// Serializes {type, payload} and sends: broadcast when clientId == nil, else only to that client.
  func send(type: String, payload: JSONValue, clientId: String?)
  /// Convenience wrappers (same names/semantics as core-server):
  func stateValuesSubscribe(path: String)           // adds path, sends state.values.subscribe {paths}
  func stateValuesUnsubscribe(path: String)
  func stateValuesClearSubscriptions()
  var subscriptions: [String] { get }
}
```

**Implementation requirements (mirror reactotron-core-server.ts exactly):**

1. **Listener setup:**

```swift
private let queue = DispatchQueue(label: "com.reactotron.server")

func start(port: UInt16) {
  let params = NWParameters.tcp
  let wsOptions = NWProtocolWebSocket.Options()
  wsOptions.autoReplyPing = true
  params.allowLocalEndpointReuse = true
  params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
  let listener = try! NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
  listener.stateUpdateHandler = { [weak self] state in
    switch state {
    case .ready: self?.events.started()
    case .failed(let error):
      if case .posix(.EADDRINUSE) = error { self?.events.portUnavailable(port) }
      else { NSLog("Reactotron server failed: \(error)") }
    default: break
    }
  }
  listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
  listener.start(queue: queue)
}
```

2. **Accept** (`accept(_ conn: NWConnection)`): assign `connectionId` (monotonic, starts 0), extract address via `if case .hostPort(let host, _) = conn.endpoint { address = "\(host)" }` (strip `%en0` interface suffixes: keep substring before `%`). Store in `partialConnections` and `sockets[id] = conn`. Emit `events.connect(PartialConnection(...))`. Set `conn.stateUpdateHandler`: on `.failed`/`.cancelled` → run the close logic (3 below). Call `conn.start(queue: queue)` then begin `receiveLoop(conn, id:)`.

3. **Close logic** (single method `handleClose(connectionId: Int)`): remove from `partialConnections`; if a full `Connection` exists with that id: remove it, `customCommands.removeValue(forKey: clientId)`, emit `events.disconnect(connection)`. Remove socket. Must be idempotent (guard on already-removed).

4. **Receive loop:** `conn.receiveMessage { data, context, _, error in ... }` — on message: process (5), then recurse to keep receiving. On error/nil data: cancel connection.

5. **Message processing** (`handleMessage(data: Data, connectionId: Int)`) — port of the `socket.on("message")` block:
   - Decode `WireMessage` (drop frame on failure), `payload = SerializationRepair.repair(message.payload ?? .null)` — repair the payload (JS repairs whole message but only payload/diff hold nested data; repair `diff` too).
   - `messageId += 1` (monotonic across all connections).
   - Build `Command(type:, connectionId:, messageId:, date: parseCommandDate(message.date), deltaTime: message.deltaTime ?? 0, important: message.important?.isTruthy ?? false, payload:, clientId: clientIds[connectionId], diff:)`.
   - **If `type == "client.intro"`:**
     - Merge `address` from the partial connection into `payload` (`payload.address`).
     - Remove from `partialConnections`.
     - `connectionClientId = payload.clientId`; if absent: generate GUID with the same `s4()+s4()-s4()-s4()-s4()-s4()s4()s4()` shape (hex, lowercase) and send `{"type":"setClientId","payload":"<guid>"}` back to THIS socket only.
     - Else (clientId present): find other live sockets whose assigned clientId equals it; after **0.5 s** (`queue.asyncAfter`) cancel each; immediately remove their `Connection` entries from `connections` (no disconnect event for the removal itself — the socket close will be a no-op because the connection entry is already gone... **verify against JS:** JS removes from `connections` immediately AND the deferred socket close then fires its own close handler which finds nothing → matches this idempotent design).
     - `clientIds[connectionId] = connectionClientId`; set `command.clientId`.
     - Build `Connection(id: connectionId, clientId:, address:, intro: payload)` and append to `connections`; emit `events.connectionEstablished(connection)`.
   - **If `type == "state.values.change"`:** `subscriptionsStorage = payload["changes"] array's "path" strings`.
   - **If `type == "customCommand.register"`:** append to `customCommands[clientId]` (id: `payload["id"].numberValue`, command, title, description, args). **`customCommand.unregister`:** remove by `payload["id"]`.
   - Always emit `events.command(command)` **after** the type-specific handling (JS emits at the end).

6. **Send:**

```swift
func send(type: String, payload: JSONValue, clientId: String? = nil) {
  queue.async { [self] in
    let text = JSONValue.object(["type": .string(type), "payload": payload]).encodedString() ?? "{}"
    let meta = NWProtocolWebSocket.Metadata(opcode: .text)
    let ctx = NWConnection.ContentContext(identifier: "send", metadata: [meta])
    for (connId, sock) in sockets {
      if let clientId, clientIds[connId] != clientId { continue }
      sock.send(content: Data(text.utf8), contentContext: ctx, isComplete: true, completion: .idempotent)
    }
  }
}
```

7. **Keepalive:** `DispatchSourceTimer` on the queue, every 30 s send a WS ping (`Metadata(opcode: .ping)`) to every socket. Cancel in `stop()`.

8. **stop():** cancel timer, cancel all sockets, cancel listener, clear all state, emit `events.stopped()`.

- [ ] **Step 1: Write failing integration tests**

```swift
import XCTest
@testable import Reactotron

/// Test helper: connect, optionally intro, collect received messages.
final class TestClient {
  let task: URLSessionWebSocketTask
  init(port: UInt16) {
    task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
    task.resume()
  }
  func send(_ json: String) async throws { try await task.send(.string(json)) }
  func receive() async throws -> String {
    if case .string(let s) = try await task.receive() { return s }
    throw URLError(.badServerResponse)
  }
  func close() { task.cancel(with: .normalClosure, reason: nil) }
}

final class ReactotronServerTests: XCTestCase {
  var server: ReactotronServer!
  var port: UInt16!

  override func setUp() {
    server = ReactotronServer()
    port = UInt16.random(in: 20_000...40_000)
  }
  override func tearDown() { server.stop() }

  func start() async {
    await withCheckedContinuation { cont in
      server.events.started = { cont.resume() }
      server.start(port: port)
    }
  }

  func testIntroWithoutClientIdGetsSetClientId() async throws {
    await start()
    let established = expectation(description: "established")
    server.events.connectionEstablished = { conn in
      XCTAssertEqual(conn.intro["name"]?.stringValue, "TestApp")
      XCTAssertFalse(conn.clientId.isEmpty)
      established.fulfill()
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"name":"TestApp","platform":"ios"}}"#)
    let reply = try await client.receive()
    XCTAssertTrue(reply.contains("setClientId"))
    await fulfillment(of: [established], timeout: 5)
    client.close()
  }

  func testCommandEventCarriesRepairedPayloadAndIds() async throws {
    await start()
    let got = expectation(description: "log command")
    server.events.command = { cmd in
      guard cmd.type == "log" else { return }  // client.intro fires first
      XCTAssertEqual(cmd.payload["message"], .null)  // "~~~ null ~~~" repaired
      XCTAssertEqual(cmd.clientId, "fixed-client-id")
      XCTAssertTrue(cmd.important)
      got.fulfill()
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"fixed-client-id"}}"#)
    try await client.send(#"{"type":"log","important":true,"payload":{"message":"~~~ null ~~~"}}"#)
    await fulfillment(of: [got], timeout: 5)
    client.close()
  }

  func testDuplicateClientIdClosesOldSocket() async throws {
    await start()
    let c1 = TestClient(port: port)
    try await c1.send(#"{"type":"client.intro","payload":{"clientId":"dup"}}"#)
    try await Task.sleep(for: .milliseconds(200))
    let c2 = TestClient(port: port)
    try await c2.send(#"{"type":"client.intro","payload":{"clientId":"dup"}}"#)
    try await Task.sleep(for: .seconds(1))  // old socket closed after the 500 ms defer
    do {
      try await c1.send(#"{"type":"log","payload":{}}"#)
      _ = try await c1.receive()
      XCTFail("old socket should be closed")
    } catch { /* expected */ }
    c2.close()
  }

  func testBroadcastAndTargetedSend() async throws {
    await start()
    let c1 = TestClient(port: port)
    try await c1.send(#"{"type":"client.intro","payload":{"clientId":"one"}}"#)
    try await Task.sleep(for: .milliseconds(300))
    server.send(type: "state.values.subscribe", payload: .object(["paths": .array([])]), clientId: "one")
    let msg = try await c1.receive()
    XCTAssertTrue(msg.contains("state.values.subscribe"))
    c1.close()
  }

  func testPortUnavailable() async throws {
    await start()
    let second = ReactotronServer()
    let unavailable = expectation(description: "portUnavailable")
    second.events.portUnavailable = { p in
      XCTAssertEqual(p, self.port); unavailable.fulfill()
    }
    second.start(port: port)
    await fulfillment(of: [unavailable], timeout: 5)
    second.stop()
  }

  func testCustomCommandRegistration() async throws {
    await start()
    let registered = expectation(description: "register")
    server.events.command = { cmd in
      if cmd.type == "customCommand.register" { registered.fulfill() }
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"cc"}}"#)
    try await client.send(#"{"type":"customCommand.register","payload":{"id":1,"command":"go_home","title":"Go Home"}}"#)
    await fulfillment(of: [registered], timeout: 5)
    client.close()
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -10`
Expected: FAIL — `cannot find 'ReactotronServer' in scope`

- [ ] **Step 3: Implement `Sources/Core/Server/ReactotronServer.swift`** per the requirements block above. Read `reactotron-core-server.ts` lines 150–390 side-by-side while implementing.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` (network tests are timing-sensitive; if a test flakes, prefer event-driven expectations over sleeps — the 500 ms duplicate-close sleep is inherent to the protocol)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: NWListener WebSocket server, full reactotron-core-server protocol port"
```

---

### Task 6: SettingsStore + SessionStore

`SessionStore` is a direct port of the reducer in `apps/reactotron-app/src/renderer/contexts/Standalone/useStandalone.ts` (read it fully). `SettingsStore` mirrors `apps/reactotron-app/src/renderer/config.ts`.

**Files:**
- Create: `Sources/State/SettingsStore.swift`
- Create: `Sources/State/SessionStore.swift`
- Test: `Tests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `Command`, `Connection`, `PartialConnection`, `JSONValue`
- Produces:

```swift
@MainActor @Observable
final class SettingsStore {
  var serverPort: Int          // default 9090, persisted key "serverPort"
  var commandHistory: Int      // default 500, persisted key "commandHistory"
  var mcpPort: Int             // default 4567, persisted key "mcpPort"
  var mcpRedactionSensitiveKeys: [String]        // default Redaction.defaultSensitiveKeys (Task 15)
  var mcpRedactionStatePathPatterns: [String]    // default []
  var mcpRedactionValuePatterns: [String]        // default Redaction.defaultValuePatterns
  var mcpAllowClientDisable: Bool                // default false
  var mcpAllowClientRemoveRules: Bool            // default false
}
// Each property reads UserDefaults in init and writes through in didSet.
// NOTE: Task 15 defines Redaction; until then initialize the three MCP arrays
// with `[]` defaults and leave a one-line comment; Task 15 wires the real defaults.

enum ServerStatus: String { case stopped, portUnavailable, started }

@MainActor @Observable
final class SessionConnection: Identifiable {
  let clientId: String
  var connection: Connection    // latest intro data
  var commands: [Command] = []  // newest first
  var connected = true
  var id: String { clientId }
}

@MainActor @Observable
final class SessionStore {
  var serverStatus: ServerStatus = .stopped
  var connections: [SessionConnection] = []
  var selectedClientId: String?
  var selectedConnection: SessionConnection? { connections.first { $0.clientId == selectedClientId } }
  private var orphanedCommands: [Command] = []
  var commandHistoryLimit = 500

  func serverStarted()
  func serverStopped()
  func portUnavailable()
  func connectionEstablished(_ connection: Connection)
  func connectionDisconnected(_ connection: Connection)
  func commandReceived(_ command: Command)
  func clearSelectedConnectionCommands()
  func selectConnection(_ clientId: String)
}
```

**Reducer semantics to replicate exactly (from useStandalone.ts):**
- `connectionEstablished`: if a `SessionConnection` with same clientId exists → mark `connected = true` and update `connection`; else append new. Then move any `orphanedCommands` whose `connectionId == connection.id` into its `commands`. If exactly **one** connected connection exists → auto-select it. Set `serverStatus = .started`.
- `connectionDisconnected`: mark `connected = false` (keep it and its commands). If it was selected → select first still-connected connection, else `selectedClientId = nil`.
- `commandReceived`: no `clientId` → push to `orphanedCommands`. Unknown clientId → log and drop. Else **prepend** (`commands.insert(command, at: 0)`), then trim to `commandHistoryLimit` (Electron caps history via the `commandHistory` setting).
- `clearSelectedConnectionCommands`: clears only the selected connection's commands.
- `selectConnection`: only if that clientId exists.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Reactotron

@MainActor
final class SessionStoreTests: XCTestCase {
  func conn(_ clientId: String, id: Int = 1) -> Connection {
    Connection(id: id, clientId: clientId, address: "127.0.0.1",
               intro: .object(["platform": .string("ios")]))
  }
  func cmd(_ type: String, clientId: String?, connectionId: Int = 1, msgId: Int = .random(in: 1...99999)) -> Command {
    Command(type: type, connectionId: connectionId, messageId: msgId, date: Date(),
            deltaTime: 0, important: false, payload: .object([:]), clientId: clientId, diff: nil)
  }

  func testAutoSelectsSingleConnection() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    XCTAssertEqual(s.selectedClientId, "a")
    XCTAssertEqual(s.serverStatus, .started)
    s.connectionEstablished(conn("b", id: 2))
    XCTAssertEqual(s.selectedClientId, "a")  // stays — auto-select only when exactly 1
  }

  func testReconnectMarksConnected() {
    let s = SessionStore()
    s.connectionEstablished(conn("a"))
    s.connectionDisconnected(conn("a"))
    XCTAssertEqual(s.connections.first?.connected, false)
    XCTAssertNil(s.selectedClientId)
    s.connectionEstablished(conn("a", id: 3))
    XCTAssertEqual(s.connections.count, 1)
    XCTAssertEqual(s.connections.first?.connected, true)
    XCTAssertEqual(s.selectedClientId, "a")
  }

  func testOrphanedCommandsAttachOnEstablish() {
    let s = SessionStore()
    s.commandReceived(cmd("log", clientId: nil, connectionId: 7))
    s.connectionEstablished(conn("a", id: 7))
    XCTAssertEqual(s.connections.first?.commands.count, 1)
  }

  func testCommandsPrependAndTrim() {
    let s = SessionStore()
    s.commandHistoryLimit = 3
    s.connectionEstablished(conn("a"))
    for i in 1...5 { s.commandReceived(cmd("log", clientId: "a", msgId: i)) }
    let cmds = s.connections.first!.commands
    XCTAssertEqual(cmds.count, 3)
    XCTAssertEqual(cmds.map(\.messageId), [5, 4, 3])  // newest first
  }

  func testClearOnlySelected() {
    let s = SessionStore()
    s.connectionEstablished(conn("a", id: 1))
    s.connectionEstablished(conn("b", id: 2))
    s.commandReceived(cmd("log", clientId: "a", connectionId: 1))
    s.commandReceived(cmd("log", clientId: "b", connectionId: 2))
    s.selectConnection("a")
    s.clearSelectedConnectionCommands()
    XCTAssertEqual(s.connections.first { $0.clientId == "a" }!.commands.count, 0)
    XCTAssertEqual(s.connections.first { $0.clientId == "b" }!.commands.count, 1)
  }

  func testDisconnectSelectedFallsBackToFirstConnected() {
    let s = SessionStore()
    s.connectionEstablished(conn("a", id: 1))
    s.connectionEstablished(conn("b", id: 2))
    s.selectConnection("b")
    s.connectionDisconnected(conn("b", id: 2))
    XCTAssertEqual(s.selectedClientId, "a")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -10`
Expected: FAIL — `cannot find 'SessionStore' in scope`

- [ ] **Step 3: Implement both stores** per the interfaces + reducer semantics above. SettingsStore pattern:

```swift
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
    mcpRedactionSensitiveKeys = Self.d.stringArray(forKey: "mcpRedactionSensitiveKeys") ?? []  // Task 15 wires Redaction defaults
    mcpRedactionStatePathPatterns = Self.d.stringArray(forKey: "mcpRedactionStatePathPatterns") ?? []
    mcpRedactionValuePatterns = Self.d.stringArray(forKey: "mcpRedactionValuePatterns") ?? []
    mcpAllowClientDisable = Self.d.object(forKey: "mcpAllowClientDisable") as? Bool ?? false
    mcpAllowClientRemoveRules = Self.d.object(forKey: "mcpAllowClientRemoveRules") as? Bool ?? false
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: SessionStore (useStandalone port) and SettingsStore"
```
---

### Task 7: App wiring + shell UI (SideBar, Footer, navigation)

References to read first:
- `apps/reactotron-app/src/renderer/App.tsx` (layout structure)
- `apps/reactotron-app/src/renderer/components/SideBar/Sidebar.tsx`
- `apps/reactotron-app/src/renderer/components/SideBarButton/index.tsx`
- `apps/reactotron-app/src/renderer/components/Footer/Stateless.tsx`
- `apps/reactotron-app/src/renderer/components/ConnectionSelector/index.tsx`
- `apps/reactotron-app/src/renderer/contexts/Standalone/index.tsx` (server↔store wiring)

**Files:**
- Create: `Sources/UI/Components/Icons.swift`
- Create: `Sources/UI/Components/SideBar.swift`
- Create: `Sources/UI/Components/Footer.swift`
- Create: `Sources/UI/RootView.swift`
- Modify: `Sources/App/AppModel.swift` (full version)
- Modify: `Sources/App/ReactotronApp.swift` (use RootView)
- Copy asset: `apps/reactotron-app/src/renderer/images/Reactotron-128.png` → `Sources/Resources/Reactotron-128.png` (add `Sources/Resources` with `buildPhase: resources` in project.yml)

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces:
  - `AppModel` grows: `let settings: SettingsStore`, `let session: SessionStore`, `let server: ReactotronServer`, `func startServer()`, `func stopServer()`, `func sendCommand(type: String, payload: JSONValue)` (sends to `session.selectedClientId`), modal flags `var activeModal: Modal?` where `enum Modal { case dispatchAction, timelineFilter, snapshotRename(SnapshotItem), subscriptionAdd, mcpSettings }` — **note:** `SnapshotItem` arrives in Task 12; until then declare `case snapshotRename` without payload and extend in Task 12.
  - `Icon` view: `Icon(_ name: IconName, size: CGFloat = 32, color: Color = Theme.foregroundLight)` rendering embedded SVG path data.
  - `SideBar(), Footer()` SwiftUI views reading `AppModel` from environment.

- [ ] **Step 1: Icons.swift — SVG path parser + initial icon set**

Parser: minimal SVG path-data parser supporting commands `M m L l H h V v C c S s Q q T t A a Z z` → `SwiftUI.Path`, then `Icon` view scales the (24×24 for Md*, 512×512 for Fa*) viewBox to `size`.

```swift
struct SVGIcon {
  let viewBox: CGFloat      // 24 for material, 512 for fontawesome
  let path: String          // SVG path data
}

enum IconName { /* one case per icon below */ }

struct Icon: View {
  let icon: IconName
  var size: CGFloat = 32
  var color: Color = Theme.foregroundLight
  var body: some View {
    Path.fromSVG(IconName.data[icon]!.path)
      .fill(color, style: FillStyle(eoFill: true))
      .transformEffect(.init(scaleX: size / IconName.data[icon]!.viewBox,
                             y: size / IconName.data[icon]!.viewBox))
      .frame(width: size, height: size)
  }
}
```

Fetch exact path data (one-time, during this step) from react-icons on unpkg:

```bash
curl -s https://unpkg.com/react-icons@5.2.1/md/index.js | grep -o 'MdReorder.*\?"});' | head -c 400
# repeat per icon; or download once and grep locally:
curl -so /tmp/md-icons.js https://unpkg.com/react-icons@5.2.1/md/index.js
curl -so /tmp/fa-icons.js https://unpkg.com/react-icons@5.2.1/fa/index.js
```

Initial icon set (more added by later tasks as they port views — same extraction method):
`MdReorder, MdAssignment, MdPhoneIphone, MdLiveHelp, MdWarning, MdOutlineMobileFriendly, MdMobiledataOff, FaMagic, MdSearch, MdFilterList, MdSwapVert, MdDeleteSweep, MdDownload, FaTimes, MdKeyboardArrowUp, MdKeyboardArrowDown, MdSettings`.

Add a unit test that every `IconName` case parses to a non-empty `Path` (`XCTAssertFalse(Path.fromSVG(data.path).isEmpty)`).

- [ ] **Step 2: Full AppModel**

```swift
@MainActor @Observable
final class AppModel {
  var currentPage: Page = .home
  var sidebarVisible = true
  var activeModal: Modal?

  let settings = SettingsStore()
  let session = SessionStore()
  let server = ReactotronServer()

  init() {
    session.commandHistoryLimit = settings.commandHistory
    wireServerEvents()
  }

  private func wireServerEvents() {
    server.events.started = { [weak self] in Task { @MainActor in self?.session.serverStarted() } }
    server.events.stopped = { [weak self] in Task { @MainActor in self?.session.serverStopped() } }
    server.events.portUnavailable = { [weak self] _ in Task { @MainActor in self?.session.portUnavailable() } }
    server.events.connectionEstablished = { [weak self] conn in
      Task { @MainActor in self?.session.connectionEstablished(conn) }
    }
    server.events.disconnect = { [weak self] conn in
      Task { @MainActor in self?.session.connectionDisconnected(conn) }
    }
    server.events.command = { [weak self] cmd in
      Task { @MainActor in self?.session.commandReceived(cmd) }
    }
  }

  func startServer() { server.start(port: UInt16(settings.serverPort)) }
  func stopServer() { server.stop() }

  /// Equivalent of Electron's sendCommand — targets selected client.
  func sendCommand(type: String, payload: JSONValue) {
    server.send(type: type, payload: payload, clientId: session.selectedClientId)
  }
}
```

`ReactotronApp.body` calls `model.startServer()` in `.task {}` on RootView.

- [ ] **Step 3: SideBar.swift** — port of `Sidebar.tsx` + `SideBarButton/index.tsx`:
  - Container: width 115, `Theme.backgroundSubtleDark` background, right border `Theme.chromeLine` 1pt, top padding 25. Hidden: animate `.frame(width:)`/offset with 0.2 s ease-out when `!model.sidebarVisible`.
  - Buttons top→bottom: Home (logo image `Reactotron-128`), Timeline (`MdReorder`), State (`MdAssignment`, matches both state pages), React Native (`MdPhoneIphone`, matches both native pages), Custom Commands (`FaMagic`, iconSize 25). `Spacer()`. Server-status button (`MdOutlineMobileFriendly` "Running" / `MdMobiledataOff` "Stopped" / `MdWarning` yellow "Port <port> unavailable", tap retries `model.startServer()`). Help (`MdLiveHelp`).
  - `SideBarButton` (read `SideBarButton/index.tsx` for exact styling): vertical icon+label, label ~11–12pt `Theme.foregroundLight`, active page highlight per reference (top bar line + brighter color), hover effect via `.onHover`.

- [ ] **Step 4: Footer.swift** — port of `Footer/Stateless.tsx` + `ConnectionSelector`:
  - Bar at window bottom, `Theme.chrome` background, top border `Theme.chromeLine`; collapsed height ~40 per reference.
  - Left: server status text + port (e.g. `Port 9090 | Running`), MCP status chip + toggle + gear (`MdSettings`) opening `.mcpSettings` modal (chip is display-only until Task 15 wires McpServer — bind to placeholder `AppModel.mcpRunning: Bool = false` now).
  - Right: connection selector — expandable list of connections (name, platform, address, connected dot), click selects `session.selectConnection`. Port the expand/collapse arrow behavior.

- [ ] **Step 5: RootView.swift**

```swift
struct RootView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        SideBar()
        pageView.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Footer()
    }
    .background(Theme.background)
    .sheet(item: $model.activeModal) { ... }   // modal cases filled by later tasks; start with EmptyView stubs
    .task { model.startServer() }
  }

  @ViewBuilder private var pageView: some View {
    switch model.currentPage {
    case .home: HomePage()
    case .timeline: Text("Timeline")           // replaced by later tasks
    /* ... one placeholder Text per page until its task lands ... */
    }
  }
}
```

(`Modal` must be `Identifiable` for `.sheet(item:)`.) `HomePage` is Task 8 — for THIS task use `Text("Home")` placeholder.

- [ ] **Step 6: Build, run, verify visually**

Run: `xcodegen && xcodebuild ... build` then launch: `open` the built app from DerivedData or `xcodebuild -showBuildSettings | grep BUILT_PRODUCTS_DIR`.
Expected: dark window, 115pt sidebar with 7 buttons + logo, footer bar, page switches on click, ⌘-click nothing yet. Compare side-by-side with Electron app (`cd /Volumes/samsung/new_mac/opensource/reactotron && yarn && yarn start` — or screenshots in repo docs).

- [ ] **Step 7: Run tests, commit**

```bash
xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test 2>&1 | tail -5
git add -A && git commit -m "feat: app shell — sidebar, footer, navigation, server wiring"
```

---

### Task 8: Home page (welcome + connections)

References: `apps/reactotron-app/src/renderer/pages/home/index.tsx`, `welcome.tsx`.

**Files:**
- Create: `Sources/UI/Pages/HomePage.swift`
- Modify: `Sources/UI/RootView.swift` (swap placeholder)

**Interfaces:**
- Consumes: `AppModel.session.connections`, `Theme`, `Icon`.
- Produces: `struct HomePage: View`.

- [ ] **Step 1: Read both reference files fully.** Port:
  - No connections → welcome screen: Reactotron logo, title, quick-start instructions text and links (open URLs via `NSWorkspace.shared.open`), exactly the copy in `welcome.tsx`.
  - With connections → connection grid/list per `home/index.tsx`: each cell shows name, platform icon/label, address, selected highlight; click → `selectConnection` + navigate to `.timeline` if that's what Electron does (verify in source).
- [ ] **Step 2: Build + visual check against Electron app.**
- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat: home page (welcome + connections)"`

---

### Task 9: TreeView + shared components (Timestamp, PageHeader, EmptyState)

References: `lib/reactotron-core-ui/src/components/TreeView/index.tsx` (uses react-treebeard styling), `Timestamp`, `Header`, `EmptyState` component dirs.

**Files:**
- Create: `Sources/UI/Components/TreeView.swift`
- Create: `Sources/UI/Components/Timestamp.swift`
- Create: `Sources/UI/Components/PageHeader.swift`
- Create: `Sources/UI/Components/EmptyState.swift`
- Test: `Tests/TreeViewModelTests.swift`

**Interfaces:**
- Consumes: `JSONValue`, `Theme`.
- Produces:
  - `struct TreeView: View { init(value: JSONValue, level: Int = 0) }` — recursive disclosure tree of a JSONValue. Value coloring per core-ui/treebeard: keys `Theme.tag`, strings `Theme.string`, numbers `Theme.constant`, bool/null `Theme.constant`, preview text `Theme.foregroundDark`.
  - Collapsed nodes show previews: objects → `{key1: …, key2: …}` truncated, arrays → `N items`.
  - `struct Timestamp: View { let date: Date }` — `HH:mm:ss.SSS` monospace, `Theme.foregroundDark`.
  - `struct PageHeader: View { init(title: String, isDraggable: Bool = true, actions: [HeaderAction]) }` where `HeaderAction = (icon: IconName, tip: String, onTap: () -> Void)`; also supports a tab row variant (used by State/Native pages — port of core-ui `Header` with `HeaderTabButton`): `PageHeader(tabs: [(text: String, icon: IconName, isActive: Bool, onTap: () -> Void)], actions: ...)`.
  - `struct EmptyState: View { init(icon: IconName, title: String, @ViewBuilder message: () -> some View) }` — centered icon+title+body, `Theme.foregroundDark`.
- Also produce a pure helper for tests: `func treePreview(_ value: JSONValue) -> String` (the collapsed-node preview string).

- [ ] **Step 1: Write failing tests for `treePreview`** (object preview truncation, array count, scalar rendering: string quoted, null → `null`, bool → `true`/`false`, NaN → `NaN`).
- [ ] **Step 2: Run tests — expect FAIL** (`cannot find 'treePreview'`).
- [ ] **Step 3: Implement all four components.** TreeView expansion state: `@State private var expanded: Set<String>` keyed by JSON path; rows indented 15pt/level with disclosure triangle.
- [ ] **Step 4: Tests pass + build.**
- [ ] **Step 5: Commit** — `git commit -m "feat: TreeView, Timestamp, PageHeader, EmptyState components"`

---

### Task 10: Timeline command renderers (BaseCommand + all 14)

References — read EVERY file in `lib/reactotron-core-ui/src/timelineCommands/`:
`BaseCommand.tsx`, `ApiResponseCommand`, `AsyncStorageMutationCommand`, `BenchmarkReportCommand`, `ClientIntroCommand`, `DisplayCommand`, `ImageCommand`, `LogCommand`, `SagaTaskCompleteCommand`, `StateActionCompleteCommand`, `StateKeysResponseCommand`, `StateValuesChangeCommand`, `StateValuesResponseCommand`, plus `timelineCommands/index.ts` (`timelineCommandResolver`).

**Files:**
- Create: `Sources/UI/Components/TimelineCommandViews.swift`
- Test: `Tests/TimelineRowModelTests.swift`

**Interfaces:**
- Consumes: `Command`, `JSONValue`, `TreeView`, `Timestamp`, `Theme`, `Icon`, `AppModel` (for actions: dispatch/replay/copy).
- Produces:
  - `struct TimelineCommandRow: View { let command: Command }` — resolver switch on `command.type` → the matching renderer; unknown type → `DisplayCommandView` fallback (matches `timelineCommandResolver` behavior — verify in index.ts).
  - `struct TimelineRowModel { let title: String; let preview: String; let titleColor: Color }` + `static func resolve(_ command: Command) -> TimelineRowModel` — pure, testable title/preview derivation.
- `BaseCommandView` chrome (port `BaseCommand.tsx`): row = [Timestamp] [TITLE tag] [preview] […toolbar icons on hover], tap toggles expanded detail area; `important` commands tinted per reference; bottom border `Theme.line`.

**Per-type behavior table (verify each against its source file while porting):**

| type | Title | Preview | Expanded body |
|---|---|---|---|
| client.intro | CONNECTION | "Connection" | TreeView of intro payload |
| log (level debug) | LOG | message text (first line) | text or TreeView if object |
| log (level warn) | WARN (warning color) | same | same + stack if present |
| log (level error) | ERROR (error/tag color) | same | same + stack rendering |
| api.response | API RESPONSE | `[status] [method] [url path]` (duration right) | Tabs: Response body / Request / Headers (port exact tab structure) |
| state.action.complete | ACTION | action type string | TreeView of action; toolbar: replay (dispatch again) |
| state.values.change | SUBSCRIPTION | `N changes` | path→new value rows w/ TreeView |
| state.values.response | STATE | path or "State" | TreeView of value |
| state.keys.response | STATE KEYS | path | list of keys |
| state.backup.response | SNAPSHOT | "Snapshot" | TreeView of state |
| asyncStorage.mutation | ASYNC STORAGE | action summary | TreeView |
| saga.task.complete | SAGA | task name + duration | effect tree per reference |
| benchmark.report | BENCHMARK | report title | step table with ms deltas |
| display | custom `payload.name` | `payload.preview` | `payload.value` TreeView or image if `payload.image` |
| image | IMAGE | uri | AsyncImage |
| customCommand.register / unregister | resolves via display fallback — confirm in index.ts | | |

Toolbar icons common to rows (from BaseCommand): copy payload to clipboard (`NSPasteboard`), tooltips via `.help(_:)`. Fetch any new icons via the Task 7 unpkg method.

Commands carry an optional `diff` (state.action.complete when the client sends one): port `TreeViewDiff` (`lib/reactotron-core-ui/src/components/TreeViewDiff`) as part of this file and render it in the ACTION expanded body when `command.diff != nil`, matching `StateActionCompleteCommand`.

- [ ] **Step 1: Write failing tests for `TimelineRowModel.resolve`** covering: log debug/warn/error titles, api.response preview composition (status+method+path), state.action.complete title from action type, display custom name, unknown type falls back to display. Use realistic payloads copied from the reference test fixtures if present (`lib/reactotron-core-ui` has stories/tests — check `*.story.tsx` for sample payloads).
- [ ] **Step 2: Run tests — expect FAIL.**
- [ ] **Step 3: Implement `TimelineRowModel.resolve` until tests pass.**
- [ ] **Step 4: Implement the views** (BaseCommandView + one view per type + resolver switch). Build.
- [ ] **Step 5: Visual check:** run app + example-app (`cd /Volumes/samsung/new_mac/opensource/reactotron/apps/example-app && yarn && yarn ios` — or any handy RN app pointing at localhost:9090) and compare every row type with Electron side-by-side.
- [ ] **Step 6: Commit** — `git commit -m "feat: all 14 timeline command renderers"`

---

### Task 11: Timeline page (search / filter / reverse / clear / export)

References: `apps/reactotron-app/src/renderer/pages/timeline/index.tsx`, `lib/reactotron-core-ui/src/utils/filterCommands` (find exact file), `lib/reactotron-core-ui/src/modals/TimelineFilterModal`.

**Files:**
- Create: `Sources/UI/Pages/TimelinePage.swift`
- Create: `Sources/UI/Modals/ModalChrome.swift`
- Create: `Sources/UI/Modals/TimelineFilterModal.swift`
- Create: `Sources/State/TimelineState.swift`
- Modify: `Sources/UI/RootView.swift` (mount page + modal case)
- Test: `Tests/FilterCommandsTests.swift`

**Interfaces:**
- Consumes: `SessionStore.selectedConnection.commands`, `TimelineCommandRow`, `PageHeader`, `EmptyState`, `Icons`.
- Produces:
  - `@MainActor @Observable final class TimelineState` (owned by AppModel: `let timeline = TimelineState()`): `var isSearchOpen: Bool`, `var search: String`, `var isReversed: Bool`, `var hiddenCommands: Set<String>` (persisted to UserDefaults key `hiddenCommands`).
  - `func filterCommands(_ commands: [Command], search: String, hidden: Set<String>) -> [Command]` — pure port of core-ui `filterCommands` (read source; it matches search text against type + serialized payload fields, case-insensitive).
  - `struct TimelinePage: View`, `struct TimelineFilterModal: View`.
  - `ModalChrome`: dark sheet container port of core-ui `Modal` — `Theme.modalOverlay` backdrop, panel `Theme.background`, title row, ESC/onClose; used by all later modals.
- [ ] **Step 1: Write failing tests for `filterCommands`** (search matches payload message, search matches type name, hidden types excluded, empty search returns all minus hidden).
- [ ] **Step 2: Run tests — expect FAIL.**
- [ ] **Step 3: Implement `filterCommands` + `TimelineState`. Tests pass.**
- [ ] **Step 4: Implement TimelinePage:**
  - `PageHeader(title: "Timeline", actions:)` with: MdDownload export (write `~/Downloads/timeline-log-<epochMillis>.json` of raw commands JSON), MdSearch toggle, MdFilterList → open filter modal, MdSwapVert reverse, MdDeleteSweep → `clearSelectedConnectionCommands()` + send `"clear"`? — **verify**: Electron `clearCommands` only clears local store (check `contexts` source; replicate exactly).
  - Search bar (visible when `isSearchOpen`): label "Filter:", rounded input `Theme.backgroundSubtleDark`, FaTimes clears + closes.
  - `ScrollView + LazyVStack` of `TimelineCommandRow` for `filterCommands(...)`, reversed when `isReversed`.
  - Empty → `EmptyState(icon: MdReorder, title: "No Activity")` with quick-start button opening `https://docs.infinite.red/reactotron/quick-start/react-native/` and RandomJoke section (port `RandomJoke` — static joke list from core-ui source, random pick).
- [ ] **Step 5: Implement TimelineFilterModal** (port): checkbox grid of command types grouped as in reference, toggling membership in `hiddenCommands`.
- [ ] **Step 6: Build + visual check with live client (compare Electron).**
- [ ] **Step 7: Commit** — `git commit -m "feat: timeline page with search/filter/reverse/clear/export"`
---

### Task 12: State pages (Subscriptions, Snapshots) + Dispatch/Rename/Add modals

References: `apps/reactotron-app/src/renderer/pages/state/Subscriptions.tsx`, `Snapshots.tsx`, `lib/reactotron-core-ui/src/modals/DispatchActionModal`, `SnapshotRenameModal`, `SubscriptionAddModal`, and `lib/reactotron-core-ui/src/contexts/State` (subscription/snapshot bookkeeping — read fully; it drives both pages).

**Files:**
- Create: `Sources/State/StateUIStore.swift`
- Create: `Sources/UI/Pages/SubscriptionsPage.swift`, `Sources/UI/Pages/SnapshotsPage.swift`
- Create: `Sources/UI/Modals/DispatchActionModal.swift`, `Sources/UI/Modals/SnapshotRenameModal.swift`, `Sources/UI/Modals/SubscriptionAddModal.swift`
- Modify: `Sources/App/AppModel.swift` (extend `Modal.snapshotRename(SnapshotItem)`), `Sources/UI/RootView.swift`
- Test: `Tests/StateUIStoreTests.swift`

**Interfaces:**
- Consumes: `AppModel.sendCommand`, `server.stateValuesSubscribe/Unsubscribe/ClearSubscriptions`, `SessionStore`, components from Task 9, `ModalChrome`.
- Produces:

```swift
struct SnapshotItem: Identifiable, Equatable {
  let id: UUID
  var name: String
  let date: Date
  let state: JSONValue
}

@MainActor @Observable
final class StateUIStore {           // owned by AppModel: let stateUI = StateUIStore()
  var subscriptionValues: [(path: String, value: JSONValue)] = []  // from latest state.values.change
  var snapshots: [SnapshotItem] = []
  func handle(command: Command)      // called from AppModel command pipeline:
  // - state.values.change → update subscriptionValues from payload.changes [{path, value}]
  // - state.backup.response → append SnapshotItem(name: "Snapshot N" or payload name, state: payload.state)
}
```

- Pages:
  - **SubscriptionsPage**: `PageHeader` with tabs [Subscriptions | Snapshots] (navigates between the two state pages — port of the shared State header) + actions: add (`MdNotificationsNone`/per ref → opens SubscriptionAddModal, ⌘N), clear all. Rows: path label (Theme.tag) + TreeView value; hover shows delete. Empty state per reference copy.
  - **SnapshotsPage**: same tab header + action: capture (`MdAdd` per ref) → `sendCommand("state.backup.request", .object([:]))`. Rows: name, relative/absolute time, actions restore (`sendCommand("state.restore.request", payload ["state": snapshot.state])` — **verify exact payload key in Snapshots.tsx**), rename (modal), delete.
- Modals:
  - **SubscriptionAddModal**: text field for path, Subscribe button → `server.stateValuesSubscribe(path:)`; ENTER submits.
  - **SnapshotRenameModal**: text field pre-filled with current name → rename in store.
  - **DispatchActionModal** (⌘D anywhere per keybinds): multiline JSON editor seeded `{\n  "type": ""\n}` (match reference seed text), Dispatch button parses JSON (error state on invalid) → `sendCommand("state.action.dispatch", .object(["action": parsed]))`.

- [ ] **Step 1: Failing tests for `StateUIStore.handle`** (values.change updates pairs; backup.response appends snapshot with default numbered name).
- [ ] **Step 2: Tests fail → implement store → tests pass.**
- [ ] **Step 3: Implement pages + modals per reference files. Build.**
- [ ] **Step 4: Live check with example-app:** subscribe to a path, see live updates; capture/restore snapshot; dispatch action; compare with Electron.
- [ ] **Step 5: Commit** — `git commit -m "feat: state subscriptions & snapshots pages with modals"`

---

### Task 13: React Native pages (Overlay, Storybook) + Custom Commands page

References: `apps/reactotron-app/src/renderer/pages/reactNative/Overlay.tsx`, `Storybook.tsx`, `components/` in that dir, `apps/reactotron-app/src/renderer/pages/customCommands/index.tsx`.

**Files:**
- Create: `Sources/UI/Pages/OverlayPage.swift`, `Sources/UI/Pages/StorybookPage.swift`, `Sources/UI/Pages/CustomCommandsPage.swift`
- Modify: `Sources/State/SessionStore.swift` — add `var customCommands: [CustomCommand] = []` to `SessionConnection`; on `customCommand.register` command append a `CustomCommand` to it, on `customCommand.unregister` remove by id, on disconnect clear (mirror server-side registry; UI reads from store).
- Modify: `Sources/UI/RootView.swift`
- Test: extend `Tests/SessionStoreTests.swift` with register/unregister/disconnect-clears cases.

**Interfaces:**
- Consumes: `AppModel.sendCommand`, PageHeader tabs (Overlay | Storybook), `Theme`.
- Produces: the three pages.

**Port notes:**
- **OverlayPage**: image-overlay debugging tool — port the exact form controls from `Overlay.tsx` (image URL/paste, opacity slider, alignment/justify controls, margin inputs, resize mode, on-change sends `sendCommand("overlay", payload)` with the same payload keys; read the file for exact keys and defaults).
- **StorybookPage**: toggle switch → `sendCommand("storybook", .bool(isOn))` (verify payload shape in source — Electron sends plain boolean payload).
- **CustomCommandsPage**: cards for `session.selectedConnection?.customCommands`: title (or command name), description, one text field per `arg` (name label), Send button → `sendCommand("custom", .object(["command": .string(cmd.command), "args": argsObject]))`. Empty state copy from reference.

- [ ] **Step 1: Failing store tests for custom command registry → implement → pass.**
- [ ] **Step 2: Implement three pages per reference. Build.**
- [ ] **Step 3: Live check with example-app (it registers demo custom commands; verify buttons appear and execute; verify overlay/storybook commands reach client).**
- [ ] **Step 4: Commit** — `git commit -m "feat: react native pages and custom commands"`

---

### Task 14: Help page, keybindings, native menu

References: `apps/reactotron-app/src/renderer/pages/help/index.tsx` + `components/`, `KeybindHandler.tsx`, `apps/reactotron-app/src/main/menu.ts`, `lib/reactotron-core-ui/src/components/RandomJoke`.

**Files:**
- Create: `Sources/UI/Pages/HelpPage.swift`
- Create: `Sources/App/AppCommands.swift` (SwiftUI `Commands` — menu + keybindings)
- Modify: `Sources/App/ReactotronApp.swift` (`.commands { AppCommands(model:) }`)

**Interfaces:**
- Consumes: `AppModel` (page switching, timeline clear, search toggle, modals), `Theme`.
- Produces: `HelpPage`, `AppCommands: Commands`.

**Keybindings (port of KeybindHandler.tsx — all with ⌘; ctrl variants are Windows/Linux, skip):**

| Shortcut | Action |
|---|---|
| ⌘⇧S | `model.sidebarVisible.toggle()` |
| ⌘⇧L | timeline search toggle |
| ⌘1 | `.home` |
| ⌘2 | `.timeline` |
| ⌘3 | `.stateSubscriptions` |
| ⌘4 | `.nativeOverlay` |
| ⌘5 | `.customCommands` |
| ⌘⇧/ (i.e. ⌘?) | `.help` |
| ⌘K | clear selected connection commands |
| ⌘N | open SubscriptionAddModal |
| ⌘D | open DispatchActionModal |

Implement as `CommandGroup`/`CommandMenu` entries so they appear in the native menu bar with shortcuts (this simultaneously satisfies the menu.ts port — replicate menu.ts's menu structure: app menu with About/Quit, Edit with standard items, View (sidebar toggle, page navigation), Help menu with the external links from menu.ts: docs/repo/feedback — read menu.ts for exact labels/URLs).

**HelpPage:** port `help/index.tsx`: Reactotron logo + version, external link buttons (exact links/labels from source — repo, feedback, docs, squad), keystrokes reference grid (list the table above), RandomJoke at bottom (port joke array from RandomJoke component source).

- [ ] **Step 1: Implement AppCommands + wire in app. Build; verify every shortcut works and menu items appear.**
- [ ] **Step 2: Implement HelpPage per reference. Build + visual check.**
- [ ] **Step 3: Commit** — `git commit -m "feat: help page, keybindings, native menu"`

---

### Task 15: MCP server (HTTP + JSON-RPC + tools + resources + redaction) + settings modal

References — read fully: `lib/reactotron-mcp/src/mcp-server.ts`, `tools.ts`, `resources.ts`, `serialization.ts`, `redaction.ts`, `apps/reactotron-app/src/renderer/components/McpSettingsModal/index.tsx`, plus how the Electron app wires MCP in `contexts/Standalone/index.tsx`.

**Files:**
- Create: `Sources/Core/MCP/MinimalHTTPServer.swift`
- Create: `Sources/Core/MCP/Redaction.swift`
- Create: `Sources/Core/MCP/McpServer.swift`
- Create: `Sources/UI/Modals/McpSettingsModal.swift`
- Modify: `Sources/App/AppModel.swift` (own `McpServer`, `var mcpRunning`, toggle from Footer), `Sources/State/SettingsStore.swift` (wire real Redaction defaults), `Sources/UI/Components/Footer.swift` (live status)
- Test: `Tests/RedactionTests.swift`, `Tests/McpServerTests.swift`

**Interfaces:**
- Consumes: `ReactotronServer` (`send`, `customCommands`, subscriptions), command stream (AppModel forwards every `Command` to `mcp.buffer(command:)`), `SettingsStore`, `JSONValue`.
- Produces:

```swift
/// Minimal HTTP/1.1 server on NWListener (TCP, no WS): parses request line, headers,
/// Content-Length body; hands (method, path, headers, body) to a handler returning
/// (status, headers, body). Connection: close after each response (keep-alive optional).
final class MinimalHTTPServer: @unchecked Sendable {
  init(handler: @escaping @Sendable (_ method: String, _ path: String,
       _ headers: [String: String], _ body: Data) -> (Int, [String: String], Data))
  func start(port: UInt16) throws
  func stop()
}

enum Redaction {
  static let REDACTED = "[REDACTED]"
  static let defaultSensitiveKeys: [String]   // VERBATIM list from redaction.ts (password, passwd, pwd, secret, client_secret, clientsecret, credentials, ssn, creditcard, privatekey, private_key, apikey, api_key, x-api-key, accesstoken, access_token, refreshtoken, refresh_token, idtoken, id_token, token, bearer, jwt, session, sessionid, session_id, csrf, xsrf, csrf_token, xsrf_token, authorization, cookie, set-cookie, proxy-authorization, x-auth-token, x-csrf-token, x-xsrf-token, csrf-token, x-forwarded-for, x-real-ip)
  static let defaultValuePatterns: [String]   // VERBATIM regex list from redaction.ts (Bearer tokens, JWTs, sk-…, sk-ant-…, gh[pousr]_…, xox[bpoas]-…, AKIA…, AIza…, stripe keys, PEM blocks)
  struct Rules { var sensitiveKeys: [String]; var statePathPatterns: [String]; var valuePatterns: [String] }
  /// Walk a JSONValue: object keys matching sensitiveKeys (case-insensitive) → .string(REDACTED);
  /// string values matched by any valuePattern regex → matched ranges replaced with REDACTED.
  /// Port the exact matching semantics from redaction.ts `redact*` functions.
  static func redact(_ value: JSONValue, rules: Rules) -> JSONValue
}

@MainActor @Observable
final class McpServer {
  private(set) var running = false
  private(set) var port: Int?
  func start(port: Int)
  func stop()
  func buffer(_ command: Command)      // ring buffer, max 500 (BUFFER_SIZE in mcp-server.ts)
  var rules: Redaction.Rules           // live-updatable from settings modal
}
```

**JSON-RPC dispatch (streamable HTTP, POST `/mcp`):**
- `initialize` → `{"jsonrpc":"2.0","id":<id>,"result":{"protocolVersion":"2025-03-26","capabilities":{"tools":{},"resources":{}},"serverInfo":{"name":"reactotron-mcp","version":"1.0.0"}}}` (match name/version in mcp-server.ts).
- `notifications/initialized` (no id) → HTTP 202, empty body.
- `ping` → `{}` result.
- `tools/list` → the 10 tools, names/descriptions/inputSchemas **copied from tools.ts registrations**: `dispatch_action`, `request_state`, `request_state_keys`, `swap_state`, `send_custom_command`, `list_custom_commands`, `show_overlay`, `clear_timeline`, `subscribe_state`, `unsubscribe_state`.
- `tools/call` → execute against `ReactotronServer`/`AppModel`. Tools that need a client response (`request_state`, `request_state_keys`, …) must port the wait-for-response pattern in tools.ts: register a one-shot command listener filtered by response type, timeout per the source (find exact ms), then respond `{"content":[{"type":"text","text":<json>}]}`. All returned data passes through `Redaction.redact`.
- `resources/list` + `resources/templates/list` + `resources/read` → port `resources.ts`: `reactotron://timeline` (summarized last events, port the summarize function from resources.ts/serialization.ts), `reactotron://timeline/{type}` template, `reactotron://state/current` (requests live state like the tool), `reactotron://network/log` (api.response events). All redacted.
- Unknown method → JSON-RPC error `-32601`. Malformed JSON → `-32700`. GET `/mcp` → 405. DELETE `/mcp` → 200.

**McpSettingsModal:** port of McpSettingsModal — "MCP Redaction Settings" title; editable lists (sensitive keys, state path patterns, value patterns; add/remove rows), toggles for allowClientDisable/allowClientRemoveRules, writes to `SettingsStore` and `mcp.rules` live.

**Footer wiring:** status chip shows MCP `stopped/running :<port>`, redaction-enforced indicator, toggle button start/stop, gear opens modal (replace Task 7 placeholder).

- [ ] **Step 1: Failing RedactionTests** (sensitive key redacted case-insensitively at depth; Bearer token substring replaced; PEM block replaced; non-matching value untouched) → implement Redaction → pass.
- [ ] **Step 2: Failing McpServerTests** via URLSession against `127.0.0.1:<random port>`: initialize handshake returns protocolVersion+serverInfo; tools/list returns 10 tools; tools/call `clear_timeline` succeeds; tools/call `list_custom_commands` returns registered commands; resources/read `reactotron://timeline` returns buffered (and redacted) events; unknown method → -32601.
- [ ] **Step 3: Implement MinimalHTTPServer + McpServer until tests pass.**
- [ ] **Step 4: Implement McpSettingsModal + footer wiring. Build.**
- [ ] **Step 5: E2E sanity: add `{"mcpServers":{"reactotron":{"type":"http","url":"http://localhost:4567/mcp"}}}` to an MCP client (e.g. `claude mcp add --transport http reactotron http://localhost:4567/mcp`) and verify tools list + a call.**
- [ ] **Step 6: Commit** — `git commit -m "feat: MCP server with tools, resources, redaction, settings UI"`

---

### Task 16: Android adb integration

Reference: `apps/reactotron-app/src/main/utils.ts` (read fully).

**Files:**
- Create: `Sources/Core/Android/AndroidDeviceManager.swift`
- Modify: `Sources/App/AppModel.swift` (own it; start alongside server)

**Interfaces:**
- Consumes: `SettingsStore.serverPort`.
- Produces:

```swift
final class AndroidDeviceManager: @unchecked Sendable {
  var onNotice: @Sendable (String) -> Void = { _ in }   // non-fatal problems → UI notice
  func start(serverPort: Int)   // runs initial reverse + begins track-devices
  func stop()
}
```

**Port semantics from utils.ts:**
- Resolve `adb` via PATH (`Process` with `/usr/bin/env adb …`); also honor `$ANDROID_HOME/platform-tools/adb` if env var set (check utils.ts for exact lookup; replicate).
- On start: `adb devices` → parse serials (lines matching `<serial>\tdevice`), then per device `adb -s <serial> reverse tcp:<port> tcp:<port>`.
- Spawn long-running `adb track-devices`; on each output chunk re-run the devices+reverse pass (utils.ts re-applies on device list changes).
- Any spawn failure (adb missing) → `onNotice("Error occurred running adb …")` once; never crash. AppModel surfaces notice as a dismissible banner/alert (match Electron's dialog copy).
- `stop()` terminates the track-devices process.

- [ ] **Step 1: Implement; manual test:** with an Android emulator running, launch app → `adb reverse --list` shows `tcp:9090`; without adb in PATH → app still launches, notice shown.
- [ ] **Step 2: Build + full test suite pass.**
- [ ] **Step 3: Commit** — `git commit -m "feat: adb reverse + track-devices integration"`

---

### Task 17: Parity pass + README + final verification

**Files:**
- Create: `README.md` (what this is, build instructions: `xcodegen && xcodebuild …`, how to point clients at it — nothing changes for clients)
- Modify: anything the parity pass flags

- [ ] **Step 1: Run Electron Reactotron and native app side-by-side** (different ports: Electron 9090, native 9091 via settings — then swap) against `apps/example-app`. Walk EVERY page and interaction:
  - welcome screen copy/layout; connection appears on connect; auto-select
  - every timeline row type renders equal (send each command type from example app)
  - search, filter modal, reverse, clear, export file
  - subscriptions add/remove/live-update; snapshots capture/rename/restore
  - dispatch action modal (⌘D) round-trip; custom commands execute
  - overlay + storybook commands
  - all keyboard shortcuts; sidebar toggle animation; footer connection switcher
  - MCP: tools/resources from a real MCP client; redaction settings persist across relaunch
  - kill client → disconnect handling; reconnect → same clientId path; two simultaneous clients → selector works
  - port conflict: start native app while Electron holds 9090 → portUnavailable UI, change port, retry works
- [ ] **Step 2: Fix all discrepancies found (commit per fix).**
- [ ] **Step 3: Full test suite:** `xcodebuild -project Reactotron.xcodeproj -scheme Reactotron test` → `** TEST SUCCEEDED **`
- [ ] **Step 4: Write README.md, commit** — `git commit -m "docs: README with build and usage instructions"`
