/**
 * File: PDFTextHighlighterInteraction.swift
 * -----------------------------------------
 * Layer: UI
 * Description: Selecting PDF text by dragging on the iPad, shared by the finger's long press and the text highlighter,
 *              showing the text covered in the chosen style's colour as the touch moves, and marking the selection when
 *              the touch lifts while the text highlighter is chosen.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
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
/// the text from where it began to where it is, shown as it is covered in the style's colour (`showWhileSelecting`),
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

    /// Selects `selection` and shows it as the touch covers it, in the style's colour, until the touch lifts. PDFKit draws
    /// no selection set while a touch is down, and its highlighted selections, set at each move, left a frame with no fill
    /// between two (a simulator recording of 2026-11-17: the yellow flickered as the finger moved), redrew the page each
    /// time and are read aloud's word: so the text covered is drawn by Graphite, one layer over the PDF view, its lines'
    /// rectangles in one path, changed without animation.
    func showWhileSelecting(_ selection: PDFSelection?, style: PDFMarkupStyle) {
        guard let pdfView else { return }
        pdfView.currentSelection = selection
        guard let selection else { return stopShowingWhileSelecting() }
        coveredTextShowing += 1
        let coveredText = CGMutablePath()
        for line in selection.selectionsByLine() {
            for page in line.pages { coveredText.addRect(pdfView.convert(line.bounds(for: page), from: page)) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if coveredTextLayer.superlayer !== pdfView.layer { pdfView.layer.addSublayer(coveredTextLayer) }
        coveredTextLayer.frame = pdfView.layer.bounds
        coveredTextLayer.fillColor = Self.colorWhileSelecting(for: style).cgColor
        coveredTextLayer.path = coveredText
        CATransaction.commit()
    }

    /// The text shown while it is selected no longer is.
    func stopShowingWhileSelecting() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coveredTextLayer.path = nil
        coveredTextLayer.removeFromSuperlayer()
        CATransaction.commit()
    }

    /// Removes the text covered once PDFKit has drawn the mark made of it: removed at once, it left a frame with neither
    /// at the lift (a simulator recording of 2026-11-18). A drag begun meanwhile keeps its own.
    private func stopShowingWhileSelectingOnceMarked() {
        let showingWhenMarked = coveredTextShowing
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.coveredTextSecondsAfterMarking)) // Never cancelled; cut short, the layer only goes sooner.
            guard let self, self.coveredTextShowing == showingWhenMarked else { return }
            self.stopShowingWhileSelecting()
        }
    }

    /// How long the text covered stays over the mark made of it, a few frames.
    static let coveredTextSecondsAfterMarking: Double = 0.1

    /// Counts each showing of the text covered, so a removal planned for one leaves the next.
    private var coveredTextShowing = 0

    /// The name of the layer that shows the text covered while the touch is down, for the hosted tests.
    static let coveredTextLayerName = "Graphite.textHighlighter.coveredText"

    private lazy var coveredTextLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.name = Self.coveredTextLayerName
        // Rectangles of lines that overlap are filled once.
        layer.fillRule = .nonZero
        return layer
    }()

    /// A highlight's own colour as it will be marked, light enough to read the text through; an underline's or a
    /// strikethrough's colour, lighter.
    static func colorWhileSelecting(for style: PDFMarkupStyle) -> UIColor {
        style.kind == .highlight ? style.color.platformColor.withAlphaComponent(0.4) : style.color.platformColor.withAlphaComponent(0.2)
    }

    /// Marks the view's selection when a touch that selected it lifts, where `marksOnLift` (the text highlighter is
    /// chosen), and says whether it did; otherwise the selection stays for its menu.
    @discardableResult
    func markSelectionOnLift(style: PDFMarkupStyle, marksOnLift: Bool) -> Bool {
        guard let pdfView else { return false }
        let tool: PDFMarkupTool = marksOnLift ? .highlight : .textSelection
        let selectionHasText = !(pdfView.currentSelection?.string ?? "").isEmpty
        guard let styleToApply = tool.styleToApplyOnMouseUp(style: style, selectionHasText: selectionHasText, clickChoseExistingMark: false) else {
            stopShowingWhileSelecting()
            return false
        }
        PDFSelectionMarking.markSelection(of: pdfView, in: session, as: styleToApply)
        stopShowingWhileSelectingOnceMarked()
        return true
    }
}
#endif
