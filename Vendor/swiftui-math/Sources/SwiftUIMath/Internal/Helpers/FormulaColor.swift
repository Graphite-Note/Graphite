/**
 * File: FormulaColor.swift
 * ------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: Graphite patch: the color arguments of `\textcolor`, `\color` and `\colorbox`,
 *              read as MathJax reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics
import Foundation

extension Math {
  /// Graphite patch: a color argument as MathJax 3.2.2 reads it (`ColorUtil.getColorByName`). A
  /// name is first looked up, in its exact case, among the 68 dvips names of its `color` package,
  /// so `Red` is that package's `#ED1B23`. Anything else goes to CSS, where a name in any case or
  /// a hex color is valid, so `red` is `#FF0000`, and where anything invalid leaves the color it
  /// inherits.
  enum FormulaColor {
    /// What the argument draws in, nil when it inherits the color around it.
    static func color(forArgument argument: String) -> CGColor? {
      rgbValue(forArgument: argument).map { value in
        CGColor(
          srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
          green: CGFloat((value >> 8) & 0xFF) / 255,
          blue: CGFloat(value & 0xFF) / 255,
          alpha: 1
        )
      }
    }

    /// Whether the argument means the formula's text color, not a color of its own: black or
    /// white, by any name or as hex. Notes use `\color{black}` and `\color{#000000}` to end a
    /// colored passage, and `\color{white}` inside a colored frame, each written against one
    /// background; MathJax's literal color would vanish on the other (Graphite's own decision).
    static func isTextColor(argument: String) -> Bool {
      let lowercasedArgument = argument.lowercased()
      if lowercasedArgument == "black" || lowercasedArgument == "white" { return true }
      guard argument.hasPrefix("#"), let value = rgbValue(forArgument: argument) else { return false }
      return value == 0 || value == 0xFFFFFF
    }

    private static func rgbValue(forArgument argument: String) -> UInt32? {
      if argument.hasPrefix("#") { return hexValue(of: argument.dropFirst()) }
      return dvipsColors[argument] ?? cssColors[argument.lowercased()]
    }

    /// CSS's `rgb` and `rrggbb`; other lengths are invalid. Alpha forms are not read.
    private static func hexValue(of digits: Substring) -> UInt32? {
      guard digits.allSatisfy(\.isHexDigit) else { return nil }
      switch digits.count {
      case 3: return UInt32(digits.map { digit in "\(digit)\(digit)" }.joined(), radix: 16)
      case 6: return UInt32(digits, radix: 16)
      default: return nil
      }
    }

    /// MathJax's `input/tex/color/ColorConstants.ts`.
    private static let dvipsColors: [String: UInt32] = [
      "Apricot": 0xFBB982, "Aquamarine": 0x00B5BE, "Bittersweet": 0xC04F17, "Black": 0x221E1F,
      "Blue": 0x2D2F92, "BlueGreen": 0x00B3B8, "BlueViolet": 0x473992, "BrickRed": 0xB6321C,
      "Brown": 0x792500, "BurntOrange": 0xF7921D, "CadetBlue": 0x74729A, "CarnationPink": 0xF282B4,
      "Cerulean": 0x00A2E3, "CornflowerBlue": 0x41B0E4, "Cyan": 0x00AEEF, "Dandelion": 0xFDBC42,
      "DarkOrchid": 0xA4538A, "Emerald": 0x00A99D, "ForestGreen": 0x009B55, "Fuchsia": 0x8C368C,
      "Goldenrod": 0xFFDF42, "Gray": 0x949698, "Green": 0x00A64F, "GreenYellow": 0xDFE674,
      "JungleGreen": 0x00A99A, "Lavender": 0xF49EC4, "LimeGreen": 0x8DC73E, "Magenta": 0xEC008C,
      "Mahogany": 0xA9341F, "Maroon": 0xAF3235, "Melon": 0xF89E7B, "MidnightBlue": 0x006795,
      "Mulberry": 0xA93C93, "NavyBlue": 0x006EB8, "OliveGreen": 0x3C8031, "Orange": 0xF58137,
      "OrangeRed": 0xED135A, "Orchid": 0xAF72B0, "Peach": 0xF7965A, "Periwinkle": 0x7977B8,
      "PineGreen": 0x008B72, "Plum": 0x92268F, "ProcessBlue": 0x00B0F0, "Purple": 0x99479B,
      "RawSienna": 0x974006, "Red": 0xED1B23, "RedOrange": 0xF26035, "RedViolet": 0xA1246B,
      "Rhodamine": 0xEF559F, "RoyalBlue": 0x0071BC, "RoyalPurple": 0x613F99, "RubineRed": 0xED017D,
      "Salmon": 0xF69289, "SeaGreen": 0x3FBC9D, "Sepia": 0x671800, "SkyBlue": 0x46C5DD,
      "SpringGreen": 0xC6DC67, "Tan": 0xDA9D76, "TealBlue": 0x00AEB3, "Thistle": 0xD883B7,
      "Turquoise": 0x00B4CE, "Violet": 0x58429B, "VioletRed": 0xEF58A0, "White": 0xFFFFFF,
      "WildStrawberry": 0xEE2967, "Yellow": 0xFFF200, "YellowGreen": 0x98CC70,
      "YellowOrange": 0xFAA21A,
    ]

    /// CSS's named colors, which browsers give MathJax's other names.
    private static let cssColors: [String: UInt32] = [
      "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF, "aquamarine": 0x7FFFD4,
      "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4, "black": 0x000000,
      "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
      "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00, "chocolate": 0xD2691E,
      "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC, "crimson": 0xDC143C,
      "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B, "darkgoldenrod": 0xB8860B,
      "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B,
      "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F, "darkorange": 0xFF8C00,
      "darkorchid": 0x9932CC, "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F,
      "darkslateblue": 0x483D8B, "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F,
      "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3, "deeppink": 0xFF1493,
      "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1E90FF,
      "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22, "fuchsia": 0xFF00FF,
      "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF, "gold": 0xFFD700, "goldenrod": 0xDAA520,
      "gray": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F, "grey": 0x808080,
      "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C, "indigo": 0x4B0082,
      "ivory": 0xFFFFF0, "khaki": 0xF0E68C, "lavender": 0xE6E6FA, "lavenderblush": 0xFFF0F5,
      "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6, "lightcoral": 0xF08080,
      "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3,
      "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A,
      "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA, "lightslategray": 0x778899,
      "lightslategrey": 0x778899, "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0,
      "lime": 0x00FF00, "limegreen": 0x32CD32, "linen": 0xFAF0E6, "magenta": 0xFF00FF,
      "maroon": 0x800000, "mediumaquamarine": 0x66CDAA, "mediumblue": 0x0000CD,
      "mediumorchid": 0xBA55D3, "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371,
      "mediumslateblue": 0x7B68EE, "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC,
      "mediumvioletred": 0xC71585, "midnightblue": 0x191970, "mintcream": 0xF5FFFA,
      "mistyrose": 0xFFE4E1, "moccasin": 0xFFE4B5, "navajowhite": 0xFFDEAD, "navy": 0x000080,
      "oldlace": 0xFDF5E6, "olive": 0x808000, "olivedrab": 0x6B8E23, "orange": 0xFFA500,
      "orangered": 0xFF4500, "orchid": 0xDA70D6, "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98,
      "paleturquoise": 0xAFEEEE, "palevioletred": 0xDB7093, "papayawhip": 0xFFEFD5,
      "peachpuff": 0xFFDAB9, "peru": 0xCD853F, "pink": 0xFFC0CB, "plum": 0xDDA0DD,
      "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399, "red": 0xFF0000,
      "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1, "saddlebrown": 0x8B4513, "salmon": 0xFA8072,
      "sandybrown": 0xF4A460, "seagreen": 0x2E8B57, "seashell": 0xFFF5EE, "sienna": 0xA0522D,
      "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD, "slategray": 0x708090,
      "slategrey": 0x708090, "snow": 0xFFFAFA, "springgreen": 0x00FF7F, "steelblue": 0x4682B4,
      "tan": 0xD2B48C, "teal": 0x008080, "thistle": 0xD8BFD8, "tomato": 0xFF6347,
      "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3, "white": 0xFFFFFF,
      "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00, "yellowgreen": 0x9ACD32,
    ]
  }
}
