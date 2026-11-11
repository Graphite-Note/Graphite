/**
 * File: PDFMarkupToolbarRow.swift
 * -------------------------------
 * Layer: UI
 * Description: The Mac's markup row under a PDF's toolbar, as in Preview: the markup button that shows it, its
 *              tools, and the pane's part that adds the row and serves the menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import SwiftUI
import AppKit
import GraphiteApple

/// The markup button of a PDF's toolbar, which shows and hides the markup row. A protected
/// or signed PDF takes no marks; the button says so.
struct PDFMarkupToolbarButton: View {
    let toolbar: PDFMarkupToolbar
    let isProtected: Bool

    var body: some View {
        Button(toolbar.isRowShown ? "Hide Markup Toolbar" : "Show Markup Toolbar", systemImage: "pencil.tip.crop.circle") {
            toolbar.toggleRow()
        }
        .symbolVariant(toolbar.isRowShown ? .fill : .none)
        .disabled(isProtected)
        .help(isProtected ? "This PDF is protected or signed, so it can't be marked up." : toolbar.isRowShown ? "Hide Markup Toolbar" : "Show Markup Toolbar")
    }
}

/// The markup row under the toolbar: Text Selection, and Highlight, whose arrow chooses the mark it makes.
struct PDFMarkupToolbarRow: View {
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    let markSelection: (PDFMarkupStyle) -> Void

    private static let rowHeight: CGFloat = 34
    private static let toolSide: CGFloat = 28
    private static let chosenToolCornerRadius: CGFloat = 6
    private static let chosenToolOpacity = 0.12
    private static let horizontalPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 4) {
            toolButton(.textSelection)
            highlightButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(height: Self.rowHeight)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func toolButton(_ tool: PDFMarkupTool) -> some View {
        Button { toolbar.choose(tool) } label: {
            Image(systemName: tool.symbolName)
                .frame(width: Self.toolSide, height: Self.toolSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .background(chosenBackground(for: tool))
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(toolbar.tool == tool ? .isSelected : [])
    }

    /// A click chooses the highlighter and marks the selection; the arrow chooses the mark.
    private var highlightButton: some View {
        Menu {
            Picker("Mark", selection: styleChoosingHighlighter) {
                ForEach(PDFMarkupStyle.choices) { choice in
                    Label {
                        Text(choice.title)
                    } icon: {
                        if let image = MacPDFMarkupInteraction.image(for: choice) { Image(nsImage: image) }
                    }
                    .tag(choice)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(nsImage: Self.highlighterIcon(for: style))
        } primaryAction: {
            toolbar.choose(.highlight)
            markSelection(style)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .frame(height: Self.toolSide)
        .padding(.horizontal, 4)
        .background(chosenBackground(for: .highlight))
        .help("Highlight: \(style.title)")
        .accessibilityLabel("Highlight, \(style.title)")
        .accessibilityAddTraits(toolbar.tool == .highlight ? .isSelected : [])
    }

    /// Choosing a mark also chooses the highlighter, as in Preview.
    private var styleChoosingHighlighter: Binding<PDFMarkupStyle> {
        Binding(get: { style }, set: { chosenStyle in
            style = chosenStyle
            toolbar.choose(.highlight)
        })
    }

    private func chosenBackground(for tool: PDFMarkupTool) -> some View {
        RoundedRectangle(cornerRadius: Self.chosenToolCornerRadius)
            .fill(Color.primary.opacity(toolbar.tool == tool ? Self.chosenToolOpacity : 0))
    }

    private static let iconSide: CGFloat = 18
    private static let iconSymbolPointSize: CGFloat = 13
    private static let styleBarHeight: CGFloat = 3
    private static let styleBarInset: CGFloat = 1

    /// The kind of mark's symbol over a bar of its colour, as Preview's button shows its colour.
    static func highlighterIcon(for style: PDFMarkupStyle) -> NSImage {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: iconSymbolPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))
        let symbol = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: style.title)?.withSymbolConfiguration(symbolConfiguration)
        let icon = NSImage(size: NSSize(width: iconSide, height: iconSide), flipped: false) { rectangle in
            if let symbol {
                let symbolOrigin = NSPoint(x: (rectangle.width - symbol.size.width) / 2,
                                           y: styleBarHeight + (rectangle.height - styleBarHeight - symbol.size.height) / 2)
                symbol.draw(in: NSRect(origin: symbolOrigin, size: symbol.size))
            }
            style.color.platformColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: styleBarInset, y: 0, width: rectangle.width - 2 * styleBarInset, height: styleBarHeight),
                         xRadius: styleBarInset, yRadius: styleBarInset).fill()
            return true
        }
        icon.accessibilityDescription = style.title
        return icon
    }
}

/// A PDF pane's markup on the Mac: the row above the pages, the row for the PDF view
/// below it, and the commands of the menu bar while the pane is focused.
struct PDFMarkupControls: ViewModifier {
    let session: PDFSession
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    let isFocused: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if toolbar.isRowShown && !session.isProtected {
                PDFMarkupToolbarRow(toolbar: toolbar, style: $style, markSelection: markSelection)
            }
            content
        }
        .environment(\.pdfMarkupToolbar, toolbar)
        .focusedSceneValue(\.pdfMarkupMenuActions, isFocused ? menuActions : nil)
    }

    private func markSelection(_ style: PDFMarkupStyle) {
        guard let view = session.pdfView else { return }
        PDFSelectionMarking.markSelection(of: view, in: session, as: style)
    }

    private var menuActions: PDFMarkupMenuActions {
        let highlightStyle: PDFMarkupStyle = if case .highlight = style { style } else { .default }
        return PDFMarkupMenuActions(isRowShown: toolbar.isRowShown, acceptsMarkup: !session.isProtected, hasTextSelection: toolbar.hasTextSelection,
                                    highlightStyle: highlightStyle, toggleRow: toolbar.toggleRow, markSelection: markSelection)
    }
}
#endif
