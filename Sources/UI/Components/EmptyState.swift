import SwiftUI

/// Centered empty-state placeholder with icon, title, and body message.
/// Port of `reactotron-core-ui`'s `EmptyState`.
struct EmptyState<Content: View>: View {
  let icon: IconName
  let title: String
  @ViewBuilder let message: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      Icon(icon, size: 100, color: Theme.foregroundLight)
        .padding(.bottom, 4)

      Text(title)
        .font(Theme.font(32))
        .foregroundStyle(Theme.foregroundLight)
        .padding(.top, 10)
        .padding(.bottom, 50)

      message()
        .foregroundStyle(Theme.foreground)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
