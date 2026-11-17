/**
 * File: PDFTextHighlighterInteraction.swift
 * -----------------------------------------
 * Layer: UI
 * Description: Selecting PDF text by dragging on the iPad, shared by the finger's long press and the text highlighter,
 *              showing the text covered in the chosen style's colour as the touch moves, and marking the selection when
 *              the touch lifts while the text highlighter is chosen.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
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
/// the text from where it began to where it is, shown as it is covered in the style's colour (PDFKit does not draw a
/// selection set during the drag: the owner's iPad and a simulator recording showed nothing until the lift, 2026-11-17),
/// and lifting marks the selection in the style chosen on the bar, as one step of the PDF's history, then clears it.
/// The decision to mark on lift is the Mac highlighter's
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
            showWhileSelecting(drag?.anchorWord, style: style)
            extend(to: currentPoint, in: pdfView, style: style)
        case .moved(let windowPoint):
            extend(to: windowPoint, in: pdfView, style: style)
        case .lifted:
            guard drag != nil else { return }
            drag = nil
            markSelectionOnLift(style: style, marksOnLift: true)
        case .cancelled:
            guard drag != nil else { return }
            drag = nil
            stopShowingWhileSelecting()
            pdfView.clearSelection()
        case .tapped:
            // A tap selects nothing; the coordinator offers the menu of a mark tapped.
            break
        }
    }

    private func extend(to windowPoint: CGPoint, in pdfView: PDFView, style: PDFMarkupStyle) {
        guard let drag, let selection = drag.selection(extendedTo: pdfView.convert(windowPoint, from: nil), in: pdfView) else { return }
        showWhileSelecting(selection, style: style)
    }

    /// Selects `selection` and shows it as the touch covers it, in the style's colour, until the touch lifts: PDFKit draws
    /// its highlighted selections in their own colours, which it does not do for a selection set while a touch is down.
    func showWhileSelecting(_ selection: PDFSelection?, style: PDFMarkupStyle) {
        guard let pdfView else { return }
        pdfView.currentSelection = selection
        guard let selection else {
            pdfView.highlightedSelections = nil
            return
        }
        selection.color = Self.colorWhileSelecting(for: style)
        pdfView.highlightedSelections = [selection]
    }

    /// The text shown while it is selected no longer is.
    func stopShowingWhileSelecting() {
        pdfView?.highlightedSelections = nil
    }

    /// A highlight's own colour as it will be marked; an underline's or a strikethrough's colour, lighter, behind the text.
    static func colorWhileSelecting(for style: PDFMarkupStyle) -> UIColor {
        style.kind == .highlight ? style.color.platformColor.withAlphaComponent(0.6) : style.color.platformColor.withAlphaComponent(0.25)
    }

    /// Marks the view's selection when a touch that selected it lifts, where `marksOnLift` (the text highlighter is
    /// chosen), and says whether it did; otherwise the selection stays for its menu.
    @discardableResult
    func markSelectionOnLift(style: PDFMarkupStyle, marksOnLift: Bool) -> Bool {
        guard let pdfView else { return false }
        stopShowingWhileSelecting()
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
