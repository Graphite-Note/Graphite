/**
 * File: PDFMarkupToolbar.swift
 * ----------------------------
 * Layer: UI
 * Description: One PDF pane's markup row on the Mac: whether it shows, the tool chosen in it, the Draw tool's
 *              colour and width, the Shapes tool's look, the signature to place, and whether the PDF has text
 *              selected, for the row and the menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 16/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteApple

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
    /// The shape the Shapes tool draws next and its look, as kept on the device
    /// (`PDFAnnotationPreferenceKey.markupShapeStyle`), or the selected shape's while one is.
    private(set) var shapeStyle = PDFMarkupShapeStyle.default
    /// Whether the sheet to draw a new signature is open.
    var isCreatingSignature = false
    /// The signature chosen in the Sign menu, until the PDF view places it (`takeSignatureToPlace`).
    @ObservationIgnored private var signatureToPlace: PDFSavedSignature?
    /// Set by the PDF view's page tools: places a signature chosen while they already exist.
    @ObservationIgnored var signaturePlacementRequested: (() -> Void)?
    /// Set by the PDF view's page tools: gives the selected shape a look chosen in the row.
    @ObservationIgnored var shapeStyleChosen: ((PDFMarkupShapeStyle) -> Void)?
    /// The mark the PDF view has selected (a click on a highlight, underline or
    /// strikethrough), which the row shows and changes; nil while none is.
    private(set) var selectedMark: PDFSelectedMark?
    /// The selected mark's kind and colour as the row shows them, read again after each
    /// edit of the PDF (`selectedMarkMayHaveChanged`), so the row follows undo and redo.
    private(set) var selectedMarkAppearance: PDFSelectedMarkAppearance?
    /// Set by the PDF view's markup handling: recolours or removes the selected mark.
    @ObservationIgnored var selectedMarkChangeRequested: ((PDFSelectedMarkChange) -> Void)?

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

    func selectedMarkChanged(_ mark: PDFSelectedMark?) {
        if selectedMark != mark { selectedMark = mark }
        selectedMarkMayHaveChanged()
    }

    /// Reads the selected mark's kind and colour again, after an edit of the PDF.
    func selectedMarkMayHaveChanged() {
        let appearance = selectedMark?.appearance
        if selectedMarkAppearance != appearance { selectedMarkAppearance = appearance }
    }

    /// A colour or Remove chosen in the row for the selected mark.
    func changeSelectedMark(_ change: PDFSelectedMarkChange) {
        selectedMarkChangeRequested?(change)
    }

    func useInkStyle(_ style: PDFMarkupInkStyle) {
        if inkStyle != style { inkStyle = style }
    }

    /// Takes the style kept on the device, for the next shape.
    func useShapeStyle(_ style: PDFMarkupShapeStyle) {
        if shapeStyle != style { shapeStyle = style }
    }

    /// A style chosen in the row: for the next shape, and for the selected one.
    func chooseShapeStyle(_ style: PDFMarkupShapeStyle) {
        useShapeStyle(style)
        shapeStyleChosen?(style)
    }

    /// Shows the selected shape's look in the row, without changing the shape.
    func showShapeStyle(_ style: PDFMarkupShapeStyle) {
        useShapeStyle(style)
    }

    /// Places a signature on the PDF's page in view, choosing the Sign tool.
    func placeSignature(_ signature: PDFSavedSignature) {
        signatureToPlace = signature
        choose(.sign)
        signaturePlacementRequested?()
    }

    /// The signature waiting to be placed, given once.
    func takeSignatureToPlace() -> PDFSavedSignature? {
        defer { signatureToPlace = nil }
        return signatureToPlace
    }
}

/// A mark selected in a PDF view: the annotation and the page it is on.
struct PDFSelectedMark: Equatable {
    let annotation: PDFAnnotation
    let page: PDFPage

    /// Its kind and colour now, or nil once it is no longer on its page, as after it was
    /// removed or its making was undone. Read again after every edit of the PDF.
    var appearance: PDFSelectedMarkAppearance? {
        guard page.annotations.contains(where: { annotation in annotation === self.annotation }),
              let markup = PDFMarkup(annotation: annotation) else { return nil }
        return PDFSelectedMarkAppearance(kind: markup.kind, color: markup.color)
    }

    static func == (leftMark: Self, rightMark: Self) -> Bool {
        leftMark.annotation === rightMark.annotation && leftMark.page === rightMark.page
    }
}

/// What the markup row shows of the selected mark.
struct PDFSelectedMarkAppearance: Equatable {
    let kind: PDFMarkupKind
    let color: PDFMarkupColor
}

/// What the markup row does to the selected mark.
enum PDFSelectedMarkChange: Equatable {
    case recolor(PDFMarkupColor)
    case remove
}

extension EnvironmentValues {
    /// The markup row of the PDF pane around a PDF view, on the Mac; nil elsewhere.
    @Entry var pdfMarkupToolbar: PDFMarkupToolbar? = nil
}
