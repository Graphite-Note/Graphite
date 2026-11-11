/**
 * File: PDFMarkupMenuActions.swift
 * --------------------------------
 * Layer: UI
 * Description: What the Mac menu bar's markup commands act on: the focused PDF pane's markup row and its selected
 *              text, and the View and Tools menu items that use it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import SwiftUI
import GraphiteApple

/// The focused PDF pane's markup, for View › Show Markup Toolbar and Tools › Annotate.
struct PDFMarkupMenuActions {
    let isRowShown: Bool
    /// False for a protected or signed PDF, which takes no marks.
    let acceptsMarkup: Bool
    let hasTextSelection: Bool
    /// The style Highlight Text uses: the highlight button's colour, or yellow while it underlines or strikes through.
    let highlightStyle: PDFMarkupStyle
    let toggleRow: () -> Void
    let markSelection: (PDFMarkupStyle) -> Void

    var canMarkSelection: Bool { acceptsMarkup && hasTextSelection }
}

extension FocusedValues {
    @Entry var pdfMarkupMenuActions: PDFMarkupMenuActions?
}

/// View › Show Markup Toolbar, dimmed while no PDF is in front.
struct PDFMarkupToolbarMenuItem: View {
    let actions: PDFMarkupMenuActions?
    let shortcut: KeyboardShortcut?

    var body: some View {
        Button(actions?.isRowShown == true ? "Hide Markup Toolbar" : "Show Markup Toolbar") { actions?.toggleRow() }
            .keyboardShortcut(shortcut)
            .disabled(actions?.acceptsMarkup != true)
    }
}

/// Tools › Annotate: marks the focused PDF's selected text.
struct PDFAnnotateMenu: View {
    let actions: PDFMarkupMenuActions?
    let shortcut: (GraphiteCommand) -> KeyboardShortcut?

    var body: some View {
        Menu("Annotate") {
            item("Highlight Text", command: .highlightPDFText, style: actions?.highlightStyle ?? .default)
            item("Underline Text", command: .underlinePDFText, style: .underline)
            item("Strikethrough Text", command: .strikethroughPDFText, style: .strikeOut)
        }
    }

    private func item(_ title: String, command: GraphiteCommand, style: PDFMarkupStyle) -> some View {
        Button(title) { actions?.markSelection(style) }
            .keyboardShortcut(shortcut(command))
            .disabled(actions?.canMarkSelection != true)
    }
}
#endif
