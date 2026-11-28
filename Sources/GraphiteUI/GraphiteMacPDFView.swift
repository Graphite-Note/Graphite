/**
 * File: GraphiteMacPDFView.swift
 * ------------------------------
 * Layer: UI
 * Description: The Mac's PDFView: it comes back to a place once it has a size, keeps its pages still while a row above
 *              it unfolds, and draws pictures and ink at the screen's resolution.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 28/11/2026
 */

#if os(macOS)
import SwiftUI
import PDFKit
import AppKit
import GraphiteCore
import GraphiteApple

/// The Mac's PDF view, which comes back to a place once it has a size and tells where it is,
/// and draws pictures and ink at the screen's resolution (`PDFAnnotationLayerResolution`).
final class GraphiteMacPDFView: PDFView {
    /// Where to show the PDF once laid out: PDFKit ignores a place asked for before.
    var pendingPlace: PDFPagePlace?
    /// The shown document's change count (`PDFSession.changeVersion`).
    var contentChangeCount: () -> Int = { 0 }
    lazy var annotationLayerResolution = PDFAnnotationLayerResolution(view: self) { [weak self] in self?.contentChangeCount() ?? 0 }
    /// Text markup by pointer and keyboard; owned by the view's coordinator.
    weak var markupInteraction: MacPDFMarkupInteraction?
    /// Takes pictures dropped onto the pages; nil in a PDF embedded in a note.
    var pictureDrops: MacPDFPictureDropTarget?
    /// Each page's ink drawn in one layer (`MacPDFPageInkLayers`); owned by the view's coordinator.
    weak var pageInkLayers: MacPDFPageInkLayers?
    /// The PDF's own history (`PDFSession.undoManager`), which Edit › Undo and Redo, ⌘Z and
    /// ⇧⌘Z reach while the PDF is the first responder.
    weak var documentUndoManager: UndoManager?

    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }

    // The window answers Undo and Redo with its own history, which never holds the PDF's
    // steps, so they stayed dimmed and only the toolbar undid. PDFKit's own menu validation
    // enables any action it does not know, so the items stay enabled and do nothing while
    // the history has no step to take.
    @objc func undo(_ sender: Any?) {
        guard let documentUndoManager, documentUndoManager.canUndo else { return }
        documentUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        guard let documentUndoManager, documentUndoManager.canRedo else { return }
        documentUndoManager.redo()
    }

    override func mouseDown(with event: NSEvent) {
        if markupInteraction?.handleMouseDown(event) == true {
            // PDFKit, which the click does not reach, would have taken the keyboard: Delete
            // removes the mark only while the PDF has it.
            window?.makeFirstResponder(self)
            return
        }
        super.mouseDown(with: event)
        // PDFKit may follow a drag in its own loop until the button is let go, which then
        // sends no mouse-up to the view.
        if NSEvent.pressedMouseButtons & Self.primaryMouseButtonMask == 0 { markupInteraction?.mouseUpFinished() }
    }

    private static let primaryMouseButtonMask = 1

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        markupInteraction?.mouseUpFinished()
    }

    /// A PDF embedded in a note leaves dragged files to the note (HUNT-394). PDFKit registers its view for the Finder's files
    /// even while it takes none (`acceptsDraggedFiles` is off), so a drop on an embed's page was refused before the note's
    /// own drop could take it.
    var leavesDroppedFilesToTheNote = false {
        didSet { if leavesDroppedFilesToTheNote { unregisterDraggedTypes() } }
    }

    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        guard !leavesDroppedFilesToTheNote else { return }
        super.registerForDraggedTypes(newTypes)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        pictureDrops?.draggingUpdated(sender) ?? super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        pictureDrops?.draggingUpdated(sender) ?? super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        pictureDrops?.performDrop(sender) ?? super.performDragOperation(sender)
    }

    override func keyDown(with event: NSEvent) {
        if markupInteraction?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let defaultMenu = super.menu(for: event)
        return markupInteraction.map { interaction in interaction.menu(for: event, defaultMenu: defaultMenu) } ?? defaultMenu
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { annotationLayerResolution.stop() } else { annotationLayerResolution.start() }
    }

    /// The page at the top edge and how far down it the edge is, measured on the page as
    /// shown. Nil before the view has shown its first place.
    var pagePlace: PDFPagePlace? {
        guard pendingPlace == nil, bounds.height > 0, let document else { return nil }
        let topPoint = NSPoint(x: bounds.midX, y: isFlipped ? bounds.minY + 1 : bounds.maxY - 1)
        guard let page = page(for: topPoint, nearest: true) else { return nil }
        let pageIndex = document.index(for: page)
        let pageRect = convert(page.bounds(for: displayBox), from: page)
        guard pageIndex != NSNotFound, pageRect.height > 0 else { return nil }
        let distanceFromTop = isFlipped ? topPoint.y - pageRect.minY : pageRect.maxY - topPoint.y
        return PDFPagePlace(pageIndex: pageIndex, fractionFromTop: Double(min(max(distanceFromTop / pageRect.height, -0.2), 1)))
    }

    /// Keeps the pages still on screen while the markup row or a banner is shown or hidden above the view.
    private lazy var pagesHeldStill = MacPDFPagesHeldStill(view: self)

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        pagesHeldStill.viewWillMove()
        super.setFrameOrigin(newOrigin)
    }

    override func setFrameSize(_ newSize: NSSize) {
        pagesHeldStill.viewWillMove()
        super.setFrameSize(newSize)
    }

    override func layout() {
        super.layout()
        defer { pagesHeldStill.viewDidLayOut() }
        guard let place = pendingPlace, bounds.width > 0, bounds.height > 0, let page = document?.page(at: place.pageIndex) else { return }
        pendingPlace = nil
        go(to: page)
        guard place.fractionFromTop > 0 else { return }
        // The point that far down the page as shown, in the page's own space, which a
        // destination takes whatever the page's rotation.
        layoutDocumentView()
        let pageRect = convert(page.bounds(for: displayBox), from: page)
        let viewY = isFlipped ? pageRect.minY + CGFloat(place.fractionFromTop) * pageRect.height
                              : pageRect.maxY - CGFloat(place.fractionFromTop) * pageRect.height
        go(to: PDFDestination(page: page, at: convert(NSPoint(x: pageRect.minX, y: viewY), to: page)))
    }
}
#endif
