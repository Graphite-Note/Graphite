/**
 * File: PDFMarkupStyle.swift
 * --------------------------
 * Layer: UI
 * Description: The mark the Mac's highlight button and the iPad's text highlighter put on selected text: a kind and
 *              any colour, kept on the device by its stored name.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
 */

import GraphiteApple

/// The mark the highlight button of the Mac's markup row and the iPad's text highlighter
/// put on selected text: a kind and any colour, chosen in the row or its menus and kept on
/// the device. Underline and strikethrough start red, as the iPad's selection menu makes them.
struct PDFMarkupStyle: Hashable, Sendable, RawRepresentable, Identifiable {
    let kind: PDFMarkupKind
    let color: PDFMarkupColor

    init(kind: PDFMarkupKind, color: PDFMarkupColor) {
        self.kind = kind
        self.color = color
    }

    static func highlight(_ color: PDFMarkupColor) -> PDFMarkupStyle { PDFMarkupStyle(kind: .highlight, color: color) }
    static let underline = PDFMarkupStyle(kind: .underline, color: .red)
    static let strikeOut = PDFMarkupStyle(kind: .strikeOut, color: .red)

    static let `default` = PDFMarkupStyle.highlight(.yellow)

    /// The styles the highlight button's menu offers, in its order, before any colour is
    /// saved: `choices(highlightColors:)` gives them with the saved text-mark colours.
    static let choices: [PDFMarkupStyle] = choices(highlightColors: PDFMarkupColor.highlightColors)

    /// A highlight in each colour, then a red underline and a red strikethrough.
    static func choices(highlightColors: [PDFMarkupColor]) -> [PDFMarkupStyle] {
        highlightColors.map(PDFMarkupStyle.highlight) + [.underline, .strikeOut]
    }

    /// The colour an underline or strikethrough starts with.
    private static let lineColor = PDFMarkupColor.red
    private static let colorSeparator: Character = "-"

    /// The name the style is kept under: `highlight-yellow`, `highlight-#FF8000`, `underline`
    /// (red) or `underline-blue`, `strikeOut` or `strikeOut-#336699`. Names an older build kept
    /// read the same.
    var rawValue: String {
        if kind != .highlight, color == Self.lineColor { return kind.rawValue }
        return kind.rawValue + String(Self.colorSeparator) + color.storedName
    }

    /// The style kept under a name, or nil for a name no style has, such as one from a newer version.
    init?(rawValue: String) {
        guard let separatorIndex = rawValue.firstIndex(of: Self.colorSeparator) else {
            // Only an underline or strikethrough is kept without a colour: it is red.
            guard let kind = PDFMarkupKind(rawValue: rawValue), kind != .highlight else { return nil }
            self.init(kind: kind, color: Self.lineColor)
            return
        }
        guard let kind = PDFMarkupKind(rawValue: String(rawValue[..<separatorIndex])),
              let color = PDFMarkupColor(storedName: String(rawValue[rawValue.index(after: separatorIndex)...])) else { return nil }
        self.init(kind: kind, color: color)
    }

    var id: String { rawValue }

    /// The menu's title: the colour for a highlight, the kind otherwise, with its colour when not red.
    var title: String {
        switch kind {
        case .highlight: color.title
        case .underline, .strikeOut: color == Self.lineColor ? kind.title : "\(kind.title) \(color.title)"
        }
    }

    /// The same mark in another colour.
    func recolored(_ newColor: PDFMarkupColor) -> PDFMarkupStyle { PDFMarkupStyle(kind: kind, color: newColor) }

    /// The SF Symbol of the kind of mark.
    var symbolName: String {
        switch kind {
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeOut: "strikethrough"
        }
    }
}
