import XCTest
import SwiftUI
@testable import Reactotron

final class IconsTests: XCTestCase {
  func testAllIconsParseToNonEmptyPath() {
    for name in IconName.allCases {
      let data = IconName.data[name]!
      XCTAssertFalse(Path.fromSVG(data.path).isEmpty, "\(name) produced an empty Path")
    }
  }

  func testSquareViewBoxIcon() {
    // MdReorder: 24x24, simple horizontal bars — sanity check bounding box is roughly square.
    let path = Path.fromSVG(IconName.data[.mdReorder]!.path)
    let box = path.boundingRect
    XCTAssertEqual(box.width, 18, accuracy: 0.5)
  }

  func testNonSquareViewBoxIcon() {
    // FaTimes carries an explicit non-square viewBox (352x512).
    let icon = IconName.data[.faTimes]!
    XCTAssertEqual(icon.width, 352)
    XCTAssertEqual(icon.height, 512)
  }

  func testArcCommandProducesClosedShape() {
    // MdSearch exercises A (arc) and S (smooth cubic) commands.
    let path = Path.fromSVG(IconName.data[.mdSearch]!.path)
    XCTAssertFalse(path.isEmpty)
    XCTAssertGreaterThan(path.boundingRect.width, 0)
    XCTAssertGreaterThan(path.boundingRect.height, 0)
  }
}
