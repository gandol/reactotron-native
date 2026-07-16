import SwiftUI

@main
struct ReactotronApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .frame(minWidth: 900, minHeight: 600)
        .environment(model)
    }
  }
}
