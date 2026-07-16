import SwiftUI

/// Verbatim port of reactotron-core-ui themes.ts (dark theme).
enum Theme {
  static let background = Color(hex: 0x1E1E1E)
  static let backgroundDarker = Color(hsl: 0, 0, 10.6)
  static let backgroundHighlight = Color(hex: 0x464B50)
  static let backgroundLight = Color(hex: 0xFFFFFF)
  static let backgroundLighter = Color(hex: 0x323537)
  static let backgroundSubtleDark = Color(hsl: 0, 0, 8.2)
  static let backgroundSubtleLight = Color(hsl: 0, 0, 12.4)
  static let bold = Color(hex: 0xF9EE98)
  static let chrome = Color(hsl: 0, 0, 12.9)
  static let chromeLine = Color(hsl: 0, 0, 14.7)
  static let constant = Color(hex: 0xCDA869)
  static let foreground = Color(hex: 0xA7A7A7)
  static let foregroundDark = Color(hex: 0x838184)
  static let foregroundLight = Color(hex: 0xC3C3C3)
  static let glow = Color(hsl: 0, 0, 9.4).opacity(0.8)
  static let heading = Color(hex: 0x7587A6)
  static let highlight = Color(hsl: 290, 3.2, 47.4)
  static let keyword = Color(hex: 0x9B859D)
  static let line = Color(hsl: 204, 4.8, 18.5)
  static let modalOverlay = Color(hsl: 0, 0, 7.1).opacity(0.95)
  static let string = Color(hex: 0x8F9D6A)
  static let subtleLine = Color(hsl: 204, 4.8, 16.5)
  static let support = Color(hex: 0xAFC4DB)
  static let tag = Color(hex: 0xCF6A4C)
  static let tagComplement = Color(hsl: 13.7, 57.7, 91.6)
  static let warning = Color(hex: 0x9B703F)

  /// themes.ts fontFamily: "Fira Code", "SF Mono", ... — SF Mono is the macOS-native member of that stack.
  static func font(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  /// CSS hsl(h, s%, l%) — matches CSS hsl-to-rgb conversion.
  init(hsl h: Double, _ s: Double, _ l: Double) {
    let s = s / 100, l = l / 100
    let c = (1 - abs(2 * l - 1)) * s
    let hp = h / 60
    let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
    let (r1, g1, b1): (Double, Double, Double) =
      switch hp {
      case ..<1: (c, x, 0)
      case ..<2: (x, c, 0)
      case ..<3: (0, c, x)
      case ..<4: (0, x, c)
      case ..<5: (x, 0, c)
      default: (c, 0, x)
      }
    let m = l - c / 2
    self.init(red: r1 + m, green: g1 + m, blue: b1 + m)
  }
}
