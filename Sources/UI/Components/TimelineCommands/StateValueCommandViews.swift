import SwiftUI

// MARK: - state.values.change

/// Port of `StateValuesChangeCommand/index.tsx`. `buildTimelineCommand(...,
/// true)` in source — this row starts expanded.
struct StateValuesChangeCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important,
      startOpen: true
    ) {
      VStack(alignment: .leading, spacing: 10) {
        if let changed = presentObject(obj?["changed"]) {
          TreeView(value: .object(["changed": .object(changed)]))
        }
        if let added = presentObject(obj?["added"]) {
          TreeView(value: .object(["+ added": .object(added)]))
        }
        if let removed = presentObject(obj?["removed"]) {
          TreeView(value: .object(["- removed": .object(removed)]))
        }
      }
    }
  }

  /// `hasX = !!payload.x && !Array.isArray(payload.x)` from source, gated to
  /// only real objects (the only shape with anything meaningful to show).
  private func presentObject(_ v: JSONValue?) -> JSONObject? {
    v?.objectValue
  }
}

// MARK: - state.values.response

/// Port of `StateValuesResponseCommand/index.tsx`. Starts expanded
/// (`buildTimelineCommand(..., true)`).
struct StateValuesResponseCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let path = command.payload["path"]?.stringValue
    let value = command.payload["value"]

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important,
      startOpen: true
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text((path?.isEmpty == false) ? path! : "(root)")
          .font(Theme.font(12))
          .foregroundStyle(Theme.bold)
        if let value {
          TreeView(value: value)
        }
      }
    }
  }
}

// MARK: - state.keys.response

/// Port of `StateKeysResponseCommand/index.tsx`. Starts expanded
/// (`buildTimelineCommand(..., true)`). Key pills are clickable — tapping one
/// sends `state.values.request` for `path.key`, matching source's
/// `buildClickHandler`.
///
/// Source lays the pills out with CSS `flex-wrap: wrap`; this port uses a
/// horizontally-scrolling row instead (the same simplification already used
/// for the connection chips in `Footer.swift`) rather than a hand-rolled
/// `Layout` conformance for a purely cosmetic wrap behavior.
struct StateKeysResponseCommandView: View {
  let command: Command
  @Environment(AppModel.self) private var model

  var body: some View {
    let rowModel = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let path = obj?["path"]?.stringValue
    let keys = obj?["keys"]?.arrayValue

    BaseCommandView(
      title: rowModel.title,
      date: command.date,
      preview: rowModel.preview,
      important: command.important,
      startOpen: true
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text((path?.isEmpty == false) ? path! : "(root)")
          .font(Theme.font(12))
          .foregroundStyle(Theme.bold)
        keysView(keys: keys, path: path)
      }
    }
  }

  @ViewBuilder
  private func keysView(keys: [JSONValue]?, path: String?) -> some View {
    if let keys {
      if keys.isEmpty {
        Text("Sorry, no keys in there.").font(Theme.font(12)).foregroundStyle(Theme.foreground)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, keyValue in
              if let key = keyValue.stringValue {
                keyPill(key, path: path)
              }
            }
          }
        }
      }
    } else {
      Text("¯\\_(ツ)_/¯").font(Theme.font(12)).foregroundStyle(Theme.foreground)
    }
  }

  private func keyPill(_ key: String, path: String?) -> some View {
    Button {
      let fullPath = (path?.isEmpty == false) ? "\(path!).\(key)" : key
      model.sendCommand(type: "state.values.request", payload: .object(["path": .string(fullPath)]))
    } label: {
      Text(key)
        .font(Theme.font(12))
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundLighter))
    }
    .buttonStyle(.plain)
  }
}
