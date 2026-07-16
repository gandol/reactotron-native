import SwiftUI

// MARK: - SVG path parsing

/// Minimal scanner over an SVG path-data string ("d" attribute), tokenizing
/// command letters and the numbers/flags that follow them.
private struct SVGPathScanner {
  private let chars: [Character]
  private var idx = 0

  init(_ d: String) { chars = Array(d) }

  private mutating func skipSeparators() {
    while idx < chars.count, chars[idx] == " " || chars[idx] == "," || chars[idx] == "\n"
      || chars[idx] == "\t" || chars[idx] == "\r" {
      idx += 1
    }
  }

  private static let commandLetters = Set("MmLlHhVvCcSsQqTtAaZz")

  mutating func nextCommand() -> Character? {
    skipSeparators()
    guard idx < chars.count, Self.commandLetters.contains(chars[idx]) else { return nil }
    defer { idx += 1 }
    return chars[idx]
  }

  /// Whether more numeric parameters follow (vs. hitting the next command letter or EOF) —
  /// used to support the SVG shorthand where a command letter is implicitly repeated.
  mutating func peekIsNumberStart() -> Bool {
    skipSeparators()
    guard idx < chars.count else { return false }
    let c = chars[idx]
    return c.isNumber || c == "-" || c == "+" || c == "."
  }

  mutating func nextNumber() -> Double? {
    skipSeparators()
    guard idx < chars.count else { return nil }
    var j = idx
    if chars[j] == "+" || chars[j] == "-" { j += 1 }
    var sawDigitOrDot = false
    var sawDot = false
    while j < chars.count {
      let c = chars[j]
      if c.isNumber {
        sawDigitOrDot = true
        j += 1
      } else if c == "." && !sawDot {
        sawDot = true
        j += 1
      } else {
        break
      }
    }
    if j < chars.count, chars[j] == "e" || chars[j] == "E" {
      var k = j + 1
      if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
      var sawExpDigit = false
      while k < chars.count, chars[k].isNumber { sawExpDigit = true; k += 1 }
      if sawExpDigit { j = k }
    }
    guard sawDigitOrDot, j > idx else { return nil }
    defer { idx = j }
    return Double(String(chars[idx..<j]))
  }

  mutating func nextPair() -> (Double, Double)? {
    guard let x = nextNumber(), let y = nextNumber() else { return nil }
    return (x, y)
  }

  /// Arc flags are single 0/1 digits and may be packed with no separator (e.g. "1 1 0 1 0 5 5").
  mutating func nextFlag() -> Bool? {
    skipSeparators()
    guard idx < chars.count, chars[idx] == "0" || chars[idx] == "1" else { return nil }
    defer { idx += 1 }
    return chars[idx] == "1"
  }
}

private func reflected(_ p: CGPoint, about c: CGPoint) -> CGPoint {
  CGPoint(x: 2 * c.x - p.x, y: 2 * c.y - p.y)
}

/// Converts one SVG elliptical-arc segment (endpoint parameterization, per the
/// SVG spec §F.6) into a run of cubic Bezier curves appended to `path`.
private func appendArc(
  to path: inout Path,
  from start: CGPoint,
  to end: CGPoint,
  rx rxIn: Double,
  ry ryIn: Double,
  xAxisRotationDeg: Double,
  largeArc: Bool,
  sweep: Bool
) {
  guard start != end else { return }
  var rx = abs(rxIn), ry = abs(ryIn)
  guard rx != 0, ry != 0 else {
    path.addLine(to: end)
    return
  }

  let phi = xAxisRotationDeg * .pi / 180
  let cosPhi = cos(phi), sinPhi = sin(phi)

  let dx2 = (start.x - end.x) / 2
  let dy2 = (start.y - end.y) / 2
  let x1p = cosPhi * dx2 + sinPhi * dy2
  let y1p = -sinPhi * dx2 + cosPhi * dy2

  let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
  if lambda > 1 {
    let s = lambda.squareRoot()
    rx *= s
    ry *= s
  }

  let sign: Double = (largeArc != sweep) ? 1 : -1
  let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
  let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
  let coef = den == 0 ? 0 : sign * max(0, num / den).squareRoot()
  let cxp = coef * (rx * y1p / ry)
  let cyp = coef * -(ry * x1p / rx)

  let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
  let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

  func vectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
    let dot = ux * vx + uy * vy
    let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
    var a = acos(min(1, max(-1, dot / len)))
    if ux * vy - uy * vx < 0 { a = -a }
    return a
  }

  let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
  let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry

  let theta1 = vectorAngle(1, 0, ux, uy)
  var dTheta = vectorAngle(ux, uy, vx, vy)
  if !sweep, dTheta > 0 { dTheta -= 2 * .pi }
  if sweep, dTheta < 0 { dTheta += 2 * .pi }

  let segments = max(1, Int((abs(dTheta) / (.pi / 2)).rounded(.up)))
  let delta = dTheta / Double(segments)
  let t = 4.0 / 3.0 * tan(delta / 4)

  var angle = theta1
  for _ in 0..<segments {
    let nextAngle = angle + delta
    let cosA = cos(angle), sinA = sin(angle)
    let cosAN = cos(nextAngle), sinAN = sin(nextAngle)

    let p1 = CGPoint(
      x: cx + rx * cosA * cosPhi - ry * sinA * sinPhi,
      y: cy + rx * cosA * sinPhi + ry * sinA * cosPhi
    )
    let p2 = CGPoint(
      x: cx + rx * cosAN * cosPhi - ry * sinAN * sinPhi,
      y: cy + rx * cosAN * sinPhi + ry * sinAN * cosPhi
    )

    let dx1 = -rx * sinA, dy1 = ry * cosA
    let dx2 = -rx * sinAN, dy2 = ry * cosAN
    let tan1 = CGPoint(x: dx1 * cosPhi - dy1 * sinPhi, y: dx1 * sinPhi + dy1 * cosPhi)
    let tan2 = CGPoint(x: dx2 * cosPhi - dy2 * sinPhi, y: dx2 * sinPhi + dy2 * cosPhi)

    let c1 = CGPoint(x: p1.x + t * tan1.x, y: p1.y + t * tan1.y)
    let c2 = CGPoint(x: p2.x - t * tan2.x, y: p2.y - t * tan2.y)

    path.addCurve(to: p2, control1: c1, control2: c2)
    angle = nextAngle
  }
}

extension Path {
  /// Parses SVG path-data (the `d` attribute) into a `Path`. Supports
  /// M m L l H h V v C c S s Q q T t A a Z z, matching every command used by
  /// the react-icons Material/FontAwesome glyphs ported into `IconName`.
  static func fromSVG(_ d: String) -> Path {
    var path = Path()
    var scanner = SVGPathScanner(d)
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var lastCubicControl: CGPoint?
    var lastQuadControl: CGPoint?

    func point(_ x: Double, _ y: Double, relative: Bool) -> CGPoint {
      relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    while let cmd = scanner.nextCommand() {
      let relative = cmd.isLowercase
      switch Character(cmd.uppercased()) {
      case "M":
        var first = true
        while scanner.peekIsNumberStart(), let (x, y) = scanner.nextPair() {
          let p = point(x, y, relative: relative)
          if first {
            path.move(to: p)
            subpathStart = p
            first = false
          } else {
            path.addLine(to: p)
          }
          current = p
          lastCubicControl = nil
          lastQuadControl = nil
        }
      case "L":
        while scanner.peekIsNumberStart(), let (x, y) = scanner.nextPair() {
          let p = point(x, y, relative: relative)
          path.addLine(to: p)
          current = p
          lastCubicControl = nil
          lastQuadControl = nil
        }
      case "H":
        while scanner.peekIsNumberStart(), let x = scanner.nextNumber() {
          let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
          path.addLine(to: p)
          current = p
          lastCubicControl = nil
          lastQuadControl = nil
        }
      case "V":
        while scanner.peekIsNumberStart(), let y = scanner.nextNumber() {
          let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
          path.addLine(to: p)
          current = p
          lastCubicControl = nil
          lastQuadControl = nil
        }
      case "C":
        while scanner.peekIsNumberStart(),
          let (x1, y1) = scanner.nextPair(),
          let (x2, y2) = scanner.nextPair(),
          let (x, y) = scanner.nextPair() {
          let c1 = point(x1, y1, relative: relative)
          let c2 = point(x2, y2, relative: relative)
          let end = point(x, y, relative: relative)
          path.addCurve(to: end, control1: c1, control2: c2)
          current = end
          lastCubicControl = c2
          lastQuadControl = nil
        }
      case "S":
        while scanner.peekIsNumberStart(),
          let (x2, y2) = scanner.nextPair(),
          let (x, y) = scanner.nextPair() {
          let c1 = lastCubicControl.map { reflected($0, about: current) } ?? current
          let c2 = point(x2, y2, relative: relative)
          let end = point(x, y, relative: relative)
          path.addCurve(to: end, control1: c1, control2: c2)
          current = end
          lastCubicControl = c2
          lastQuadControl = nil
        }
      case "Q":
        while scanner.peekIsNumberStart(),
          let (x1, y1) = scanner.nextPair(),
          let (x, y) = scanner.nextPair() {
          let c1 = point(x1, y1, relative: relative)
          let end = point(x, y, relative: relative)
          path.addQuadCurve(to: end, control: c1)
          current = end
          lastQuadControl = c1
          lastCubicControl = nil
        }
      case "T":
        while scanner.peekIsNumberStart(), let (x, y) = scanner.nextPair() {
          let c1 = lastQuadControl.map { reflected($0, about: current) } ?? current
          let end = point(x, y, relative: relative)
          path.addQuadCurve(to: end, control: c1)
          current = end
          lastQuadControl = c1
          lastCubicControl = nil
        }
      case "A":
        while scanner.peekIsNumberStart(),
          let rx = scanner.nextNumber(),
          let ry = scanner.nextNumber(),
          let xRotation = scanner.nextNumber(),
          let largeArc = scanner.nextFlag(),
          let sweep = scanner.nextFlag(),
          let (x, y) = scanner.nextPair() {
          let end = point(x, y, relative: relative)
          appendArc(
            to: &path, from: current, to: end, rx: rx, ry: ry,
            xAxisRotationDeg: xRotation, largeArc: largeArc, sweep: sweep
          )
          current = end
          lastCubicControl = nil
          lastQuadControl = nil
        }
      case "Z":
        path.closeSubpath()
        current = subpathStart
        lastCubicControl = nil
        lastQuadControl = nil
      default:
        break
      }
    }

    return path
  }
}

// MARK: - Icon catalog

/// One glyph's geometry: its viewBox size (react-icons Fa* glyphs carry
/// non-square viewBoxes, e.g. FaTimes is 352×512) and SVG path data. Multiple
/// filled subpaths in `path` are combined with the even-odd fill rule, which
/// is how the source glyphs express cut-out holes (e.g. the gear in MdSettings).
struct SVGIcon {
  let width: CGFloat
  let height: CGFloat
  let path: String
}

/// One case per icon ported from react-icons (unpkg react-icons@5.2.1),
/// extracted from the `md` and `fa` family bundles. Later tasks add more
/// cases here as they port additional views — same extraction method.
enum IconName: CaseIterable {
  case mdReorder
  case mdAssignment
  case mdPhoneIphone
  case mdLiveHelp
  case mdWarning
  case mdOutlineMobileFriendly
  case mdMobiledataOff
  case faMagic
  case mdSearch
  case mdFilterList
  case mdSwapVert
  case mdDeleteSweep
  case mdDownload
  case faTimes
  case mdKeyboardArrowUp
  case mdKeyboardArrowDown
  case mdSettings

  static let data: [IconName: SVGIcon] = [
    .mdReorder: SVGIcon(
      width: 24, height: 24,
      path: "M3 15h18v-2H3v2zm0 4h18v-2H3v2zm0-8h18V9H3v2zm0-6v2h18V5H3z"
    ),
    .mdAssignment: SVGIcon(
      width: 24, height: 24,
      path: "M19 3h-4.18C14.4 1.84 13.3 1 12 1c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm2 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"
    ),
    .mdPhoneIphone: SVGIcon(
      width: 24, height: 24,
      path: "M15.5 1h-8A2.5 2.5 0 0 0 5 3.5v17A2.5 2.5 0 0 0 7.5 23h8a2.5 2.5 0 0 0 2.5-2.5v-17A2.5 2.5 0 0 0 15.5 1zm-4 21c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm4.5-4H7V4h9v14z"
    ),
    .mdLiveHelp: SVGIcon(
      width: 24, height: 24,
      path: "M19 2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h4l3 3 3-3h4c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-6 16h-2v-2h2v2zm2.07-7.75-.9.92C13.45 11.9 13 12.5 13 14h-2v-.5c0-1.1.45-2.1 1.17-2.83l1.24-1.26c.37-.36.59-.86.59-1.41 0-1.1-.9-2-2-2s-2 .9-2 2H8c0-2.21 1.79-4 4-4s4 1.79 4 4c0 .88-.36 1.68-.93 2.25z"
    ),
    .mdWarning: SVGIcon(
      width: 24, height: 24,
      path: "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"
    ),
    .mdOutlineMobileFriendly: SVGIcon(
      width: 24, height: 24,
      path: "M19 1H9c-1.1 0-2 .9-2 2v3h2V4h10v16H9v-2H7v3c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-2-2-2zM7.01 13.47l-2.55-2.55-1.27 1.27L7 16l7.19-7.19-1.27-1.27-5.91 5.93z"
    ),
    .mdMobiledataOff: SVGIcon(
      width: 24, height: 24,
      path: "M16 7h3l-4-4-4 4h3v4.17l2 2zM2.81 2.81 1.39 4.22 8 10.83v6.18l-3 .01L9 21l4-4-3 .01v-4.18l9.78 9.78 1.41-1.42z"
    ),
    .faMagic: SVGIcon(
      width: 512, height: 512,
      path: "M224 96l16-32 32-16-32-16-16-32-16 32-32 16 32 16 16 32zM80 160l26.66-53.33L160 80l-53.34-26.67L80 0 53.34 53.33 0 80l53.34 26.67L80 160zm352 128l-26.66 53.33L352 368l53.34 26.67L432 448l26.66-53.33L512 368l-53.34-26.67L432 288zm70.62-193.77L417.77 9.38C411.53 3.12 403.34 0 395.15 0c-8.19 0-16.38 3.12-22.63 9.38L9.38 372.52c-12.5 12.5-12.5 32.76 0 45.25l84.85 84.85c6.25 6.25 14.44 9.37 22.62 9.37 8.19 0 16.38-3.12 22.63-9.37l363.14-363.15c12.5-12.48 12.5-32.75 0-45.24zM359.45 203.46l-50.91-50.91 86.6-86.6 50.91 50.91-86.6 86.6z"
    ),
    .mdSearch: SVGIcon(
      width: 24, height: 24,
      path: "M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"
    ),
    .mdFilterList: SVGIcon(
      width: 24, height: 24,
      path: "M10 18h4v-2h-4v2zM3 6v2h18V6H3zm3 7h12v-2H6v2z"
    ),
    .mdSwapVert: SVGIcon(
      width: 24, height: 24,
      path: "M16 17.01V10h-2v7.01h-3L15 21l4-3.99h-3zM9 3 5 6.99h3V14h2V6.99h3L9 3z"
    ),
    .mdDeleteSweep: SVGIcon(
      width: 24, height: 24,
      path: "M15 16h4v2h-4zm0-8h7v2h-7zm0 4h6v2h-6zM3 18c0 1.1.9 2 2 2h6c1.1 0 2-.9 2-2V8H3v10zM14 5h-3l-1-1H6L5 5H2v2h12z"
    ),
    .mdDownload: SVGIcon(
      width: 24, height: 24,
      path: "M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z"
    ),
    .faTimes: SVGIcon(
      width: 352, height: 512,
      path: "M242.72 256l100.07-100.07c12.28-12.28 12.28-32.19 0-44.48l-22.24-22.24c-12.28-12.28-32.19-12.28-44.48 0L176 189.28 75.93 89.21c-12.28-12.28-32.19-12.28-44.48 0L9.21 111.45c-12.28 12.28-12.28 32.19 0 44.48L109.28 256 9.21 356.07c-12.28 12.28-12.28 32.19 0 44.48l22.24 22.24c12.28 12.28 32.2 12.28 44.48 0L176 322.72l100.07 100.07c12.28 12.28 32.2 12.28 44.48 0l22.24-22.24c12.28-12.28 12.28-32.19 0-44.48L242.72 256z"
    ),
    .mdKeyboardArrowUp: SVGIcon(
      width: 24, height: 24,
      path: "M7.41 15.41 12 10.83l4.59 4.58L18 14l-6-6-6 6z"
    ),
    .mdKeyboardArrowDown: SVGIcon(
      width: 24, height: 24,
      path: "M7.41 8.59 12 13.17l4.59-4.58L18 10l-6 6-6-6 1.41-1.41z"
    ),
    .mdSettings: SVGIcon(
      width: 24, height: 24,
      path: "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.488.488 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"
    ),
  ]
}

// MARK: - Icon view

/// Renders an `IconName`'s SVG path data at `size`×`size`, aspect-fit (matching
/// the SVG default `preserveAspectRatio="xMidYMid meet"`) so non-square
/// FontAwesome glyphs (e.g. FaTimes) aren't stretched.
struct Icon: View {
  let name: IconName
  var size: CGFloat
  var color: Color

  init(_ name: IconName, size: CGFloat = 32, color: Color = Theme.foregroundLight) {
    self.name = name
    self.size = size
    self.color = color
  }

  private var icon: SVGIcon { IconName.data[name]! }

  var body: some View {
    let scale = min(size / icon.width, size / icon.height)
    Path.fromSVG(icon.path)
      .fill(color, style: FillStyle(eoFill: true))
      .transformEffect(CGAffineTransform(scaleX: scale, y: scale))
      .frame(width: icon.width * scale, height: icon.height * scale)
      .frame(width: size, height: size)
  }
}
