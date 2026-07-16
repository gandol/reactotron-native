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
