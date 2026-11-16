/**
 * File: PencilToolSelection.swift
 * -------------------------------
 * Layer: UI
 * Description: The tool a canvas draws with, as a value, and the PencilKit tool it becomes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// The tool a canvas draws with, as a value, so a canvas is updated exactly when it changes.
struct PencilToolSelection: Equatable {
    var kind: PencilToolKind
    /// The ink preset in use, or the one last in use while erasing or selecting.
    var preset: InkPreset
    /// The eraser removes whole strokes, or only the ink it passes over.
    var erasesWholeStrokes: Bool
    var eraserWidth: Double
    var isRulerActive: Bool
}

#if canImport(UIKit)
import PencilKit

extension PencilToolSelection {
    /// The PencilKit tool a canvas draws with.
    var tool: any PKTool {
        switch kind {
        case .ink: preset.inkingTool
        case .eraser: erasesWholeStrokes ? PKEraserTool(.vector) : PKEraserTool(.fixedWidthBitmap, width: CGFloat(eraserWidth))
        case .lasso, .laser, .readAloud, .text, .textHighlighter: PKLassoTool()
        }
    }
}
#endif
