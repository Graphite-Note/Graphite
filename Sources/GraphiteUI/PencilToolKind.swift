/**
 * File: PencilToolKind.swift
 * --------------------------
 * Layer: UI
 * Description: What the Pencil bar has in use: an ink, the eraser, the lasso, the laser, the Read Aloud pen or text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// What the bar has in use: one of its inks, the eraser, the lasso, the laser pointer, the
/// Read Aloud pen, the text tool, or the text highlighter.
enum PencilToolKind: String, Codable, CaseIterable, Identifiable {
    case ink, eraser, lasso, laser, readAloud, text
    /// Marks the PDF text it selects, when the touch lifts, with the style chosen beside it
    /// (`PDFTextHighlighterInteraction`). The Pencil's freehand highlighter is an ink.
    case textHighlighter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ink: "Ink"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .laser: "Laser Pointer"
        case .readAloud: "Read Aloud Pen"
        case .text: "Text Box"
        case .textHighlighter: "Text Highlighter"
        }
    }
    var symbolName: String {
        switch self {
        case .ink: "pencil.tip"
        case .eraser: "eraser"
        case .lasso: "lasso"
        // Only a fallback: the bar and the palette draw the laser's own glyph (`LaserPointerGlyph`).
        case .laser: "cursorarrow.rays"
        // Only a fallback, as for the laser (`ReadAloudPenGlyph`).
        case .readAloud: "speaker.wave.2"
        case .text: "character.textbox"
        // A text cursor: the tool marks text, where the ink highlighter's symbol draws freely.
        case .textHighlighter: "character.cursor.ibeam"
        }
    }
    /// Whether the canvas draws with PencilKit's tool: the lasso, the laser pointer, the Read
    /// Aloud pen, the text tool and the text highlighter are Graphite's own and draw nothing.
    var drawsInk: Bool { self == .ink || self == .eraser }
    /// Tools for the moment, put away with the app: the laser points while presenting, the
    /// Read Aloud pen points at what to read, the text tool places a box or two among the
    /// ink, and the text highlighter marks a PDF's text. The tool before them is kept instead,
    /// which a build without them can read.
    var isPutAwayWithApp: Bool {
        switch self {
        case .ink, .eraser, .lasso: false
        case .laser, .readAloud, .text, .textHighlighter: true
        }
    }
}
