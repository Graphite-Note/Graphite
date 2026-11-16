/**
 * File: PDFTextHighlighterInteraction.swift
 * -----------------------------------------
 * Layer: UI
 * Description: Selecting PDF text by dragging on the iPad, shared by the finger's long press and the text highlighter,
 *              and marking the selection when the touch lifts while the text highlighter is chosen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteApple

/// A text selection dragged on a PDF view: from the word where the touch began to where it is now, across pages. The
/// finger's long press and the text highlighter select the same way. It asks the PDF view, so it lives on the main actor.
@MainActor
struct PDFTextSelectionDrag {
    let anchorPage: PDFPage
    /// Where the touch began, in the page's coordinates.
    let anchorPoint: CGPoint

    /// A drag begun at `viewPoint`, on the page there or the nearest one; nil where the view shows no page.
    init?(startingAt viewPoint: CGPoint, in pdfView: PDFView) {
        guard let page = pdfView.page(for: viewPoint, nearest: true) else { return nil }
        anchorPage = page
        anchorPoint = pdfView.convert(viewPoint, to: page)
    }

    /// The word where the drag began, the selection shown before the touch moves; nil off text.
    var anchorWord: PDFSelection? { anchorPage.selectionForWord(at: anchorPoint) }

    /// The text from the drag's first word to `viewPoint`; nil where that selects no text.
    func selection(extendedTo viewPoint: CGPoint, in pdfView: PDFView) -> PDFSelection? {
        guard let document = pdfView.document, let page = pdfView.page(for: viewPoint, nearest: true) else { return nil }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        let rangeSelection = document.selection(from: anchorPage, at: anchorPoint, to: page, at: pagePoint)
        if let anchorWord { rangeSelection?.add(anchorWord) }
        guard let rangeSelection, !(rangeSelection.string ?? "").isEmpty else { return nil }
        return rangeSelection
    }
}

/// The text highlighter of a PDF view on the iPad (`PencilToolKind.textHighlighter`): a drag on a page's canvas selects
/// the text from where it began to where it is, and lifting marks the selection in the style chosen on the bar, as one
/// step of the PDF's history, then clears it. The decision to mark on lift is the Mac highlighter's
/// (`PDFMarkupTool.styleToApplyOnMouseUp`); the marking is `PDFSelectionMarking`'s, as for the selection menu.
@MainActor
final class PDFTextHighlighterInteraction {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    private var drag: PDFTextSelectionDrag?

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
    }

    /// Follows one drag of the tool, in the window's points; marks with `style` when it lifts.
    func handle(_ dragEvent: TextHighlighterDrag, style: PDFMarkupStyle) {
        guard let pdfView else { return }
        switch dragEvent {
        case .began(let startPoint, let currentPoint):
            drag = PDFTextSelectionDrag(startingAt: pdfView.convert(startPoint, from: nil), in: pdfView)
            pdfView.currentSelection = drag?.anchorWord
            extend(to: currentPoint, in: pdfView)
        case .moved(let windowPoint):
            extend(to: windowPoint, in: pdfView)
        case .lifted:
            guard drag != nil else { return }
            drag = nil
            markSelectionOnLift(style: style, marksOnLift: true)
        case .cancelled:
            guard drag != nil else { return }
            drag = nil
            pdfView.clearSelection()
        }
    }

    private func extend(to windowPoint: CGPoint, in pdfView: PDFView) {
        guard let drag, let selection = drag.selection(extendedTo: pdfView.convert(windowPoint, from: nil), in: pdfView) else { return }
        pdfView.currentSelection = selection
    }

    /// Marks the view's selection when a touch that selected it lifts, where `marksOnLift` (the text highlighter is
    /// chosen), and says whether it did; otherwise the selection stays for its menu.
    @discardableResult
    func markSelectionOnLift(style: PDFMarkupStyle, marksOnLift: Bool) -> Bool {
        guard let pdfView else { return false }
        let tool: PDFMarkupTool = marksOnLift ? .highlight : .textSelection
        let selectionHasText = !(pdfView.currentSelection?.string ?? "").isEmpty
        guard let styleToApply = tool.styleToApplyOnMouseUp(style: style, selectionHasText: selectionHasText, clickChoseExistingMark: false) else {
            return false
        }
        PDFSelectionMarking.markSelection(of: pdfView, in: session, as: styleToApply)
        return true
    }
}
#endif
