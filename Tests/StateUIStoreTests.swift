import XCTest
@testable import Reactotron

/// Verifies `StateUIStore.handle(command:)` against the exact wire shapes
/// confirmed in `reactotron-core-contract/src/state.ts`:
///   - `state.values.change` payload: `{ changes: [{ path, value }] }`
///   - `state.backup.response` payload: `{ name?, state }`
@MainActor
final class StateUIStoreTests: XCTestCase {
  private func cmd(_ type: String, payload: JSONValue) -> Command {
    Command(
      type: type, connectionId: 1, messageId: 1, date: Date(),
      deltaTime: 0, important: false, payload: payload, clientId: "a", diff: nil
    )
  }

  // MARK: - state.values.change

  func testValuesChangeUpdatesSubscriptionPairs() {
    let store = StateUIStore()
    let payload: JSONValue = .object([
      "changes": .array([
        .object(["path": .string("user.name"), "value": .string("Ada")]),
        .object(["path": .string("count"), "value": .number(3)]),
      ])
    ])

    store.handle(command: cmd("state.values.change", payload: payload))

    XCTAssertEqual(store.subscriptionValues.count, 2)
    XCTAssertEqual(store.subscriptionValues[0].path, "user.name")
    XCTAssertEqual(store.subscriptionValues[0].value, .string("Ada"))
    XCTAssertEqual(store.subscriptionValues[1].path, "count")
    XCTAssertEqual(store.subscriptionValues[1].value, .number(3))
  }

  /// Subscriptions.tsx's `getLatestChanges` takes only the newest
  /// `state.values.change` command's `changes` array — later commands
  /// *replace* the pairs, they don't merge into them.
  func testValuesChangeReplacesRatherThanMerges() {
    let store = StateUIStore()
    store.handle(command: cmd(
      "state.values.change",
      payload: .object(["changes": .array([.object(["path": .string("a"), "value": .number(1)])])])
    ))
    store.handle(command: cmd(
      "state.values.change",
      payload: .object(["changes": .array([.object(["path": .string("b"), "value": .number(2)])])])
    ))

    XCTAssertEqual(store.subscriptionValues.count, 1)
    XCTAssertEqual(store.subscriptionValues[0].path, "b")
  }

  func testValuesChangeWithMissingChangesIsEmpty() {
    let store = StateUIStore()
    store.handle(command: cmd("state.values.change", payload: .object([:])))
    XCTAssertTrue(store.subscriptionValues.isEmpty)
  }

  // MARK: - state.backup.response

  func testBackupResponseAppendsSnapshotWithDefaultNumberedName() {
    let store = StateUIStore()
    let payload: JSONValue = .object(["name": .null, "state": .object(["count": .number(1)])])

    store.handle(command: cmd("state.backup.response", payload: payload))
    XCTAssertEqual(store.snapshots.count, 1)
    XCTAssertEqual(store.snapshots[0].name, "Snapshot 1")
    XCTAssertEqual(store.snapshots[0].state, .object(["count": .number(1)]))

    store.handle(command: cmd("state.backup.response", payload: payload))
    XCTAssertEqual(store.snapshots.count, 2)
    XCTAssertEqual(store.snapshots[1].name, "Snapshot 2")
  }

  func testBackupResponseUsesProvidedName() {
    let store = StateUIStore()
    let payload: JSONValue = .object(["name": .string("My Snap"), "state": .object([:])])

    store.handle(command: cmd("state.backup.response", payload: payload))

    XCTAssertEqual(store.snapshots.count, 1)
    XCTAssertEqual(store.snapshots[0].name, "My Snap")
  }

  func testBackupResponseSnapshotsHaveDistinctIds() {
    let store = StateUIStore()
    let payload: JSONValue = .object(["state": .object([:])])
    store.handle(command: cmd("state.backup.response", payload: payload))
    store.handle(command: cmd("state.backup.response", payload: payload))
    XCTAssertNotEqual(store.snapshots[0].id, store.snapshots[1].id)
  }

  // MARK: - Rename / remove

  func testRenameSnapshotUpdatesName() {
    let store = StateUIStore()
    store.handle(command: cmd("state.backup.response", payload: .object(["state": .object([:])])))
    let snapshot = store.snapshots[0]

    store.renameSnapshot(snapshot, to: "Renamed")

    XCTAssertEqual(store.snapshots[0].name, "Renamed")
  }

  func testRemoveSnapshotDeletesIt() {
    let store = StateUIStore()
    store.handle(command: cmd("state.backup.response", payload: .object(["state": .object([:])])))
    let snapshot = store.snapshots[0]

    store.removeSnapshot(snapshot)

    XCTAssertTrue(store.snapshots.isEmpty)
  }

  // MARK: - Unrelated commands

  func testIgnoresUnrelatedCommandTypes() {
    let store = StateUIStore()
    store.handle(command: cmd("log", payload: .object([:])))
    XCTAssertTrue(store.subscriptionValues.isEmpty)
    XCTAssertTrue(store.snapshots.isEmpty)
  }
}
