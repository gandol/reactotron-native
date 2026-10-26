import SwiftUI

/// A header action button shown in a `PageHeader`.
typealias HeaderAction = (icon: IconName, tip: String, onTap: () -> Void)

/// A tab definition for the tab-row variant of `PageHeader`.
typealias HeaderTab = (text: String, icon: IconName, isActive: Bool, onTap: () -> Void)

// MARK: - PageHeader

/// Page header bar with two layout variants:
/// - **Title + actions**: a title string centered in the header (matching React
///   Header's MiddleContainer), icon buttons right-aligned.
/// - **Tabs + actions**: a row of selectable tabs (icon + label) on the left,
///   icon buttons on the right.
///
/// Port of `reactotron-core-ui`'s `Header` + `HeaderTabButton`.
/// The React Header uses a 3-column flex layout (LeftContainer/MiddleContainer/
/// RightContainer) where the middle column is centered via `justify-content:
/// center`. This is replicated with a ZStack overlay so the title floats
/// centered independently of left/right content widths, while tabs and actions
/// remain left/right respectively.
struct PageHeader: View {

  let title: String?
  let tabs: [HeaderTab]?
  let isDraggable: Bool
  let actions: [HeaderAction]

  init(title: String, isDraggable: Bool = true, actions: [HeaderAction] = []) {
    self.title = title
    self.tabs = nil
    self.isDraggable = isDraggable
    self.actions = actions
  }

  init(tabs: [HeaderTab], isDraggable: Bool = true, actions: [HeaderAction] = []) {
    self.title = nil
    self.tabs = tabs
    self.isDraggable = isDraggable
    self.actions = actions
  }

  var body: some View {
    ZStack(alignment: .center) {
      // Background row: tabs on the left, actions on the right
      HStack(spacing: 0) {
        if let tabs, !tabs.isEmpty {
          HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
              tabButton(tab)
            }
          }
          .padding(.leading, 10)
        } else {
          Spacer() // balance the actions side when no tabs
        }

        Spacer(minLength: 0)

        HStack(spacing: 0) {
          ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
            Button {
              action.onTap()
            } label: {
              // Padding + contentShape widens the hit area past the 18pt glyph
              // without changing the visual spacing (4+4 = the old 8pt gap).
              Icon(action.icon, size: 18, color: Theme.foregroundLight)
                .padding(.horizontal, 4)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .help(action.tip)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.trailing, 16)
      }
      .frame(height: 70)

      // Centered title overlay — does not intercept clicks (allowsHitTesting false)
      if let title {
        Text(title)
          .font(Theme.font())
          .foregroundStyle(Theme.foregroundLight)
          .allowsHitTesting(false)
      }
    }
    .frame(height: 70)
    .background(Theme.backgroundSubtleLight)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Theme.chromeLine).frame(height: 1)
    }
    .shadow(color: Theme.glow, radius: 15, y: 2)
  }

  // MARK: Tab button

  private func tabButton(_ tab: HeaderTab) -> some View {
    Button {
      tab.onTap()
    } label: {
      VStack(spacing: 2) {
        Icon(tab.icon, size: 32, color: tab.isActive ? Theme.highlight : Theme.foregroundLight)
        Text(tab.text)
          .font(Theme.font(12))
          .foregroundStyle(tab.isActive ? Theme.highlight : Theme.foregroundLight)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 15)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
