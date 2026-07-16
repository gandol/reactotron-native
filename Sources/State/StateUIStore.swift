import Foundation
import Observation

/// A captured snapshot of the connected client's redux/mobx-state-tree store.
///
/// Port of `reactotron-core-ui`'s `Snapshot` type (`{ id, name, state }`),
/// plus a `date` field (the receiving `Command`'s timestamp) that the source
/// doesn't carry but this port's row UI wants for a "captured at" display.
struct SnapshotItem: Identifiable, Equatable {
  let id: UUID
  var name: String
  let date: Date
  let state: JSONValue
}

/// Owns the two pieces of UI state `pages/state/Subscriptions.tsx` and
/// `Snapshots.tsx` read from `StateContext`/`ReactotronContext` in the source:
/// the latest `state.values.subscribe` values, and the accumulated snapshot
/// list built from `state.backup.response` commands.
///
/// Port notes (verified against `reactotron-core-contract/src/state.ts` and
/// `lib/reactotron-core-ui/src/contexts/State/use{Subscriptions,Snapshots}.ts`):
/// - `state.values.change` payload is `{ changes: [{ path, value }] }`.
///   `Subscriptions.tsx`'s `getLatestChanges` takes only the *newest* such
///   command's `changes` array — each new command **replaces**
///   `subscriptionValues` wholesale, it does not merge into the existing list.
/// - `state.backup.response` payload is `{ state }`; `useSnapshots.ts` also
///   reads an optional `payload.name`, falling back to a generated name when
///   absent (upstream uses a formatted timestamp — this port uses "Snapshot N"
///   per the task brief, see `task-12-report.md` for the rationale).
/// - Both handlers are routed here from `AppModel`'s global command pipeline
///   (every command from every connected client), matching how `useSnapshots`
///   itself subscribes via a global `addCommandListener` unscoped by selected
///   connection. `subscriptionValues`, by contrast, is scoped to the selected
///   connection in the source (`ReactotronContext.commands` is
///   `selectedConnection.commands`); this port keeps a single flat list
///   instead, per the interface this task specifies — see the report for the
///   multi-client caveat that implies.
@MainActor @Observable
final class StateUIStore {
  var subscriptionValues: [(path: String, value: JSONValue)] = []
  var snapshots: [SnapshotItem] = []

  private var snapshotCounter = 0

  func handle(command: Command) {
    switch command.type {
    case "state.values.change":
      let changes = command.payload["changes"]?.arrayValue ?? []
      subscriptionValues = changes.compactMap { change in
        guard let path = change["path"]?.stringValue else { return nil }
        return (path: path, value: change["value"] ?? .null)
      }

    case "state.backup.response":
      snapshotCounter += 1
      let name = command.payload["name"]?.stringValue ?? "Snapshot \(snapshotCounter)"
      let state = command.payload["state"] ?? .null
      snapshots.append(SnapshotItem(id: UUID(), name: name, date: command.date, state: state))

    default:
      break
    }
  }

  func renameSnapshot(_ snapshot: SnapshotItem, to name: String) {
    guard let idx = snapshots.firstIndex(where: { $0.id == snapshot.id }) else { return }
    snapshots[idx].name = name
  }

  func removeSnapshot(_ snapshot: SnapshotItem) {
    snapshots.removeAll { $0.id == snapshot.id }
  }
}
