/**
 * File: PDFTextMarkColors.swift
 * -----------------------------
 * Layer: UI
 * Description: The colours saved on the device for highlights, underlines and strikethroughs, kept apart from the
 *              pen colours: read and written as a list of colour names, with colours added and removed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import GraphiteApple

/// The colours a highlight, underline or strikethrough is offered in, saved on the device
/// under `PDFAnnotationPreferenceKey.textMarkColors` and shared by the Mac's markup row, the
/// iPad's text highlighter and both platforms' mark menus. They start as Graphite's five
/// highlight colours; a colour chosen in a colour picker can be added, and any can be
/// removed. Pen colours are kept apart (Settings › Colors), as the ink highlighter's are.
///
/// Read with `@AppStorage(PDFAnnotationPreferenceKey.textMarkColors) var stored: Data?`,
/// then `PDFTextMarkColors(decoding: stored).colors`; change with `adding(_:)` or
/// `removing(_:)` and write back `encoded`.
struct PDFTextMarkColors: Equatable, Sendable {
    private(set) var colors: [PDFMarkupColor]

    /// At most this many colours are kept, so the list stays a row of swatches.
    static let maximumColorCount = 24

    init(colors: [PDFMarkupColor]) {
        var unique: [PDFMarkupColor] = []
        for color in colors where !unique.contains(color) { unique.append(color) }
        self.colors = Array(unique.prefix(Self.maximumColorCount))
    }

    static let standard = PDFTextMarkColors(colors: PDFMarkupColor.highlightColors)

    /// The saved colours; the standard ones while none were saved or the saved list cannot be
    /// read, which is left as it is until a colour is added or removed.
    init(decoding storedData: Data?) {
        guard let storedData, let names = try? JSONDecoder().decode([String].self, from: storedData) else { // Unreadable reads as none saved.
            self = .standard
            return
        }
        self.init(colors: names.compactMap(PDFMarkupColor.init(storedName:)))
    }

    /// The list as it is saved: the colours' names in order, as JSON.
    var encoded: Data? {
        try? JSONEncoder().encode(colors.map(\.storedName)) // An array of strings always encodes.
    }

    func contains(_ color: PDFMarkupColor) -> Bool { colors.contains(color) }

    /// Adds `color` to the list saved in `preferences`, as a colour picker's choice is kept.
    static func save(_ color: PDFMarkupColor, in preferences: UserDefaults) {
        let key = PDFAnnotationPreferenceKey.textMarkColors
        preferences.set(PDFTextMarkColors(decoding: preferences.data(forKey: key)).adding(color).encoded, forKey: key)
    }

    /// The list with `color` at its end, unless it is already in it or the list is full.
    func adding(_ color: PDFMarkupColor) -> PDFTextMarkColors {
        PDFTextMarkColors(colors: colors + [color])
    }

    func removing(_ color: PDFMarkupColor) -> PDFTextMarkColors {
        PDFTextMarkColors(colors: colors.filter { savedColor in savedColor != color })
    }

    /// The colours to offer for a mark of `kind`, with `currentColor` (a mark's own colour,
    /// perhaps from another application) first when it is not among them, so it shows and
    /// can be ticked. Underlines and strikethroughs are offered red first.
    func offered(for kind: PDFMarkupKind, including currentColor: PDFMarkupColor? = nil) -> [PDFMarkupColor] {
        let kindColors = kind == .highlight ? colors : [PDFMarkupStyle.underline.color] + colors.filter { color in color != PDFMarkupStyle.underline.color }
        guard let currentColor, !kindColors.contains(currentColor) else { return kindColors }
        return [currentColor] + kindColors
    }
}
