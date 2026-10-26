import AppKit
import SwiftUI
import XCTest
@testable import Reactotron

/// Views that render a lazy `.raw` subtree parse it once per view lifetime
/// (`MaterializedJSON`), not on every redraw.
@MainActor
final class MaterializedViewTests: XCTestCase {
  private var materializeCount: Int { RawJSON.debugMaterializeCount.withLock { $0 } }

  private func raw(_ subtree: String) throws -> RawJSON {
    let frame = Data(#"{"type":"t","payload":{"v":\#(subtree)}}"#.utf8)
    guard case .raw(let r)? = JSONParser.parse(frame, lazy: LazyJSONPolicy(minBytes: 1))?["payload"]?["v"]
    else {
      XCTFail("payload.v is not raw")
      throw CancellationError()
    }
    return r
  }

  /// Hosts `view` in an offscreen window and lays it out (evaluates bodies).
  private func render<V: View>(_ view: V) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return host
  }

  /// A collapsed nested raw object node previews its keys from the node's
  /// cached parse; it used to parse the original `.raw` value a second time
  /// (and again on every redraw) for the preview.
  func testCollapsedRawObjectNodeParsesOnce() throws {
    let user = try raw(#"{"name":"alice","tags":["a","b"],"nested":{"x":1}}"#)
    let value: JSONValue = .object(["user": .raw(user), "small": .number(1)])
    let before = materializeCount
    let host = render(TreeView(value: value))
    XCTAssertEqual(materializeCount - before, 1, "root expanded, `user` collapsed: one parse")
    for _ in 0..<3 {
      host.rootView = TreeView(value: value)
      host.layoutSubtreeIfNeeded()
    }
    XCTAssertEqual(materializeCount - before, 1, "redraws reuse the node's cached parse")
  }

  /// `MaterializedView` (a log's `stack`, a saga's `children`) resolves its
  /// value once across redraws of the row that builds it.
  func testMaterializedViewParsesOnceAcrossRedraws() throws {
    let stack = try raw(#"[{"fileName":"a.js","lineNumber":1},{"fileName":"b.js","lineNumber":2}]"#)
    let before = materializeCount
    func view(_ label: String) -> some View {
      MaterializedView(value: .raw(stack)) { resolved in
        Text("\(label) \(resolved.arrayValue?.count ?? 0)")
      }
    }
    let host = render(view("first"))
    XCTAssertEqual(materializeCount - before, 1)
    for i in 0..<3 {
      host.rootView = view("redraw \(i)")
      host.layoutSubtreeIfNeeded()
    }
    XCTAssertEqual(materializeCount - before, 1)
  }
}
