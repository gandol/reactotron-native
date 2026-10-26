import SwiftUI

/// Port of `SagaTaskCompleteCommand/Stateless.tsx`.
///
/// Status icons (RESOLVED/REJECTED/CANCELLED — source's
/// `MdDone`/`MdError`/`MdEject`) are rendered as SF Symbols rather than
/// ported react-icons glyphs: they're a small decorative detail nested two
/// levels into the expanded body of a less-common command type. The
/// icons everyone sees on every row (toolbar/chrome) get exact react-icons
/// ports in `Icons.swift`; this keeps that porting effort proportionate to
/// visibility instead of gold-plating a rarely-opened detail view.
struct SagaTaskCompleteCommandView: View {
  let command: Command
  @State private var isDetailsOpen = false

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let duration = obj?["duration"]?.numberValue.map { Int($0) } ?? 0
    let triggerType = obj?["triggerType"]?.stringValue ?? ""
    let description = obj?["description"]?.stringValue

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important,
      toolbar: [
        TimelineToolbarAction(icon: .mdList, tip: "Toggle saga details") {
          isDetailsOpen.toggle()
        }
      ]
    ) {
      // Resolved inside the expand closure, once per expansion: a large
      // `children` array is a lazy `.raw` subtree, and neither collapsed rows
      // nor redraws of an open one may parse it again.
      MaterializedView(value: obj?["children"] ?? .null) { childrenValue in
        let children = childrenValue.arrayValue ?? []
        let effectWord = children.count == 1 ? "Effect" : "Effects"
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text((description?.isEmpty == false) ? description! : triggerType)
              .foregroundStyle(Theme.tag)
            Text("\(children.count) \(effectWord)")
              .foregroundStyle(Theme.foreground)
            Spacer()
            Text("\(duration)ms").foregroundStyle(Theme.foregroundDark)
          }
          .font(Theme.font(12))
          .padding(.bottom, 4)
          .overlay(alignment: .bottom) { Rectangle().fill(Theme.highlight).frame(height: 1) }

          ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            effectRow(child, isDetailsOpen: isDetailsOpen)
          }
        }
      }
    }
  }

  private func effectRow(_ effect: JSONValue, isDetailsOpen: Bool) -> some View {
    let depth = effect["depth"]?.numberValue.map { Int($0) } ?? 0
    let status = effect["status"]?.stringValue ?? ""
    let name = effect["name"]?.stringValue ?? ""
    let description = effect["description"]?.stringValue
    let duration = effect["duration"]?.numberValue.map { Int($0) } ?? 0
    let loser = effect["loser"]?.isTruthy ?? false
    let isLoser = loser || status == "CANCELLED"
    let hasExtra = effect["extra"]?.isTruthy ?? false

    return VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top) {
        HStack(spacing: 4) {
          statusIcon(status)
          Text(name)
            .strikethrough(isLoser)
            .foregroundStyle(isLoser ? Theme.foregroundDark : Theme.constant)
        }
        .padding(.leading, CGFloat(depth) * 20)
        .frame(width: 220, alignment: .leading)

        if hasExtra, let description, !description.isEmpty {
          Text(description)
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Spacer()
        }

        Text("\(duration)ms").foregroundStyle(Theme.foregroundDark)
      }

      if hasExtra, isDetailsOpen {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 2) {
            Text("in").font(Theme.font(10)).foregroundStyle(Theme.foregroundDark)
            TreeView(value: effect["extra"] ?? .null)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text("out").font(Theme.font(10)).foregroundStyle(Theme.foregroundDark)
            TreeView(value: effect["result"] ?? .null)
          }
        }
        .padding(.leading, CGFloat(depth) * 20 + 20)
      }
    }
    .font(Theme.font(12))
    .padding(.top, 4)
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.subtleLine).frame(height: 1) }
  }

  @ViewBuilder
  private func statusIcon(_ status: String) -> some View {
    switch status {
    case "RESOLVED":
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.tag).font(.system(size: 11))
    case "REJECTED":
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.tag).font(.system(size: 11))
    case "CANCELLED":
      Image(systemName: "eject.fill").foregroundStyle(Theme.tag).font(.system(size: 11))
    default:
      EmptyView()
    }
  }
}
