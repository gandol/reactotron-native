import SwiftUI

/// Port of `ClientIntroCommand/index.tsx`. Source has no toolbar and shows
/// the whole intro payload as a flat `makeTable`.
struct ClientIntroCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important
    ) {
      KeyValueTable(object: command.payload.objectValue ?? [:])
    }
  }
}
