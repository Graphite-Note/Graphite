/**
 * File: PDFMarkupToolbarRow.swift
 * -------------------------------
 * Layer: UI
 * Description: The Mac's markup row under a PDF's toolbar, as in Preview: the markup button that shows it, its
 *              tools and their choices laid out in the row, folded into menus only where the pane is too narrow,
 *              and the pane's part that adds the row and serves the menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 13/11/2026
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

/// How much of the markup row is folded into menus, from none in a wide pane to all in a narrow one.
enum PDFMarkupRowFolding: Int, CaseIterable, Comparable {
    /// Every tool and every choice is a button of the row.
    case none
    /// The chosen tool's choices (ink colours, text format) are menus.
    case options
    /// The highlight colours are one menu as well.
    case highlightColors
    /// The tools are one menu too.
    case tools

    static func < (leftFolding: Self, rightFolding: Self) -> Bool { leftFolding.rawValue < rightFolding.rawValue }
}

/// The markup row under the toolbar. Its tools and their choices are buttons laid out in
/// the row, as the owner asked (2026-11-13): Text Selection; the highlight colours,
/// Underline and Strikethrough; Draw and Eraser; Text Box; then the chosen tool's choices.
/// Where the pane is too narrow for all of them, the choices fold into menus first, then
/// the highlight colours, then the tools (`PDFMarkupRowFolding`).
struct PDFMarkupToolbarRow: View {
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    @Binding var inkStyle: PDFMarkupInkStyle
    let textFormat: PDFMarkupTextFormatSource
    let markSelection: (PDFMarkupStyle) -> Void

    static let rowHeight: CGFloat = 34
    private static let horizontalPadding: CGFloat = 10

    var body: some View {
        // The first layout that fits the pane's width, from none folded to all.
        ViewThatFits(in: .horizontal) {
            ForEach(PDFMarkupRowFolding.allCases, id: \.self) { folding in
                PDFMarkupRowContent(toolbar: toolbar, style: $style, inkStyle: $inkStyle, textFormat: textFormat, markSelection: markSelection,
                                    folding: folding)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(height: Self.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The markup row's tools and choices laid out with some of them folded into menus.
struct PDFMarkupRowContent: View {
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    @Binding var inkStyle: PDFMarkupInkStyle
    let textFormat: PDFMarkupTextFormatSource
    let markSelection: (PDFMarkupStyle) -> Void
    let folding: PDFMarkupRowFolding

    var body: some View {
        HStack(spacing: PDFMarkupRowMetrics.groupSpacing) {
            if folding >= .tools {
                PDFMarkupToolMenu(toolbar: toolbar, style: $style, markSelection: markSelection)
            } else {
                PDFMarkupToolButton(tool: .textSelection, toolbar: toolbar)
                groupDivider
                PDFMarkupTextMarkButtons(toolbar: toolbar, style: $style, foldsColors: folding >= .highlightColors, markSelection: markSelection)
                groupDivider
                PDFMarkupToolButton(tool: .draw, toolbar: toolbar)
                PDFMarkupToolButton(tool: .eraseInk, toolbar: toolbar)
                groupDivider
                PDFMarkupToolButton(tool: .textBox, toolbar: toolbar)
            }
            options
        }
        .fixedSize()
    }

    @ViewBuilder private var options: some View {
        switch toolbar.tool {
        case .draw:
            groupDivider
            PDFMarkupInkOptions(inkStyle: $inkStyle, isFolded: folding >= .options)
        case .textBox:
            groupDivider
            PDFMarkupTextFormatControls(source: textFormat, isFolded: folding >= .options)
        case .textSelection, .highlight, .eraseInk:
            EmptyView()
        }
    }

    private var groupDivider: some View {
        Divider().frame(height: PDFMarkupRowMetrics.dividerHeight)
    }
}

/// The sizes the markup row's controls share.
enum PDFMarkupRowMetrics {
    static let toolSide: CGFloat = 26
    static let swatchSide: CGFloat = 14
    static let chosenRingSide: CGFloat = 20
    static let chosenCornerRadius: CGFloat = 6
    static let chosenOpacity = 0.14
    static let groupSpacing: CGFloat = 6
    static let itemSpacing: CGFloat = 2
    static let dividerHeight: CGFloat = 18
    static let swatchEdgeOpacity = 0.25

    /// The faint fill behind the chosen tool, as the toolbar marks a button that is on.
    static func chosenBackground(_ isChosen: Bool) -> some View {
        RoundedRectangle(cornerRadius: chosenCornerRadius).fill(Color.primary.opacity(isChosen ? chosenOpacity : 0))
    }
}

/// One tool of the row as a button, with a faint fill while it is chosen.
struct PDFMarkupToolButton: View {
    let tool: PDFMarkupTool
    let toolbar: PDFMarkupToolbar

    var body: some View {
        Button { toolbar.choose(tool) } label: {
            Image(systemName: tool.symbolName)
                .frame(width: PDFMarkupRowMetrics.toolSide, height: PDFMarkupRowMetrics.toolSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .background(PDFMarkupRowMetrics.chosenBackground(toolbar.tool == tool))
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(toolbar.tool == tool ? .isSelected : [])
    }
}

/// A round swatch of a colour, ringed while it is the one in use.
struct PDFMarkupSwatch: View {
    let color: Color
    let isInUse: Bool

    var body: some View {
        Circle().fill(color)
            .frame(width: PDFMarkupRowMetrics.swatchSide, height: PDFMarkupRowMetrics.swatchSide)
            .overlay { Circle().strokeBorder(Color.primary.opacity(PDFMarkupRowMetrics.swatchEdgeOpacity), lineWidth: 0.5) }
            .overlay {
                if isInUse {
                    Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                        .frame(width: PDFMarkupRowMetrics.chosenRingSide, height: PDFMarkupRowMetrics.chosenRingSide)
                }
            }
            .frame(width: PDFMarkupRowMetrics.toolSide - 4, height: PDFMarkupRowMetrics.toolSide)
            .contentShape(Rectangle())
    }
}

/// The text marks: a swatch per highlight colour, and Underline and Strikethrough buttons.
/// A click chooses the mark, marks the text selected and leaves the highlighter on, so text
/// selected next is marked the same way when the mouse is let go.
struct PDFMarkupTextMarkButtons: View {
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    let foldsColors: Bool
    let markSelection: (PDFMarkupStyle) -> Void

    var body: some View {
        HStack(spacing: PDFMarkupRowMetrics.itemSpacing) {
            if foldsColors {
                colorMenu
            } else {
                ForEach(PDFMarkupColor.highlightColors) { color in colorButton(color) }
            }
            markButton(.underline)
            markButton(.strikeOut)
        }
        .padding(.horizontal, 2)
        .background(PDFMarkupRowMetrics.chosenBackground(toolbar.tool == .highlight))
    }

    private func choose(_ chosenStyle: PDFMarkupStyle) {
        style = chosenStyle
        toolbar.choose(.highlight)
        markSelection(chosenStyle)
    }

    private func colorButton(_ color: PDFMarkupColor) -> some View {
        let isInUse = style == .highlight(color)
        return Button { choose(.highlight(color)) } label: {
            PDFMarkupSwatch(color: Color(nsColor: color.platformColor), isInUse: isInUse)
        }
        .buttonStyle(.plain)
        .help("Highlight \(color.title)")
        .accessibilityLabel("Highlight \(color.title)")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    /// The colours folded into one button: a click marks with the colour in use, the arrow chooses another.
    private var colorMenu: some View {
        let currentColor: PDFMarkupColor = if case .highlight(let color) = style { color } else { .yellow }
        return Menu {
            ForEach(PDFMarkupColor.highlightColors) { color in
                Button {
                    choose(.highlight(color))
                } label: {
                    Label { Text(color.title) } icon: { Image(nsImage: MacPDFMarkupInteraction.swatch(color.platformColor)) }
                }
            }
        } label: {
            Image(nsImage: MacPDFMarkupInteraction.swatch(currentColor.platformColor))
        } primaryAction: {
            choose(.highlight(currentColor))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Highlight \(currentColor.title)")
        .accessibilityLabel("Highlight Colors")
    }

    private func markButton(_ markStyle: PDFMarkupStyle) -> some View {
        let isInUse = style == markStyle
        return Button { choose(markStyle) } label: {
            Image(systemName: markStyle.symbolName)
                .foregroundStyle(Color(nsColor: markStyle.color.platformColor))
                .frame(width: PDFMarkupRowMetrics.toolSide, height: PDFMarkupRowMetrics.toolSide)
                .background(PDFMarkupRowMetrics.chosenBackground(isInUse))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(markStyle.title)
        .accessibilityLabel(markStyle.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }
}

/// Every tool in one menu, for a pane too narrow for the row's buttons; its label is the tool chosen.
struct PDFMarkupToolMenu: View {
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    let markSelection: (PDFMarkupStyle) -> Void

    var body: some View {
        Menu {
            Button(PDFMarkupTool.textSelection.title, systemImage: PDFMarkupTool.textSelection.symbolName) { toolbar.choose(.textSelection) }
            Section {
                ForEach(PDFMarkupStyle.choices) { choice in
                    Button {
                        style = choice
                        toolbar.choose(.highlight)
                        markSelection(choice)
                    } label: {
                        Label { Text(choice.kind == .highlight ? "Highlight \(choice.title)" : choice.title) } icon: { styleIcon(choice) }
                    }
                }
            }
            Section {
                ForEach([PDFMarkupTool.draw, .eraseInk, .textBox], id: \.self) { tool in
                    Button(tool.title, systemImage: tool.symbolName) { toolbar.choose(tool) }
                }
            }
        } label: {
            Label(toolbar.tool.title, systemImage: toolbar.tool.symbolName).labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Markup Tools")
    }

    /// A highlight's swatch, or the symbol of an underline or strikethrough, which the menu tints as its text.
    @ViewBuilder private func styleIcon(_ style: PDFMarkupStyle) -> some View {
        switch style {
        case .highlight(let color): Image(nsImage: MacPDFMarkupInteraction.swatch(color.platformColor))
        case .underline, .strikeOut: Image(systemName: style.symbolName)
        }
    }
}

/// A PDF pane's markup on the Mac: the row above the pages, the row for the PDF view
/// below it, and the commands of the menu bar while the pane is focused.
struct PDFMarkupControls: ViewModifier {
    let session: PDFSession
    let toolbar: PDFMarkupToolbar
    @Binding var style: PDFMarkupStyle
    @Binding var inkStyle: PDFMarkupInkStyle
    let isFocused: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if toolbar.isRowShown && !session.isProtected {
                PDFMarkupToolbarRow(toolbar: toolbar, style: $style, inkStyle: $inkStyle, textFormat: PDFMarkupTextFormatSource(session: session),
                                    markSelection: markSelection)
            }
            content
        }
        .environment(\.pdfMarkupToolbar, toolbar)
        .focusedSceneValue(\.pdfMarkupMenuActions, isFocused ? menuActions : nil)
        // The PDF view's Draw tool reads the style from the row's model when a stroke begins.
        .onChange(of: inkStyle, initial: true) { toolbar.useInkStyle(inkStyle) }
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
