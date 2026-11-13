/**
 * File: PDFMarkupToolbar.swift
 * ----------------------------
 * Layer: UI
 * Description: One PDF pane's markup row on the Mac: whether it shows, the tool chosen in it, the Draw tool's
 *              colour and width, the Shapes tool's look, the signature to place, and whether the PDF has text
 *              selected, for the row and the menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
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

extension EnvironmentValues {
    /// The markup row of the PDF pane around a PDF view, on the Mac; nil elsewhere.
    @Entry var pdfMarkupToolbar: PDFMarkupToolbar? = nil
}
