import SwiftUI

/// Displays a `Date` formatted as `HH:mm:ss.SSS` in monospace.
/// Port of `reactotron-core-ui`'s `Timestamp` component.
struct Timestamp: View {
  let date: Date

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
  }()

  var body: some View {
    Text(Self.formatter.string(from: date))
      .font(.system(.body, design: .monospaced))
      .foregroundStyle(Theme.foregroundDark)
  }
}
