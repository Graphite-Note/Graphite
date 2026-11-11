/**
 * File: PDFMarkupStyle.swift
 * --------------------------
 * Layer: UI
 * Description: The mark the Mac's highlight button puts on selected text: a highlight colour, an underline or a
 *              strikethrough, kept on the device by its stored name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import GraphiteApple

/// The mark the highlight button of the Mac's markup row puts on selected text, chosen
/// from the button's menu and kept on the device. Underline and strikethrough are red, as
/// the iPad's selection menu makes them.
enum PDFMarkupStyle: Hashable, Sendable, RawRepresentable, Identifiable {
    case highlight(PDFMarkupColor)
    case underline
    case strikeOut

    static let `default` = PDFMarkupStyle.highlight(.yellow)

    /// The styles the highlight button's menu offers, in its order.
    static let choices: [PDFMarkupStyle] = PDFMarkupColor.highlightColors.map(PDFMarkupStyle.highlight) + [.underline, .strikeOut]

    private static let highlightPrefix = "highlight-"

    /// The name the style is kept under: `highlight-yellow`, `underline` or `strikeOut`.
    var rawValue: String {
        switch self {
        case .highlight(let color): Self.highlightPrefix + color.rawValue
        case .underline: PDFMarkupKind.underline.rawValue
        case .strikeOut: PDFMarkupKind.strikeOut.rawValue
        }
    }

    /// The style kept under a name, or nil for a name no style has, such as one from a newer version.
    init?(rawValue: String) {
        if rawValue.hasPrefix(Self.highlightPrefix) {
            guard let color = PDFMarkupColor(rawValue: String(rawValue.dropFirst(Self.highlightPrefix.count))),
                  PDFMarkupColor.highlightColors.contains(color) else { return nil }
            self = .highlight(color)
            return
        }
        switch PDFMarkupKind(rawValue: rawValue) {
        case .underline: self = .underline
        case .strikeOut: self = .strikeOut
        case .highlight, nil: return nil
        }
    }

    var id: String { rawValue }

    var kind: PDFMarkupKind {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        }
    }

    var color: PDFMarkupColor {
        switch self {
        case .highlight(let color): color
        case .underline, .strikeOut: .red
        }
    }

    /// The menu's title: the colour for a highlight, the kind otherwise.
    var title: String {
        switch self {
        case .highlight(let color): color.title
        case .underline, .strikeOut: kind.title
        }
    }

    /// The SF Symbol of the kind of mark.
    var symbolName: String {
        switch self {
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeOut: "strikethrough"
        }
    }
}
