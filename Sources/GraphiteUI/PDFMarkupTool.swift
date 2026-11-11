/**
 * File: PDFMarkupTool.swift
 * -------------------------
 * Layer: UI
 * Description: The tool chosen in the Mac's markup row, and what letting go of the mouse after selecting text
 *              does with it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

/// The tool chosen in the Mac's markup row. With the row hidden, the tool is text selection.
enum PDFMarkupTool: Hashable, Sendable, CaseIterable {
    /// Selecting text only selects it; the right-click menu and the menu bar mark it.
    case textSelection
    /// Every text selection is marked with the chosen style when the mouse is let go, as Preview does.
    case highlight

    var title: String {
        switch self {
        case .textSelection: "Text Selection"
        case .highlight: "Highlight"
        }
    }

    var symbolName: String {
        switch self {
        case .textSelection: "character.cursor.ibeam"
        case .highlight: "highlighter"
        }
    }

    /// The mark to put on the selection when the mouse is let go after selecting text, or nil to leave it selected.
    /// A click that chose a mark already on the page selects that mark, so it never marks the text again.
    func styleToApplyOnMouseUp(style: PDFMarkupStyle, selectionHasText: Bool, clickChoseExistingMark: Bool) -> PDFMarkupStyle? {
        switch self {
        case .textSelection: nil
        case .highlight: selectionHasText && !clickChoseExistingMark ? style : nil
        }
    }
}
