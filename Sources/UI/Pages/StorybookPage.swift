import SwiftUI

/// Port of `pages/reactNative/Storybook.tsx`.
///
/// `isStorybookOn` is local view state (matching the source's `useStorybook()`
/// hook — a `useState` that only reflects the UI's own toggling, not a value
/// read back off the wire), so it resets when this page's identity resets
/// (e.g. navigating away and back), same lifetime tradeoff as `OverlayPage`.
///
/// `turnOnStorybook`/`turnOffStorybook` send `sendCommand("storybook", <bool>)`
/// — verified against `lib/reactotron-core-ui/src/contexts/ReactNative/
/// useStorybook.ts`: the payload is a bare boolean, not an object.
///
/// The storybook logo images (`storybook-logo.png` / `storybook-logo-color.png`)
/// aren't ported — no asset catalog/bundled-image equivalent exists for them in
/// this project yet, and the task brief doesn't call for adding one. `MdBook`
/// stands in for the logo, matching the tab icon used for this page elsewhere.
struct StorybookPage: View {
  @Environment(AppModel.self) private var model
  @State private var isStorybookOn = false

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(tabs: reactNativeHeaderTabs(model: model, active: .nativeStorybook))

      VStack(spacing: 0) {
        topSection
        warningBar
      }
    }
  }

  // MARK: - Top section (logo + on/off toggle)

  private var topSection: some View {
    VStack(spacing: 20) {
      Icon(.mdBook, size: 76, color: isStorybookOn ? Theme.highlight : Theme.foregroundLight)

      HStack(spacing: 0) {
        radioButton(title: "On", selected: isStorybookOn, onTap: turnOn)
        radioButton(title: "Off", selected: !isStorybookOn, onTap: turnOff)
      }
      .foregroundStyle(Theme.foreground)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func radioButton(title: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
    Button(action: onTap) {
      HStack(spacing: 4) {
        Icon(
          selected ? .mdRadioButtonChecked : .mdRadioButtonUnchecked,
          size: 32, color: Theme.foreground
        )
        Text(title).font(Theme.font())
      }
      .padding(10)
    }
    .buttonStyle(.plain)
  }

  private func turnOn() {
    isStorybookOn = true
    model.sendCommand(type: "storybook", payload: .bool(true))
  }

  private func turnOff() {
    isStorybookOn = false
    model.sendCommand(type: "storybook", payload: .bool(false))
  }

  // MARK: - Warning bar

  private var warningBar: some View {
    HStack(spacing: 20) {
      Icon(.mdWarning, size: 60, color: Theme.warning)
      Text("This is preview feature. It requires a specific setup of Storybook within React Native.")
        .font(Theme.font())
    }
    .foregroundStyle(Theme.warning)
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.backgroundDarker)
    .overlay(alignment: .top) {
      Rectangle().fill(Theme.chromeLine).frame(height: 1)
    }
  }
}
