/**
 * File: DiagramColor.swift
 * ------------------------
 * Layer: Core
 * Description: A color a diagram's own statements give.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics

/// A color a diagram's own statements give (`fill:#f9f`, `stroke:rgb(51, 51, 51)`, `color:red`), as sRGB channels and opacity,
/// each from 0 to 1.
public struct DiagramColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The color a style value writes, or nil for a value not read here: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`,
    /// `rgb(r, g, b)`, `rgba(r, g, b, a)` (channels 0 to 255 or percentages, opacity 0 to 1 or a percentage), a CSS color
    /// name, and `none` or `transparent`, which are no color at all. Case and spaces around the value do not matter.
    public init?(cssText: String) {
        let text = cssText.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            guard let color = Self.hexadecimalColor(String(text.dropFirst())) else { return nil }
            self = color
        } else if text.hasPrefix("rgb"), let color = Self.functionalColor(text) {
            self = color
        } else if text == "none" || text == "transparent" {
            self = DiagramColor(red: 0, green: 0, blue: 0, alpha: 0)
        } else if let value = Self.namedColors[text] {
            self = DiagramColor(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        } else {
            return nil
        }
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func hexadecimalColor(_ digits: String) -> DiagramColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded: String
        switch digits.count {
        case 3, 4: expanded = digits.map { digit in "\(digit)\(digit)" }.joined()
        case 6, 8: expanded = digits
        default: return nil
        }
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        let hasOpacity = expanded.count == 8
        let shift: UInt64 = hasOpacity ? 8 : 0
        return DiagramColor(red: Double(value >> (16 + shift) & 0xFF) / 255, green: Double(value >> (8 + shift) & 0xFF) / 255,
                            blue: Double(value >> shift & 0xFF) / 255, alpha: hasOpacity ? Double(value & 0xFF) / 255 : 1)
    }

    /// `rgb(51, 51, 51)`, `rgba(51 51 51 / 50%)` and `rgb(20%, 20%, 20%)`.
    private static func functionalColor(_ text: String) -> DiagramColor? {
        guard let opening = text.firstIndex(of: "("), text.hasSuffix(")"), ["rgb", "rgba"].contains(String(text[..<opening])) else { return nil }
        let inside = text[text.index(after: opening)..<text.index(before: text.endIndex)]
        let parts = inside.split(whereSeparator: { character in character == "," || character == " " || character == "/" }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var channels: [Double] = []
        for part in parts.prefix(3) {
            guard let channel = number(part, fullScale: 255) else { return nil }
            channels.append(min(1, max(0, channel)))
        }
        let alpha = parts.count == 4 ? number(parts[3], fullScale: 1).map { opacity in min(1, max(0, opacity)) } : 1
        guard let alpha else { return nil }
        return DiagramColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// A number out of `fullScale`, or a percentage.
    private static func number(_ text: String, fullScale: Double) -> Double? {
        if text.hasSuffix("%") { return Double(text.dropLast()).map { percentage in percentage / 100 } }
        return Double(text).map { value in value / fullScale }
    }

    /// The CSS color names a diagram is likely to use, as 0xRRGGBB.
    private static let namedColors: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF, "yellow": 0xFFFF00,
        "orange": 0xFFA500, "purple": 0x800080, "pink": 0xFFC0CB, "gray": 0x808080, "grey": 0x808080, "brown": 0xA52A2A,
        "cyan": 0x00FFFF, "aqua": 0x00FFFF, "magenta": 0xFF00FF, "fuchsia": 0xFF00FF, "lime": 0x00FF00, "navy": 0x000080,
        "teal": 0x008080, "maroon": 0x800000, "olive": 0x808000, "silver": 0xC0C0C0, "gold": 0xFFD700, "indigo": 0x4B0082,
        "violet": 0xEE82EE, "coral": 0xFF7F50, "salmon": 0xFA8072, "khaki": 0xF0E68C, "tan": 0xD2B48C, "beige": 0xF5F5DC,
        "ivory": 0xFFFFF0, "lavender": 0xE6E6FA, "plum": 0xDDA0DD, "orchid": 0xDA70D6, "crimson": 0xDC143C, "tomato": 0xFF6347,
        "turquoise": 0x40E0D0, "skyblue": 0x87CEEB, "lightblue": 0xADD8E6, "lightgreen": 0x90EE90, "lightgray": 0xD3D3D3,
        "lightgrey": 0xD3D3D3, "lightyellow": 0xFFFFE0, "lightpink": 0xFFB6C1, "lightcoral": 0xF08080, "lightsalmon": 0xFFA07A,
        "lightcyan": 0xE0FFFF, "darkblue": 0x00008B, "darkgreen": 0x006400, "darkred": 0x8B0000, "darkgray": 0xA9A9A9,
        "darkgrey": 0xA9A9A9, "darkorange": 0xFF8C00, "darkcyan": 0x008B8B, "darkviolet": 0x9400D3, "darkmagenta": 0x8B008B,
        "royalblue": 0x4169E1, "steelblue": 0x4682B4, "dodgerblue": 0x1E90FF, "cornflowerblue": 0x6495ED, "slateblue": 0x6A5ACD,
        "seagreen": 0x2E8B57, "forestgreen": 0x228B22, "limegreen": 0x32CD32, "springgreen": 0x00FF7F, "chartreuse": 0x7FFF00,
        "firebrick": 0xB22222, "hotpink": 0xFF69B4, "deeppink": 0xFF1493, "gainsboro": 0xDCDCDC, "whitesmoke": 0xF5F5F5,
        "wheat": 0xF5DEB3, "peachpuff": 0xFFDAB9, "mistyrose": 0xFFE4E1, "aliceblue": 0xF0F8FF, "honeydew": 0xF0FFF0,
        "lemonchiffon": 0xFFFACD, "dimgray": 0x696969, "dimgrey": 0x696969, "slategray": 0x708090, "slategrey": 0x708090,
        "midnightblue": 0x191970, "sienna": 0xA0522D, "chocolate": 0xD2691E, "peru": 0xCD853F, "goldenrod": 0xDAA520,
    ]
}
