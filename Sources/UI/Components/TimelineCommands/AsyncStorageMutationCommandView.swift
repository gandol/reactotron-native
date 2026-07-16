import SwiftUI

/// Port of `AsyncStorageMutationCommand/index.tsx`. No toolbar in source.
struct AsyncStorageMutationCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let action = obj?["action"]?.stringValue

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important
    ) {
      VStack(alignment: .leading, spacing: 6) {
        if let action, !action.isEmpty {
          HStack(spacing: 10) {
            Text("action")
              .foregroundStyle(Theme.foregroundDark)
              .frame(width: 150, alignment: .leading)
            Text(action)
              .foregroundStyle(Theme.foreground)
          }
          .font(Theme.font(12))
        }
        KeyValueTable(object: obj?["data"]?.objectValue ?? [:])
      }
    }
  }
}
