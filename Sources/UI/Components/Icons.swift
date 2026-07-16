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
  // Added in Task 8 for `home/index.tsx`'s per-platform connection icon (`connectionHelpers.ts`'s `getIcon`).
  case faApple
  case faAndroid
  case faFirefox
  case faSafari
  case faEdge
  case faChrome
  case faQuestion

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
    // Added in Task 8 — react-icons `fa` family, used by `home/index.tsx`'s per-platform connection icon.
    .faApple: SVGIcon(
      width: 384, height: 512,
      path: "M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"
    ),
    .faAndroid: SVGIcon(
      width: 576, height: 512,
      path: "M420.55,301.93a24,24,0,1,1,24-24,24,24,0,0,1-24,24m-265.1,0a24,24,0,1,1,24-24,24,24,0,0,1-24,24m273.7-144.48,47.94-83a10,10,0,1,0-17.27-10h0l-48.54,84.07a301.25,301.25,0,0,0-246.56,0L116.18,64.45a10,10,0,1,0-17.27,10h0l47.94,83C64.53,202.22,8.24,285.55,0,384H576c-8.24-98.45-64.54-181.78-146.85-226.55"
    ),
    .faFirefox: SVGIcon(
      width: 512, height: 512,
      path: "M503.52,241.48c-.12-1.56-.24-3.12-.24-4.68v-.12l-.36-4.68v-.12a245.86,245.86,0,0,0-7.32-41.15c0-.12,0-.12-.12-.24l-1.08-4c-.12-.24-.12-.48-.24-.6-.36-1.2-.72-2.52-1.08-3.72-.12-.24-.12-.6-.24-.84-.36-1.2-.72-2.4-1.08-3.48-.12-.36-.24-.6-.36-1-.36-1.2-.72-2.28-1.2-3.48l-.36-1.08c-.36-1.08-.84-2.28-1.2-3.36a8.27,8.27,0,0,0-.36-1c-.48-1.08-.84-2.28-1.32-3.36-.12-.24-.24-.6-.36-.84-.48-1.2-1-2.28-1.44-3.48,0-.12-.12-.24-.12-.36-1.56-3.84-3.24-7.68-5-11.4l-.36-.72c-.48-1-.84-1.8-1.32-2.64-.24-.48-.48-1.08-.72-1.56-.36-.84-.84-1.56-1.2-2.4-.36-.6-.6-1.2-1-1.8s-.84-1.44-1.2-2.28c-.36-.6-.72-1.32-1.08-1.92s-.84-1.44-1.2-2.16a18.07,18.07,0,0,0-1.2-2c-.36-.72-.84-1.32-1.2-2s-.84-1.32-1.2-2-.84-1.32-1.2-1.92-.84-1.44-1.32-2.16a15.63,15.63,0,0,0-1.2-1.8L463.2,119a15.63,15.63,0,0,0-1.2-1.8c-.48-.72-1.08-1.56-1.56-2.28-.36-.48-.72-1.08-1.08-1.56l-1.8-2.52c-.36-.48-.6-.84-1-1.32-1-1.32-1.8-2.52-2.76-3.72a248.76,248.76,0,0,0-23.51-26.64A186.82,186.82,0,0,0,412,62.46c-4-3.48-8.16-6.72-12.48-9.84a162.49,162.49,0,0,0-24.6-15.12c-2.4-1.32-4.8-2.52-7.2-3.72a254,254,0,0,0-55.43-19.56c-1.92-.36-3.84-.84-5.64-1.2h-.12c-1-.12-1.8-.36-2.76-.48a236.35,236.35,0,0,0-38-4H255.14a234.62,234.62,0,0,0-45.48,5c-33.59,7.08-63.23,21.24-82.91,39-1.08,1-1.92,1.68-2.4,2.16l-.48.48H124l-.12.12.12-.12a.12.12,0,0,0,.12-.12l-.12.12a.42.42,0,0,1,.24-.12c14.64-8.76,34.92-16,49.44-19.56l5.88-1.44c.36-.12.84-.12,1.2-.24,1.68-.36,3.36-.72,5.16-1.08.24,0,.6-.12.84-.12C250.94,20.94,319.34,40.14,367,85.61a171.49,171.49,0,0,1,26.88,32.76c30.36,49.2,27.48,111.11,3.84,147.59-34.44,53-111.35,71.27-159,24.84a84.19,84.19,0,0,1-25.56-59,74.05,74.05,0,0,1,6.24-31c1.68-3.84,13.08-25.67,18.24-24.59-13.08-2.76-37.55,2.64-54.71,28.19-15.36,22.92-14.52,58.2-5,83.28a132.85,132.85,0,0,1-12.12-39.24c-12.24-82.55,43.31-153,94.31-170.51-27.48-24-96.47-22.31-147.71,15.36-29.88,22-51.23,53.16-62.51,90.36,1.68-20.88,9.6-52.08,25.8-83.88-17.16,8.88-39,37-49.8,62.88-15.6,37.43-21,82.19-16.08,124.79.36,3.24.72,6.36,1.08,9.6,19.92,117.11,122,206.38,244.78,206.38C392.77,503.42,504,392.19,504,255,503.88,250.48,503.76,245.92,503.52,241.48Z"
    ),
    .faSafari: SVGIcon(
      width: 512, height: 512,
      path: "M274.69,274.69l-37.38-37.38L166,346ZM256,8C119,8,8,119,8,256S119,504,256,504,504,393,504,256,393,8,256,8ZM411.85,182.79l14.78-6.13A8,8,0,0,1,437.08,181h0a8,8,0,0,1-4.33,10.46L418,197.57a8,8,0,0,1-10.45-4.33h0A8,8,0,0,1,411.85,182.79ZM314.43,94l6.12-14.78A8,8,0,0,1,331,74.92h0a8,8,0,0,1,4.33,10.45l-6.13,14.78a8,8,0,0,1-10.45,4.33h0A8,8,0,0,1,314.43,94ZM256,60h0a8,8,0,0,1,8,8V84a8,8,0,0,1-8,8h0a8,8,0,0,1-8-8V68A8,8,0,0,1,256,60ZM181,74.92a8,8,0,0,1,10.46,4.33L197.57,94a8,8,0,1,1-14.78,6.12l-6.13-14.78A8,8,0,0,1,181,74.92Zm-63.58,42.49h0a8,8,0,0,1,11.31,0L140,128.72A8,8,0,0,1,140,140h0a8,8,0,0,1-11.31,0l-11.31-11.31A8,8,0,0,1,117.41,117.41ZM60,256h0a8,8,0,0,1,8-8H84a8,8,0,0,1,8,8h0a8,8,0,0,1-8,8H68A8,8,0,0,1,60,256Zm40.15,73.21-14.78,6.13A8,8,0,0,1,74.92,331h0a8,8,0,0,1,4.33-10.46L94,314.43a8,8,0,0,1,10.45,4.33h0A8,8,0,0,1,100.15,329.21Zm4.33-136h0A8,8,0,0,1,94,197.57l-14.78-6.12A8,8,0,0,1,74.92,181h0a8,8,0,0,1,10.45-4.33l14.78,6.13A8,8,0,0,1,104.48,193.24ZM197.57,418l-6.12,14.78a8,8,0,0,1-14.79-6.12l6.13-14.78A8,8,0,1,1,197.57,418ZM264,444a8,8,0,0,1-8,8h0a8,8,0,0,1-8-8V428a8,8,0,0,1,8-8h0a8,8,0,0,1,8,8Zm67-6.92h0a8,8,0,0,1-10.46-4.33L314.43,418a8,8,0,0,1,4.33-10.45h0a8,8,0,0,1,10.45,4.33l6.13,14.78A8,8,0,0,1,331,437.08Zm63.58-42.49h0a8,8,0,0,1-11.31,0L372,383.28A8,8,0,0,1,372,372h0a8,8,0,0,1,11.31,0l11.31,11.31A8,8,0,0,1,394.59,394.59ZM286.25,286.25,110.34,401.66,225.75,225.75,401.66,110.34ZM437.08,331h0a8,8,0,0,1-10.45,4.33l-14.78-6.13a8,8,0,0,1-4.33-10.45h0A8,8,0,0,1,418,314.43l14.78,6.12A8,8,0,0,1,437.08,331ZM444,264H428a8,8,0,0,1-8-8h0a8,8,0,0,1,8-8h16a8,8,0,0,1,8,8h0A8,8,0,0,1,444,264Z"
    ),
    .faEdge: SVGIcon(
      width: 512, height: 512,
      path: "M481.92,134.48C440.87,54.18,352.26,8,255.91,8,137.05,8,37.51,91.68,13.47,203.66c26-46.49,86.22-79.14,149.46-79.14,79.27,0,121.09,48.93,122.25,50.18,22,23.8,33,50.39,33,83.1,0,10.4-5.31,25.82-15.11,38.57-1.57,2-6.39,4.84-6.39,11,0,5.06,3.29,9.92,9.14,14,27.86,19.37,80.37,16.81,80.51,16.81A115.39,115.39,0,0,0,444.94,322a118.92,118.92,0,0,0,58.95-102.44C504.39,176.13,488.39,147.26,481.92,134.48ZM212.77,475.67a154.88,154.88,0,0,1-46.64-45c-32.94-47.42-34.24-95.6-20.1-136A155.5,155.5,0,0,1,203,215.75c59-45.2,94.84-5.65,99.06-1a80,80,0,0,0-4.89-10.14c-9.24-15.93-24-36.41-56.56-53.51-33.72-17.69-70.59-18.59-77.64-18.59-38.71,0-77.9,13-107.53,35.69C35.68,183.3,12.77,208.72,8.6,243c-1.08,12.31-2.75,62.8,23,118.27a248,248,0,0,0,248.3,141.61C241.78,496.26,214.05,476.24,212.77,475.67Zm250.72-98.33a7.76,7.76,0,0,0-7.92-.23,181.66,181.66,0,0,1-20.41,9.12,197.54,197.54,0,0,1-69.55,12.52c-91.67,0-171.52-63.06-171.52-144A61.12,61.12,0,0,1,200.61,228,168.72,168.72,0,0,0,161.85,278c-14.92,29.37-33,88.13,13.33,151.66,6.51,8.91,23,30,56,47.67,23.57,12.65,49,19.61,71.7,19.61,35.14,0,115.43-33.44,163-108.87A7.75,7.75,0,0,0,463.49,377.34Z"
    ),
    .faChrome: SVGIcon(
      width: 496, height: 512,
      path: "M131.5 217.5L55.1 100.1c47.6-59.2 119-91.8 192-92.1 42.3-.3 85.5 10.5 124.8 33.2 43.4 25.2 76.4 61.4 97.4 103L264 133.4c-58.1-3.4-113.4 29.3-132.5 84.1zm32.9 38.5c0 46.2 37.4 83.6 83.6 83.6s83.6-37.4 83.6-83.6-37.4-83.6-83.6-83.6-83.6 37.3-83.6 83.6zm314.9-89.2L339.6 174c37.9 44.3 38.5 108.2 6.6 157.2L234.1 503.6c46.5 2.5 94.4-7.7 137.8-32.9 107.4-62 150.9-192 107.4-303.9zM133.7 303.6L40.4 120.1C14.9 159.1 0 205.9 0 256c0 124 90.8 226.7 209.5 244.9l63.7-124.8c-57.6 10.8-113.2-20.8-139.5-72.5z"
    ),
    .faQuestion: SVGIcon(
      width: 384, height: 512,
      path: "M202.021 0C122.202 0 70.503 32.703 29.914 91.026c-7.363 10.58-5.093 25.086 5.178 32.874l43.138 32.709c10.373 7.865 25.132 6.026 33.253-4.148 25.049-31.381 43.63-49.449 82.757-49.449 30.764 0 68.816 19.799 68.816 49.631 0 22.552-18.617 34.134-48.993 51.164-35.423 19.86-82.299 44.576-82.299 106.405V320c0 13.255 10.745 24 24 24h72.471c13.255 0 24-10.745 24-24v-5.773c0-42.86 125.268-44.645 125.268-160.627C377.504 66.256 286.902 0 202.021 0zM192 373.459c-38.196 0-69.271 31.075-69.271 69.271 0 38.195 31.075 69.27 69.271 69.27s69.271-31.075 69.271-69.271-31.075-69.27-69.271-69.27z"
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
