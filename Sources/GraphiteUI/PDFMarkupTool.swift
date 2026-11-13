/**
 * File: PDFMarkupTool.swift
 * -------------------------
 * Layer: UI
 * Description: The tool chosen in the Mac's markup row, what letting go of the mouse after selecting text does with
 *              it, and whether it takes presses on pages from PDFKit.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
 */

/// The tool chosen in the Mac's markup row. With the row hidden, the tool is text selection.
enum PDFMarkupTool: Hashable, Sendable, CaseIterable {
    /// Selecting text only selects it; the right-click menu and the menu bar mark it.
    case textSelection
    /// Every text selection is marked with the chosen style when the mouse is let go, as Preview does.
    case highlight
    /// Dragging on a page draws ink with the row's colour and width, stored as the iPad's ink is.
    case draw
    /// Dragging over ink removes each whole stroke it touches.
    case eraseInk
    /// A click on a page places a text box and starts typing in it; a click on a box selects it.
    case textBox

    var title: String {
        switch self {
        case .textSelection: "Text Selection"
        case .highlight: "Highlight"
        case .draw: "Draw"
        case .eraseInk: "Eraser"
        case .textBox: "Text Box"
        }
    }

    var symbolName: String {
        switch self {
        case .textSelection: "character.cursor.ibeam"
        case .highlight: "highlighter"
        case .draw: "scribble.variable"
        case .eraseInk: "eraser"
        case .textBox: "character.textbox"
        }
    }

    /// Whether a press on a page belongs to the tool rather than to PDFKit, which then
    /// neither selects text nor follows a link under the pointer.
    var takesPagePresses: Bool {
        switch self {
        case .textSelection, .highlight: false
        case .draw, .eraseInk, .textBox: true
        }
    }

    /// The mark to put on the selection when the mouse is let go after selecting text, or nil to leave it selected.
    /// A click that chose a mark already on the page selects that mark, so it never marks the text again.
    func styleToApplyOnMouseUp(style: PDFMarkupStyle, selectionHasText: Bool, clickChoseExistingMark: Bool) -> PDFMarkupStyle? {
        switch self {
        case .textSelection, .draw, .eraseInk, .textBox: nil
        case .highlight: selectionHasText && !clickChoseExistingMark ? style : nil
        }
    }
}
