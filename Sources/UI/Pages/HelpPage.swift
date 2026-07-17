import SwiftUI
import AppKit

/// Port of `pages/help/index.tsx`'s `Help`.
///
/// One deliberate addition beyond the source: a `RandomJoke()` at the bottom,
/// per the task brief. `help/index.tsx` itself never renders `RandomJoke` —
/// that component is only used by `pages/timeline/index.tsx`'s empty state
/// (already ported onto `TimelinePage`, Task 11) — so this is a brief-directed
/// embellishment, not a mechanical port of the reference file. Reuses that
/// same `RandomJoke` view (`Sources/UI/Pages/TimelinePage.swift`) rather than
/// duplicating its joke list.
struct HelpPage: View {
  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "Using Reactotron \(appVersionString(infoDictionary: Bundle.main.infoDictionary))")

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          logo

          sectionTitle("Let's Connect!")
          connectRow

          sectionTitle("Keystrokes")
          ForEach(AppKeybinds.grouped, id: \.name) { group in
            KeybindGroupView(name: group.name, keybinds: group.keybinds)
          }

          Rectangle()
            .fill(Theme.foregroundDark)
            .frame(height: 1)
            .padding(.vertical, 30)

          HStack {
            Spacer(minLength: 0)
            RandomJoke()
            Spacer(minLength: 0)
          }
        }
        .padding(20)
      }
    }
  }

  // MARK: - Logo

  /// Same loose-bundled-resource pattern as `SideBarButton`/`WelcomeView`
  /// (Tasks 7/8): `Bundle.main.url(forResource:withExtension:)` +
  /// `NSImage(contentsOf:)`, not an asset-catalog lookup.
  private static let reactotronLogoImage: NSImage = {
    if let url = Bundle.main.url(forResource: "Reactotron-128", withExtension: "png"),
      let image = NSImage(contentsOf: url) {
      return image
    }
    return NSImage()
  }()

  private var logo: some View {
    HStack {
      Spacer(minLength: 0)
      Image(nsImage: Self.reactotronLogoImage)
        .resizable()
        .frame(width: 128, height: 128)
      Spacer(minLength: 0)
    }
    .padding(.vertical, 20)
  }

  // MARK: - "Let's Connect!" row

  /// Port of the `ConnectContainer`'s 4 `ItemContainer` buttons — icons,
  /// labels, and URLs verbatim from `help/index.tsx`.
  private var connectRow: some View {
    HStack(alignment: .top, spacing: 10) {
      ConnectLinkButton(icon: .goRepo, label: "GitHub Docs") {
        openExternal("https://github.com/infinitered/reactotron")
      }
      ConnectLinkButton(icon: .goComment, label: "Feedback") {
        openExternal("https://github.com/infinitered/reactotron/issues/new")
      }
      ConnectLinkButton(icon: .goSquirrel, label: "Updates") {
        openExternal("https://github.com/infinitered/reactotron/releases")
      }
      ConnectLinkButton(icon: .faTwitter, label: "@reactotron") {
        openExternal("https://twitter.com/reactotron")
      }
    }
    .padding(.bottom, 50)
  }

  private func openExternal(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Section title

  /// Port of `help/index.tsx`'s `Title` styled-component: 18px text, a
  /// vertical margin, and a highlight-colored underline hugging the text.
  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(Theme.font(18))
      .foregroundStyle(Theme.foregroundLight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 10)
      .padding(.bottom, 2)
      .overlay(alignment: .bottom) {
        Rectangle().fill(Theme.highlight).frame(height: 1)
      }
      .padding(.bottom, 10)
  }
}

// MARK: - Version helper

/// Reads `CFBundleShortVersionString` for the Help page's "Using Reactotron
/// {version}" title — a port of `` `Using Reactotron ${projectJson.version}` ``,
/// where `projectJson` is the app's own `package.json`. Takes the dictionary
/// as a parameter (rather than reading `Bundle.main` internally) so it's a
/// pure, unit-testable function.
func appVersionString(infoDictionary: [String: Any]?) -> String {
  guard let version = infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty else {
    return "0.0.0"
  }
  return version
}

// MARK: - ConnectLinkButton

/// Port of `SharedStyles.ts`'s `ItemContainer`/`ItemIconContainer`: a
/// centered icon-over-label button with a subtle chrome background and
/// border.
private struct ConnectLinkButton: View {
  let icon: IconName
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Icon(icon, size: 40, color: Theme.foregroundLight)
        Text(label)
          .font(Theme.font())
          .foregroundStyle(Theme.foreground)
      }
      .padding(10)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 5).fill(Theme.chrome))
      .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.chromeLine, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Keystrokes grid

/// Port of `help/index.tsx`'s `components/KeybindGroup.tsx`: a group name
/// label (highlight-colored) over a vertical stack of its keybinds.
private struct KeybindGroupView: View {
  let name: String
  let keybinds: [AppKeybind]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(name)
        .font(Theme.font())
        .foregroundStyle(Theme.highlight)

      VStack(alignment: .leading, spacing: 0) {
        ForEach(keybinds) { keybind in
          KeybindRow(keybind: keybind)
        }
      }
    }
    .padding(.bottom, 35)
  }
}

/// Port of `help/index.tsx`'s `components/Keybind.tsx`: a fixed-width row of
/// keycap chips (one per `+`-separated token) followed by the binding's name.
private struct KeybindRow: View {
  let keybind: AppKeybind

  /// Verbatim port of `Keybind.tsx`'s `KEY_REMAPS` — note the source maps
  /// `shift` to "⬆" (an up-arrow glyph), not "⇧"; kept as-is rather than
  /// "corrected", since this task ports the source exactly.
  private static let keyRemaps: [String: String] = ["command": "⌘", "ctrl": "CTRL", "shift": "⬆"]

  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: 2) {
        ForEach(Array(keybind.tokens.enumerated()), id: \.offset) { index, token in
          keyCap(token)
          if index < keybind.tokens.count - 1 {
            Text("+")
              .font(Theme.font())
              .foregroundStyle(Theme.foreground)
              .padding(.horizontal, 2)
          }
        }
      }
      .frame(width: 180, alignment: .leading)

      Text(keybind.name)
        .font(Theme.font())
        .foregroundStyle(Theme.foreground)
    }
    .padding(.vertical, 5)
  }

  private func keyCap(_ token: String) -> some View {
    Text(Self.keyRemaps[token.lowercased()] ?? token.lowercased())
      .font(Theme.font(14, weight: .bold))
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(Theme.foreground)
      .foregroundStyle(Theme.background)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 1).fill(Theme.highlight).frame(height: 2)
      }
  }
}
