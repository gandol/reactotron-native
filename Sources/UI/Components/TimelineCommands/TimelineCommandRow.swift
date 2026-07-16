import SwiftUI

/// Port of `timelineCommands/index.ts`'s `timelineCommandResolver`, combined
/// with its caller in `pages/timeline/index.tsx`
/// (`if (CommandComponent) { return <CommandComponent .../> } return null`).
///
/// Only the 12 types the real resolver switches on render a row at all —
/// confirmed by reading `index.ts` in full, plus
/// `contexts/State/useSnapshots.ts` (`if (command.type !==
/// CommandType.StateBackupResponse) return`) and
/// `contexts/CustomCommands/useCustomCommands.ts`
/// (`command.type === CommandType.CustomCommandRegister`). Notably absent
/// from `timelineCommandResolver`'s switch: `state.backup.response`
/// (consumed by the Snapshots panel) and `customCommand.register`/
/// `unregister` (consumed by the Custom Commands panel) — neither ever
/// reaches the timeline in the reference app. This view renders nothing
/// (`EmptyView`) for those and for any other unrecognized type, matching
/// the resolver returning `null` + the caller returning `null`.
///
/// (This task's brief assumed unknown types should fall back to
/// `DisplayCommandView`; reading `index.ts` and its caller together showed
/// that isn't what the reference app actually does — see
/// `.superpowers/sdd/task-10-report.md` for the full list of brief-vs-source
/// mismatches found while porting.)
struct TimelineCommandRow: View {
  let command: Command

  var body: some View {
    switch command.type {
    case "client.intro":
      ClientIntroCommandView(command: command)
    case "log":
      LogCommandView(command: command)
    case "api.response":
      ApiResponseCommandView(command: command)
    case "state.action.complete":
      StateActionCompleteCommandView(command: command)
    case "state.values.change":
      StateValuesChangeCommandView(command: command)
    case "state.values.response":
      StateValuesResponseCommandView(command: command)
    case "state.keys.response":
      StateKeysResponseCommandView(command: command)
    case "asyncStorage.mutation":
      AsyncStorageMutationCommandView(command: command)
    case "saga.task.complete":
      SagaTaskCompleteCommandView(command: command)
    case "benchmark.report":
      BenchmarkReportCommandView(command: command)
    case "display":
      DisplayCommandView(command: command)
    case "image":
      ImageCommandView(command: command)
    default:
      EmptyView()
    }
  }
}
