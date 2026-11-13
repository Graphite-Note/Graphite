/**
 * File: PDFMarkupToolbar.swift
 * ----------------------------
 * Layer: UI
 * Description: One PDF pane's markup row on the Mac: whether it shows, the tool chosen in it, the Draw tool's
 *              colour and width, and whether the PDF has text selected, for the row and the menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
 */

import SwiftUI

/// One PDF pane's markup row on the Mac. The row starts hidden in every pane; hiding it
/// goes back to text selection, so a hidden row never leaves the highlighter on.
@MainActor @Observable
final class PDFMarkupToolbar {
    private(set) var isRowShown = false
    private(set) var chosenTool = PDFMarkupTool.textSelection
    /// Whether the PDF view has text selected, which the menu bar's Annotate commands need.
    private(set) var hasTextSelection = false
    /// The colour and width of the Draw tool's next stroke, as kept on the device
    /// (`PDFAnnotationPreferenceKey.markupInkStyle`), which the pane hands over.
    private(set) var inkStyle = PDFMarkupInkStyle.default

    /// The tool the PDF view follows: text selection while the row is hidden.
    var tool: PDFMarkupTool { isRowShown ? chosenTool : .textSelection }

    func toggleRow() {
        isRowShown.toggle()
        if !isRowShown { chosenTool = .textSelection }
    }

    /// Chooses a tool of the row, showing the row if a menu command chose it while hidden.
    func choose(_ tool: PDFMarkupTool) {
        chosenTool = tool
        isRowShown = true
    }

    func textSelectionChanged(hasText: Bool) {
        if hasTextSelection != hasText { hasTextSelection = hasText }
    }

    func useInkStyle(_ style: PDFMarkupInkStyle) {
        if inkStyle != style { inkStyle = style }
    }
}

extension EnvironmentValues {
    /// The markup row of the PDF pane around a PDF view, on the Mac; nil elsewhere.
    @Entry var pdfMarkupToolbar: PDFMarkupToolbar? = nil
}
