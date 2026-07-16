import SwiftUI

/// Port of `reactotron-core-ui/src/modals/TimelineFilterModal` — a grouped grid
/// of checkboxes toggling membership of `AppModel.timeline.hiddenCommands`, plus
/// "Check all" / "Uncheck all" bulk actions. Group names, membership, and order
/// are copied verbatim from the source's `GROUPS` constant.
struct TimelineFilterModal: View {
  @Environment(AppModel.self) private var model
  let onClose: () -> Void

  private struct FilterGroup {
    let name: String
    let items: [(value: String, text: String)]
  }

  /// Verbatim port of `TimelineFilterModal/index.tsx`'s `GROUPS`, with
  /// `CommandType` enum members resolved to their string values (see
  /// `reactotron-core-contract/src/command.ts`).
  private static let groups: [FilterGroup] = [
    FilterGroup(
      name: "Informational",
      items: [
        (value: "log", text: "Log"),
        (value: "image", text: "Image"),
        (value: "display", text: "Custom Display"),
      ]
    ),
    FilterGroup(
      name: "General",
      items: [
        (value: "client.intro", text: "Connection"),
        (value: "benchmark.report", text: "Benchmark"),
        (value: "api.response", text: "API"),
      ]
    ),
    FilterGroup(
      name: "Async Storage",
      items: [
        (value: "asyncStorage.mutation", text: "Mutations")
      ]
    ),
    FilterGroup(
      name: "State & Sagas",
      items: [
        (value: "state.action.complete", text: "Action"),
        (value: "saga.task.complete", text: "Saga"),
        (value: "state.values.change", text: "Subscription Changed"),
      ]
    ),
  ]

  private static let allValues: Set<String> = Set(groups.flatMap { $0.items.map(\.value) })

  var body: some View {
    ModalChrome(title: "Timeline Filter", onClose: onClose) {
      VStack(alignment: .leading, spacing: 0) {
        bulkActions
          .padding(.bottom, 20)

        ForEach(Self.groups, id: \.name) { group in
          groupSection(group)
        }
      }
    }
  }

  // MARK: - Bulk actions ("Check all" / "Uncheck all")

  private var bulkActions: some View {
    HStack(spacing: 4) {
      Button {
        // To turn everything on we need the hidden set to be empty.
        model.timeline.hiddenCommands = []
      } label: {
        Text("Check all").foregroundStyle(Theme.tag)
      }
      .buttonStyle(.plain)

      Text("/").foregroundStyle(Theme.foreground)

      Button {
        // To turn everything off we need the hidden set to contain every option.
        model.timeline.hiddenCommands = Self.allValues
      } label: {
        Text("Uncheck all").foregroundStyle(Theme.tag)
      }
      .buttonStyle(.plain)
    }
    .font(Theme.font())
  }

  // MARK: - Group section

  private func groupSection(_ group: FilterGroup) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(group.name)
        .font(Theme.font(18))
        .foregroundStyle(Theme.foregroundLight)
        .padding(.vertical, 10)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
          Rectangle().fill(Theme.highlight).frame(height: 1)
        }

      ForEach(group.items, id: \.value) { item in
        checkboxRow(value: item.value, label: item.text)
      }
    }
  }

  // MARK: - Checkbox row (port of `components/Checkbox`)

  private func checkboxRow(value: String, label: String) -> some View {
    let isChecked = !model.timeline.hiddenCommands.contains(value)

    return Button {
      if isChecked {
        model.timeline.hiddenCommands.insert(value)
      } else {
        model.timeline.hiddenCommands.remove(value)
      }
    } label: {
      HStack(spacing: 10) {
        Icon(isChecked ? .mdCheckBox : .mdCheckBoxOutlineBlank, size: 18, color: Theme.tag)
        Text(label)
          .font(Theme.font())
          .foregroundStyle(Theme.tag)
      }
      .padding(.vertical, 5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
