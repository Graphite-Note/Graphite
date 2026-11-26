/**
 * File: PresentationPencilTool.swift
 * ----------------------------------
 * Layer: UI
 * Description: What Apple Pencil does on a presented slide, the laser or ink that fades, and the ink's colours,
 *              kept on the device; and the mapping of a point between a screen's slide and the slide's canvas.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// What Apple Pencil does on a presented slide (decision 9). Neither leaves anything in the note.
enum PresentationPencilTool: String, CaseIterable, Identifiable {
    /// Graphite's laser of pages and drawings, as its dot or line style is set.
    case laser
    /// Ink in a colour, which fades a moment after the Pencil lifts.
    case fadingInk

    static let preferenceKey = "GraphitePresentationPencilTool"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .laser: "Laser Pointer"
        case .fadingInk: "Fading Ink"
        }
    }

    var symbolName: String {
        switch self {
        case .laser: "rays"
        case .fadingInk: "pencil.tip"
        }
    }

    /// The tool kept in `defaults`: the laser when none, or one this build does not know, is kept.
    static func stored(in defaults: UserDefaults) -> PresentationPencilTool {
        defaults.string(forKey: preferenceKey).flatMap(PresentationPencilTool.init(rawValue:)) ?? .laser
    }
}

/// The colours fading ink is written in: ones that read on light and dark slides alike.
enum PresentationInkColor: String, CaseIterable, Identifiable {
    case red, blue, green, orange

    static let preferenceKey = "GraphitePresentationInkColor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "Red"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        }
    }

    /// The colour's red, green and blue components, from 0 to 1.
    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: (0.92, 0.2, 0.18)
        case .blue: (0.16, 0.45, 0.95)
        case .green: (0.18, 0.7, 0.33)
        case .orange: (0.98, 0.58, 0.1)
        }
    }

    var color: Color { Color(red: components.red, green: components.green, blue: components.blue) }

    static func stored(in defaults: UserDefaults) -> PresentationInkColor {
        defaults.string(forKey: preferenceKey).flatMap(PresentationInkColor.init(rawValue:)) ?? .red
    }
}

/// The Pencil's choices a presentation starts with, read from the device's preferences when it starts.
struct PresentationPencilChoices: Equatable {
    var tool: PresentationPencilTool
    var inkColor: PresentationInkColor
    var laserStyle: LaserPointerStyle

    static func stored(in defaults: UserDefaults) -> PresentationPencilChoices {
        PresentationPencilChoices(tool: .stored(in: defaults), inkColor: .stored(in: defaults), laserStyle: .stored(in: defaults))
    }
}

/// Where a point of a screen's slide is on the slide's canvas, and back: the marks of the Pencil travel between
/// the device and an external display in canvas points, so they land on the same words on both.
struct PresentationCanvasMapping: Equatable {
    /// Where the canvas is drawn in the view, in the view's points (`NoteSlideView.canvasFrame(in:)`).
    let canvasFrame: CGRect

    init(viewSize: CGSize) {
        canvasFrame = NoteSlideView.canvasFrame(in: viewSize)
    }

    /// The view's points per canvas point.
    var scale: CGFloat { NotePresentation.canvasSize.width > 0 ? canvasFrame.width / NotePresentation.canvasSize.width : 1 }

    func canvasPoint(fromViewPoint viewPoint: CGPoint) -> CGPoint {
        guard scale > 0 else { return viewPoint }
        return CGPoint(x: (viewPoint.x - canvasFrame.minX) / scale, y: (viewPoint.y - canvasFrame.minY) / scale)
    }

    func viewPoint(fromCanvasPoint canvasPoint: CGPoint) -> CGPoint {
        CGPoint(x: canvasFrame.minX + canvasPoint.x * scale, y: canvasFrame.minY + canvasPoint.y * scale)
    }
}
