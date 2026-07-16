import SwiftUI
import AppKit

/// Loose bundled resource (Copy Bundle Resources, not an asset catalog) —
/// loaded directly from the main bundle rather than `Image(_:)`/`NSImage(named:)`,
/// which target asset-catalog entries.
private let reactotronLogoImage: NSImage = {
  if let url = Bundle.main.url(forResource: "Reactotron-128", withExtension: "png"),
    let image = NSImage(contentsOf: url) {
    return image
  }
  return NSImage()
}()

/// Port of `SideBar/Sidebar.tsx` + `SideBarButton/Stateless.tsx`.
struct SideBar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        SideBarButton(image: true, text: "Home", isActive: model.currentPage == .home, hideTopBar: true) {
          model.currentPage = .home
        }
        SideBarButton(icon: .mdReorder, text: "Timeline", isActive: model.currentPage == .timeline) {
          model.currentPage = .timeline
        }
        SideBarButton(
          icon: .mdAssignment, text: "State",
          isActive: model.currentPage == .stateSubscriptions || model.currentPage == .stateSnapshots
        ) {
          model.currentPage = .stateSubscriptions
        }
        SideBarButton(
          icon: .mdPhoneIphone, text: "React Native",
          isActive: model.currentPage == .nativeOverlay || model.currentPage == .nativeStorybook
        ) {
          model.currentPage = .nativeOverlay
        }
        SideBarButton(
          icon: .faMagic, iconSize: 25, text: "Custom Commands",
          isActive: model.currentPage == .customCommands
        ) {
          model.currentPage = .customCommands
        }

        Spacer(minLength: 0)

        serverStatusButton

        SideBarButton(icon: .mdLiveHelp, text: "Help", isActive: model.currentPage == .help, hideTopBar: true) {
          model.currentPage = .help
        }
      }
      .padding(.top, 25)
      .frame(width: 115, alignment: .top)
      .background(Theme.backgroundSubtleDark)
      .overlay(alignment: .trailing) {
        Rectangle().fill(Theme.chromeLine).frame(width: 1)
      }
    }
    .frame(width: model.sidebarVisible ? 115 : 0, alignment: .leading)
    .clipped()
    .animation(.easeOut(duration: 0.2), value: model.sidebarVisible)
  }

  @ViewBuilder private var serverStatusButton: some View {
    switch model.session.serverStatus {
    case .started:
      SideBarButton(icon: .mdOutlineMobileFriendly, text: "Running", isActive: false) {}
    case .stopped:
      SideBarButton(icon: .mdMobiledataOff, text: "Stopped", isActive: false) {}
    case .portUnavailable:
      SideBarButton(
        icon: .mdWarning, iconColor: .yellow,
        text: "Port \(model.settings.serverPort) unavailable", isActive: false
      ) {
        model.startServer()
      }
    }
  }
}

/// Port of `SideBarButton/Stateless.tsx`: vertical icon/image + label, with the
/// icon/label color springing between `Theme.highlight` (inactive) and
/// `Theme.foregroundLight` (active) — approximated here as a direct switch
/// with an eased animation rather than react-motion's spring.
private struct SideBarButton: View {
  var icon: IconName?
  var image = false
  var iconSize: CGFloat = 32
  var iconColor: Color?
  var text: String
  var isActive: Bool
  var hideTopBar = false
  var action: () -> Void = {}

  @State private var hovering = false

  private var animatedColor: Color { isActive ? Theme.foregroundLight : Theme.highlight }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        if let icon {
          Icon(icon, size: iconSize, color: iconColor ?? animatedColor)
            .padding(.bottom, 4)
        }
        if image {
          Image(nsImage: reactotronLogoImage)
            .resizable()
            .frame(width: 32, height: 32)
            .saturation(isActive ? 1 : 0)
            .brightness(isActive ? 0 : -0.3)
            .padding(.bottom, 4)
        }
        Text(text)
          .font(Theme.font(12))
          .foregroundStyle(animatedColor)
          .multilineTextAlignment(.center)
      }
      .padding(.vertical, 15)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .top) {
        if !hideTopBar {
          Rectangle().fill(Theme.line).frame(height: 1)
        }
      }
      .background(hovering ? Color.white.opacity(0.04) : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 10)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.2), value: isActive)
  }
}
