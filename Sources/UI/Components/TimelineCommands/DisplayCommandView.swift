import SwiftUI

/// Port of `DisplayCommand/index.tsx`. `payload.image` can be a plain URI
/// string or `{ uri: string }` — both handled by `displayImageURL`. Uses
/// SwiftUI's built-in `AsyncImage`, which natively covers this task's
/// "handles invalid URL / loading / error states" safety requirement via its
/// `AsyncImagePhase` cases.
struct DisplayCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let value = obj?["value"]
    let imageURLString = displayImageURL(obj?["image"])

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important,
      isTagged: true,
      toolbar: [
        TimelineToolbarAction(icon: .mdContentCopy, tip: "Copy text to clipboard") {
          copyValue(value)
        }
      ]
    ) {
      VStack(alignment: .leading, spacing: 10) {
        if let value, value.isTruthy {
          TreeView(value: jsonAwareValue(value))
        }
        if let imageURLString, let url = URL(string: imageURLString) {
          AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
              image.resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 300)
            case .failure:
              Text("Failed to load image").font(Theme.font(12)).foregroundStyle(Theme.tag)
            case .empty:
              ProgressView().frame(height: 60)
            @unknown default:
              EmptyView()
            }
          }
        }
      }
    }
  }

  private func displayImageURL(_ image: JSONValue?) -> String? {
    guard let image, image.isTruthy else { return nil }
    if let s = image.stringValue { return s }
    return image["uri"]?.stringValue
  }

  private func copyValue(_ value: JSONValue?) {
    guard let value, value.isTruthy else { return }
    if let s = value.stringValue {
      copyToClipboard(s)
    } else {
      copyToClipboard(prettyJSON(value))
    }
  }
}
