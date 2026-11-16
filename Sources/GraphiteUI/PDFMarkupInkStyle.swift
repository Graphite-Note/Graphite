/**
 * File: PDFMarkupInkStyle.swift
 * -----------------------------
 * Layer: UI
 * Description: The colour and line width the Mac's Draw tool gives a stroke, kept on the device by one stored name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import GraphiteCore

/// How thick the Draw tool's line is, in points of the page.
enum PDFMarkupInkWidth: String, Hashable, Sendable, CaseIterable, Identifiable {
    case fine, medium, bold

    var id: String { rawValue }

    var points: Double {
        switch self {
        case .fine: 1
        case .medium: 2.5
        case .bold: 5
        }
    }

    var title: String {
        switch self {
        case .fine: "Fine"
        case .medium: "Medium"
        case .bold: "Bold"
        }
    }
}

/// The colour and line width of the next stroke the Mac's Draw tool makes, chosen in the
/// markup row and kept on the device as `medium #000000`.
struct PDFMarkupInkStyle: Hashable, Sendable, RawRepresentable {
    var color: PDFTextColor
    var width: PDFMarkupInkWidth

    static let `default` = PDFMarkupInkStyle(color: .black, width: .medium)

    init(color: PDFTextColor, width: PDFMarkupInkWidth) {
        self.color = color
        self.width = width
    }

    var rawValue: String { "\(width.rawValue) \(color.hex)" }

    /// The style kept under a name, or nil for a name no style has, such as one from a newer version.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let width = PDFMarkupInkWidth(rawValue: String(parts[0])),
              let color = PDFTextColor(hex: String(parts[1])) else { return nil }
        self.init(color: color, width: width)
    }
}
