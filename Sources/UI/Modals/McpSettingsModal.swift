import SwiftUI

/// Port of `apps/reactotron-app/src/renderer/components/McpSettingsModal`.
/// Editable tag lists for the redaction rules (sensitive keys, state path
/// patterns, value patterns) plus the two client-permission toggles. Every
/// edit persists to `SettingsStore` and pushes the new rules live into the
/// running `McpServer` (equivalent to Standalone's `updateMcpRedactionConfig`).
struct McpSettingsModal: View {
  @Environment(AppModel.self) private var model
  let onClose: () -> Void

  var body: some View {
    @Bindable var settings = model.settings

    ModalChrome(title: "MCP Redaction Settings", onClose: onClose) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Spacer()
          Button("Reset to defaults") { resetToDefaults() }
            .buttonStyle(.plain)
            .font(Theme.font(12))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.chromeLine))
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            section(
              title: "Sensitive Keys",
              description: "Field and HTTP header names redacted wherever found in payloads (case-insensitive)"
            ) {
              TagListEditor(
                placeholder: "Type key or header name and press Enter",
                values: settings.mcpRedactionSensitiveKeys
              ) { updated in
                model.updateMcpRules(
                  sensitiveKeys: updated,
                  statePathPatterns: model.settings.mcpRedactionStatePathPatterns,
                  valuePatterns: model.settings.mcpRedactionValuePatterns
                )
              }
            }

            section(
              title: "State Path Patterns",
              description: "Dot-separated paths to redact in state (supports trailing wildcard, e.g. auth.tokens.*)"
            ) {
              TagListEditor(
                placeholder: "Type state path and press Enter",
                values: settings.mcpRedactionStatePathPatterns
              ) { updated in
                model.updateMcpRules(
                  sensitiveKeys: model.settings.mcpRedactionSensitiveKeys,
                  statePathPatterns: updated,
                  valuePatterns: model.settings.mcpRedactionValuePatterns
                )
              }
            }

            section(
              title: "Value Patterns",
              description: "Regex patterns matched against string values"
            ) {
              TagListEditor(
                placeholder: "Type regex pattern and press Enter",
                values: settings.mcpRedactionValuePatterns
              ) { updated in
                model.updateMcpRules(
                  sensitiveKeys: model.settings.mcpRedactionSensitiveKeys,
                  statePathPatterns: model.settings.mcpRedactionStatePathPatterns,
                  valuePatterns: updated
                )
              }
            }

            section(title: "Client Permissions", description: nil) {
              VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow apps to disable redaction entirely", isOn: $settings.mcpAllowClientDisable)
                Toggle("Allow apps to remove default rules", isOn: $settings.mcpAllowClientRemoveRules)
              }
              .toggleStyle(.checkbox)
              .font(Theme.font(12))
              .foregroundStyle(Theme.foreground)
            }
          }
          .padding(.top, 12)
        }
        .frame(maxHeight: 440)
      }
    }
  }

  private func resetToDefaults() {
    model.updateMcpRules(
      sensitiveKeys: Redaction.defaultSensitiveKeys,
      statePathPatterns: Redaction.defaultStatePathPatterns,
      valuePatterns: Redaction.defaultValuePatterns
    )
    model.settings.mcpAllowClientDisable = false
    model.settings.mcpAllowClientRemoveRules = false
  }

  @ViewBuilder
  private func section<Content: View>(
    title: String, description: String?, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(Theme.font(14, weight: .semibold))
        .foregroundStyle(Theme.foreground)
      if let description {
        Text(description)
          .font(Theme.font(11))
          .foregroundStyle(Theme.foregroundDark)
      }
      content()
    }
  }
}

// MARK: - Tag list editor (port of the modal's TagListEditor)

private struct TagListEditor: View {
  let placeholder: String
  let values: [String]
  let onChange: ([String]) -> Void

  @State private var input = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !values.isEmpty {
        FlowLayout(spacing: 4) {
          ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            tag(value, index: index)
          }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundSubtleDark))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.chromeLine))
      }

      TextField(placeholder, text: $input)
        .textFieldStyle(.plain)
        .font(Theme.font(12))
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.backgroundSubtleDark))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.chromeLine))
        .onSubmit {
          let value = input.trimmingCharacters(in: .whitespaces)
          if !value.isEmpty, !values.contains(value) {
            onChange(values + [value])
          }
          input = ""
        }
    }
  }

  private func tag(_ value: String, index: Int) -> some View {
    HStack(spacing: 4) {
      Text(value)
        .font(Theme.font(11))
        .foregroundStyle(Theme.foreground)
      Button {
        onChange(values.enumerated().filter { $0.offset != index }.map(\.element))
      } label: {
        Text("×")
          .font(Theme.font(14))
          .foregroundStyle(Theme.foregroundDark)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.backgroundHighlight))
  }
}

// MARK: - Flow layout

/// Wrapping horizontal layout — the SwiftUI equivalent of the source's
/// `flex-wrap` tag container. macOS 14's `Layout` protocol.
private struct FlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var widest: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, x - spacing)
    }
    let width = maxWidth.isFinite ? maxWidth : widest
    return CGSize(width: width, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
