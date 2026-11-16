/**
 * File: InkPreset.swift
 * ---------------------
 * Layer: UI
 * Description: One drawing tool of the Pencil bar: an ink with its color, width, opacity and three widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// One drawing tool of the bar as its owner set it up: an ink with its color, width and
/// opacity, and the three widths the bar offers for it. The bar starts with three tools and
/// holds up to `PencilToolbox.maximumPresetCount`.
struct InkPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var ink: PencilInk
    var colorHex: String
    var width: Double
    var opacity = 1.0
    /// The tool's three sizes on the bar, from the ink's own (`PencilInk.widthChoices`); a
    /// second tap on the size in use changes its width.
    var widthChoices: [Double]

    static let opacityRange = 0.1...1.0

    init(ink: PencilInk) {
        self.ink = ink
        colorHex = ink.defaultColorHex
        width = ink.mediumWidth
        widthChoices = ink.widthChoices
    }

    private enum CodingKeys: String, CodingKey {
        case id, ink, colorHex, width, opacity, widthChoices
    }

    /// A tool saved before its sizes could be changed has the ink's own.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ink = try container.decode(PencilInk.self, forKey: .ink)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        width = try container.decode(Double.self, forKey: .width)
        opacity = try container.decode(Double.self, forKey: .opacity)
        widthChoices = try container.decodeIfPresent([Double].self, forKey: .widthChoices) ?? ink.widthChoices
    }

    /// The preset with every value one the bar can show: a stored state written by another
    /// build, or by hand, may hold others.
    var validated: InkPreset {
        var preset = self
        let widthRange = ink.widthRange
        func drawableWidth(_ width: Double, otherwise fallbackWidth: Double) -> Double {
            width.isFinite ? min(max(width, widthRange.lowerBound), widthRange.upperBound) : fallbackWidth
        }
        preset.colorHex = TextColorMarkup.canonicalHex(colorHex) ?? ink.defaultColorHex
        preset.width = drawableWidth(width, otherwise: ink.mediumWidth)
        preset.opacity = opacity.isFinite ? min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) : 1
        preset.widthChoices = widthChoices.count == ink.widthChoices.count
            ? zip(widthChoices, ink.widthChoices).map { storedWidth, inkWidth in drawableWidth(storedWidth, otherwise: inkWidth) }
            : ink.widthChoices
        return preset
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit

extension InkPreset {
    var inkingTool: PKInkingTool {
        let inkType = ink.inkType
        let widthRange = inkType.validWidthRange
        let color = (UIColor(graphiteHex: colorHex) ?? .black).withAlphaComponent(CGFloat(opacity))
        return PKInkingTool(inkType, color: color, width: min(max(CGFloat(width), widthRange.lowerBound), widthRange.upperBound))
    }
}
#endif
