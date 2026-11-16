/**
 * File: PDFAnnotationInput.swift
 * ------------------------------
 * Layer: UI
 * Description: What a PDF view is told about writing on it: the tools, the finger and the pages' state.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple

/// How a PDF view accepts annotation input.
struct PDFAnnotationInput: Equatable {
    /// Pencil drawing on pages and text markup from the selection menu.
    var isEnabled: Bool
    /// One finger draws and two fingers scroll, for people without an Apple Pencil.
    var drawsWithFinger: Bool
    /// Shows the system tool picker (pens, colors, eraser, lasso, undo, redo).
    var showsToolPicker: Bool
    /// Strokes become the lines, ellipses, and polygons they were meant to be.
    var drawsShapes = false
    /// The view is the one being worked in, whether or not its tool picker shows.
    var isFocused = false
    /// The tool of the fixed tool bar; nil while the floating palette chooses the tool.
    var fixedTool: PencilToolSelection?
    /// Lines or dots shown under the ink while writing, never saved into the PDF.
    var writingGuides: DrawingPaper = .plain
    /// The Mac's markup row: its tool. The iPad marks text from its selection menu, and with
    /// the fixed bar's text highlighter (`fixedTool`).
    var markupTool = PDFMarkupTool.textSelection
    /// The mark the Mac's highlight button and the iPad's text highlighter make.
    var markupStyle = PDFMarkupStyle.default

    /// Whether the view keeps first responder for its document: Undo shortcuts reach the
    /// document's history, and a lasso selection does not bring up typing suggestions.
    var holdsFirstResponder: Bool { isEnabled && (isFocused || showsToolPicker) }
}
