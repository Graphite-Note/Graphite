/**
 * File: PencilInk.swift
 * ---------------------
 * Layer: UI
 * Description: Every ink PencilKit draws with, under the names of the system's palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// Every ink PencilKit draws with, under the names of the system's palette.
enum PencilInk: String, Codable, CaseIterable, Identifiable {
    case pen, monoline, fountainPen, reedPen, pencil, crayon, watercolor, highlighter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pen: "Pen"
        case .monoline: "Monoline"
        case .fountainPen: "Fountain Pen"
        case .reedPen: "Reed Pen"
        case .pencil: "Pencil"
        case .crayon: "Crayon"
        case .watercolor: "Watercolor"
        case .highlighter: "Highlighter"
        }
    }
    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .monoline: "pencil.line"
        case .fountainPen: "paintbrush.pointed"
        case .reedPen: "pencil.and.outline"
        case .pencil: "pencil"
        case .crayon: "scribble"
        case .watercolor: "paintbrush"
        case .highlighter: "highlighter"
        }
    }

    /// The widths PencilKit accepts for the ink, in points.
    var widthRange: ClosedRange<Double> {
        switch self {
        case .pen: 0.9...25
        case .monoline: 0.5...4
        case .fountainPen: 1.5...14
        case .reedPen: 5...40
        case .pencil: 2.4...16
        case .crayon: 10...50
        case .watercolor: 10...80
        case .highlighter: 7.5...60
        }
    }

    /// The three widths a tool of this ink starts with on the bar, from fine to broad. Each
    /// tool can change its own (`InkPreset.widthChoices`).
    var widthChoices: [Double] {
        switch self {
        case .pen: [1.6, 2.8, 4.8]
        case .monoline: [0.8, 1.6, 3.0]
        case .fountainPen: [2.5, 4.0, 7.0]
        case .reedPen: [8, 16, 28]
        case .pencil: [2.4, 4.0, 7.0]
        case .crayon: [12, 22, 36]
        case .watercolor: [14, 30, 52]
        case .highlighter: [10, 18, 28]
        }
    }
    var mediumWidth: Double { widthChoices[1] }

    var defaultColorHex: String {
        switch self {
        case .pencil: "#3a3a3c"
        case .highlighter: "#f6d743"
        default: "#1c1c1e"
        }
    }
}

#if canImport(UIKit)
import PencilKit

extension PencilInk {
    /// The inks this system draws with.
    static var availableInks: [PencilInk] { allCases }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .reedPen: return .reed
        case .pencil: return .pencil
        case .crayon: return .crayon
        case .watercolor: return .watercolor
        case .highlighter: return .marker
        }
    }
}
#endif
