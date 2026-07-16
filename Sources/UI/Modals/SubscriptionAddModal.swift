import SwiftUI

/// Port of `reactotron-core-ui`'s `modals/SubscriptionAddModal`. Submits on
/// Enter — matching the source's `onKeyPress` handler — and leaves closing
/// to the caller (`onSubscribe`), same as `RootModals.tsx`'s
/// `onAddSubscription={(path) => { closeSubscriptionModal(); addSubscription(path) }}`.
struct SubscriptionAddModal: View {
  let onClose: () -> Void
  let onSubscribe: (String) -> Void

  @State private var path = ""
  @FocusState private var focused: Bool

  var body: some View {
    ModalChrome(title: "Add Subscription", onClose: onClose) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Enter a path you would like to subscribe. Here are some examples to get you started:")
          .font(Theme.font())
          .foregroundStyle(Theme.foreground)

        VStack(alignment: .leading, spacing: 0) {
          Text("user.firstName")
          Text("repo")
          Text("repo.*")
        }
        .font(Theme.font())
        .foregroundStyle(Theme.bold)
        .padding(.leading, 40)

        VStack(alignment: .leading, spacing: 0) {
          Text("PATH")
            .font(Theme.font(13))
            .foregroundStyle(Theme.heading)

          TextField("", text: $path)
            .textFieldStyle(.plain)
            .font(Theme.font(25))
            .foregroundStyle(Theme.foregroundLight)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
              Rectangle().fill(Theme.line).frame(height: 1)
            }
            .focused($focused)
            .onSubmit(handleSubmit)
        }
        .padding(.top, 15)
      }
    } additionalKeystrokes: {
      KeystrokeContainer {
        Keystroke("ENTER")
        Text("Subscribe")
          .font(Theme.font(13))
          .foregroundStyle(Theme.foreground)
      }
    }
    .onAppear { focused = true }
  }

  private func handleSubmit() {
    onSubscribe(path)
    path = ""
  }
}
