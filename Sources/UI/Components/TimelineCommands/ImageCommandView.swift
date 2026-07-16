import SwiftUI

/// Port of `ImageCommand/index.tsx`. No toolbar in source. `AsyncImage`
/// covers invalid-URL/loading/error states natively (an empty or malformed
/// `uri` fails the `URL(string:)` init and falls straight to the "Invalid
/// image URI" text — never a crash).
struct ImageCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let uri = obj?["uri"]?.stringValue ?? ""
    let caption = obj?["caption"]?.stringValue
    let width = obj?["width"]?.numberValue
    let height = obj?["height"]?.numberValue
    let filename = obj?["filename"]?.stringValue
    let dimensions: String? = {
      guard let width, let height else { return nil }
      return "\(Int(width)) x \(Int(height))"
    }()

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important
    ) {
      VStack(alignment: .leading, spacing: 8) {
        if !uri.isEmpty, let url = URL(string: uri) {
          AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
              image.resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 400)
            case .failure:
              Text("Failed to load image").font(Theme.font(12)).foregroundStyle(Theme.tag)
            case .empty:
              ProgressView().frame(height: 80)
            @unknown default:
              EmptyView()
            }
          }
        } else {
          Text("Invalid image URI").font(Theme.font(12)).foregroundStyle(Theme.tag)
        }
        if let caption, !caption.isEmpty {
          Text(caption).font(Theme.font(16)).foregroundStyle(Theme.foreground)
        }
        if let dimensions {
          Text(dimensions).font(Theme.font(12)).foregroundStyle(Theme.constant)
        }
        if let filename, !filename.isEmpty {
          Text(filename).font(Theme.font(12)).foregroundStyle(Theme.highlight)
        }
      }
    }
  }
}
