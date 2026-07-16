import SwiftUI
import AppKit

/// Port of `pages/home/index.tsx` (`Connections`) + `pages/home/welcome.tsx` (`Welcome`).
///
/// `AndroidDeviceHelp` (also rendered by `index.tsx`, below the connection list) is
/// intentionally NOT ported — it's Electron-`ipcRenderer`-specific tooling that shells
/// out to `adb devices` from the main process to help debug USB-connected Android
/// devices. There's no equivalent IPC/adb bridge in this native app, and no task in
/// the plan introduces one, so it's out of scope rather than silently dropped.
struct HomePage: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      header
      if model.session.connections.isEmpty {
        WelcomeView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(model.session.connections) { sessionConnection in
              ConnectionCell(connection: sessionConnection.connection)
            }
          }
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  /// Port of `reactotron-core-ui`'s `Header` as used here: `title="Connections"`,
  /// no tabs/actions. `isDraggable` (`-webkit-app-region: drag`, for Electron's
  /// frameless custom title bar) has no equivalent need here — this app uses a
  /// native macOS title bar/window chrome, which is already draggable.
  private var header: some View {
    Text("Connections")
      .font(Theme.font())
      .foregroundStyle(Theme.foregroundLight)
      .frame(maxWidth: .infinity)
      .frame(height: 70)
      .background(Theme.backgroundSubtleLight)
      .overlay(alignment: .bottom) {
        Rectangle().fill(Theme.chromeLine).frame(height: 1)
      }
      .shadow(color: Theme.glow, radius: 15, y: 2)
  }
}

// MARK: - Welcome (no connections)

/// Port of `welcome.tsx`'s `Welcome` — copy is verbatim from the source.
private struct WelcomeView: View {
  /// Loose bundled resource, same loading pattern as `SideBarButton`'s logo (Task 7):
  /// `Bundle.main.url(forResource:withExtension:)` + `NSImage(contentsOf:)`, not
  /// `Image(_:)`/`NSImage(named:)` which target asset-catalog entries.
  private static let reactotronLogoImage: NSImage = {
    if let url = Bundle.main.url(forResource: "Reactotron-128", withExtension: "png"),
      let image = NSImage(contentsOf: url) {
      return image
    }
    return NSImage()
  }()

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: Self.reactotronLogoImage)
        .resizable()
        .frame(width: 100, height: 100)
        .padding(.bottom, 4)

      Text("Welcome to Reactotron!")
        .font(Theme.font(32))
        .foregroundStyle(Theme.foregroundLight)
        .padding(.top, 10)
        .padding(.bottom, 50)

      VStack(spacing: 8) {
        Text("Connect a device or simulator to get started.")
          .font(Theme.font(17.5))
        Text("Need to set up your app to use Reactotron?")
          .font(Theme.font(17.5))

        Button {
          NSWorkspace.shared.open(URL(string: "https://docs.infinite.red/reactotron/")!)
        } label: {
          Text("Check out the docs here!")
            .font(Theme.font())
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundLighter))
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
      }
      .foregroundStyle(Theme.foreground)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 400)
    }
    .foregroundStyle(Theme.foregroundLight)
  }
}

// MARK: - Connection list (has connections)

/// Port of `index.tsx`'s `ConnectionCell`. Fields shown, in order: platform icon,
/// connection name, `"{platformName} {platformDetails}"`, and screen size. The
/// screen column (divider + text) always renders, even when the screen string is
/// empty — matching `<Screen>{screen}</Screen>`, which is unconditional in the
/// source (only the *text content* is conditionally non-empty, not the element).
/// There is no `onClick` on `ConnectionContainer` in the source, no address field,
/// and no selected-state styling: this list is purely informational
/// (selection/click-to-navigate lives in the footer's connection selector, ported
/// in Task 7).
private struct ConnectionCell: View {
  let connection: Connection

  var body: some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        Icon(connectionIcon(for: connection), size: 32, color: Theme.foregroundLight)

        Text(connectionName(for: connection))
          .font(Theme.font())
          .foregroundStyle(Theme.tag)
          .lineLimit(1)
          .padding(.leading, 10)
          .frame(width: proxy.size.width * 0.25, alignment: .leading)

        HStack(spacing: 10) {
          Rectangle().fill(Theme.subtleLine).frame(width: 1)
          Text("\(platformName(for: connection)) \(platformDetails(for: connection))")
            .font(Theme.font())
            .foregroundStyle(Theme.foregroundDark)
        }
        .padding(.leading, 10)

        HStack(spacing: 10) {
          Rectangle().fill(Theme.subtleLine).frame(width: 1)
          Text(screenSize(for: connection))
            .font(Theme.font())
            .foregroundStyle(Theme.backgroundHighlight)
        }
        .padding(.leading, 10)

        Spacer(minLength: 0)
      }
      .frame(maxHeight: .infinity, alignment: .center)
    }
    .frame(height: 32)
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Theme.line).frame(height: 1)
    }
  }
}

// MARK: - connectionHelpers.ts port

/// Port of `getBrowserApp`: checks the connection's user agent for each browser's
/// signature substring. Order matters — Chrome's UA also contains "Safari/", so
/// Chrome must be checked first (matches the source's comment to that effect).
/// Falls back to "Edge" when nothing matches, same as the source.
private func browserApp(for connection: Connection) -> String {
  let ua = connection.intro["userAgent"]?.stringValue ?? ""
  if ua.contains("Firefox/") { return "Firefox" }
  if ua.contains("Chrome/") { return "Chrome" }
  if ua.contains("Safari/") { return "Safari" }
  if ua.contains("Edge/") { return "Edge" }
  return "Edge"
}

/// Port of `getPlatformName`.
private func platformName(for connection: Connection) -> String {
  switch connection.platform {
  case "ios": return "iOS"
  case "android": return "Android"
  case "browser":
    let app = browserApp(for: connection)
    return app.isEmpty ? "Browser" : app
  default:
    return connection.platform.isEmpty ? "Unknown platform" : connection.platform
  }
}

/// Port of `getPlatformDetails`.
private func platformDetails(for connection: Connection) -> String {
  switch connection.platform {
  case "ios":
    return connection.platformVersion ?? ""
  case "android":
    if let osRelease = connection.osRelease, !osRelease.isEmpty {
      return "\(osRelease) (sdk \(connection.platformVersion ?? ""))"
    } else {
      return "sdk \(connection.platformVersion ?? "")"
    }
  case "browser":
    return connection.platformVersion == "MacIntel" ? "macOS" : (connection.platformVersion ?? "")
  default:
    return ""
  }
}

/// Port of `getConnectionName`.
private func connectionName(for connection: Connection) -> String {
  guard let name = connection.name, !name.isEmpty else { return "Name unknown" }
  return name
}

/// Port of `getScreen`: `windowWidth`/`windowHeight`/`screenScale` aren't modeled as
/// `Connection` properties (Task 7's scope didn't need them) — read straight off the
/// raw `intro` payload, same source data the TSX reads via destructuring.
private func screenSize(for connection: Connection) -> String {
  guard
    let width = connection.intro["windowWidth"]?.numberValue, width != 0,
    let height = connection.intro["windowHeight"]?.numberValue, height != 0,
    let scale = connection.intro["screenScale"]?.numberValue, scale != 0
  else { return "" }
  return "\(jsNumberString(width)) x \(jsNumberString(height)) @ \(jsNumberString(scale))x"
}

/// JS template-literal number formatting has no trailing ".0" for whole numbers
/// (`` `${5}` === "5" ``, not "5.0").
private func jsNumberString(_ n: Double) -> String {
  n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
}

/// Port of `getIcon`: phone icons for iOS/Android, browser icons (by sniffed
/// browser) for the "browser" platform, `FaQuestion` for anything else.
private func connectionIcon(for connection: Connection) -> IconName {
  if connection.platform == "browser" {
    switch browserApp(for: connection) {
    case "Firefox": return .faFirefox
    case "Chrome": return .faChrome
    case "Safari": return .faSafari
    case "Edge": return .faEdge
    default: return .faQuestion
    }
  }
  switch connection.platform {
  case "ios": return .faApple
  case "android": return .faAndroid
  default: return .faQuestion
  }
}
