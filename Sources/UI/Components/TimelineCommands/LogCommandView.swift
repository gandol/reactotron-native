import SwiftUI

/// Port of `LogCommand/index.tsx`.
///
/// Scope note: source's `useFileSource` reads the crash site's source file
/// off local disk via Electron IPC and shows a clickable inline code preview
/// that opens the file in an editor (`sendCommand("editor.open", ...)`).
/// That's Electron/Node file-system access with no equivalent wired up in
/// this codebase yet — skipped. Message rendering + the stack-trace table
/// (function/file/line, dimmed for node_modules frames) are ported, which
/// covers the brief's "same + stack rendering" requirement.
struct LogCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let message = obj?["message"]
    // `"stack" in payload` in source — true if the key is present at all,
    // even if its value isn't a proper frame array (a raw `Error.stack`
    // string is a valid `LogPayload.stack` per reactotron-core-contract).
    let hasStackKey = obj?["stack"] != nil

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      titleColor: model.titleColor,
      important: command.important,
      toolbar: [
        TimelineToolbarAction(icon: .mdContentCopy, tip: "Copy text to clipboard") {
          copyLog(message: message, stackValue: obj?["stack"], hasStackKey: hasStackKey, level: obj?["level"]?.stringValue)
        }
      ]
    ) {
      VStack(alignment: .leading, spacing: 10) {
        if hasStackKey {
          errorMessageBox(message)
          // Resolved inside the expand closure, once per expansion: a large
          // `stack` is a lazy `.raw` subtree, and neither collapsed rows nor
          // redraws of an open one may parse it again.
          MaterializedView(value: obj?["stack"] ?? .null) { stack in
            let stackFrames = stack.arrayValue ?? []
            if !stackFrames.isEmpty {
              stackTable(stackFrames)
            }
          }
        } else {
          messageBody(message)
        }
      }
    }
  }

  // MARK: - Non-error message body (ContentView port: JSON-aware string, else tree)

  @ViewBuilder
  private func messageBody(_ message: JSONValue?) -> some View {
    if let message, !message.isNull {
      if case .string(let s) = message {
        let parsed = jsonAwareValue(message)
        if case .string = parsed {
          Text(s)
            .font(Theme.font(12))
            .foregroundStyle(Theme.foreground)
            .textSelection(.enabled)
        } else {
          TreeView(value: parsed)
        }
      } else {
        TreeView(value: message)
      }
    } else {
      Text("null").font(Theme.font(12)).foregroundStyle(Theme.tag)
    }
  }

  // MARK: - Error message + stack

  private func errorMessageBox(_ message: JSONValue?) -> some View {
    Text(message?.stringValue ?? message.flatMap { $0.encodedString() } ?? "")
      .font(Theme.font(12))
      .foregroundStyle(Theme.tag)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.backgroundDarker)
      .overlay(Rectangle().stroke(Theme.subtleLine, lineWidth: 1))
      .textSelection(.enabled)
  }

  private func stackTable(_ stack: [JSONValue]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Stack Trace")
        .font(Theme.font(12))
        .foregroundStyle(Theme.tag)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }

      HStack {
        Text("Function").frame(maxWidth: .infinity, alignment: .leading)
        Text("File").frame(maxWidth: .infinity, alignment: .leading)
        Text("Line").frame(width: 60, alignment: .trailing)
      }
      .font(Theme.font(11))
      .foregroundStyle(Theme.foregroundDark)

      ForEach(Array(stack.enumerated()), id: \.offset) { idx, frame in
        stackRow(frame, isSelected: idx == 0)
      }
    }
  }

  private func stackRow(_ frame: JSONValue, isSelected: Bool) -> some View {
    let fileName = frame["fileName"]?.stringValue ?? ""
    let functionName = frame["functionName"]?.stringValue
    let lineNumber = frame["lineNumber"]?.numberValue.map { Int($0) } ?? 0
    let isNodeModule = fileName.contains("/node_modules/")
    let justFile = fileName.split(separator: "/").last.map(String.init) ?? fileName

    return HStack {
      Text((functionName?.isEmpty == false) ? functionName! : "(anonymous function)")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(justFile.replacingOccurrences(of: "webpack://", with: ""))
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("\(lineNumber)").frame(width: 60, alignment: .trailing)
    }
    .font(Theme.font(11))
    .foregroundStyle(isSelected ? Theme.tag : Theme.foreground)
    .opacity(isNodeModule ? 0.4 : 1)
    .padding(.vertical, 4)
  }

  // MARK: - Toolbar copy

  private func copyLog(message: JSONValue?, stackValue: JSONValue?, hasStackKey: Bool, level: String?) {
    guard let message, message.isTruthy else { return }
    if level == "error", hasStackKey, let stackValue, stackValue.isTruthy {
      copyToClipboard(prettyJSON(.object(["message": message, "stack": stackValue])))
    } else if let s = message.stringValue {
      copyToClipboard(s)
    } else {
      copyToClipboard(prettyJSON(message))
    }
  }
}
