/**
 * File: MacPDFSignatureTool.swift
 * -------------------------------
 * Layer: UI
 * Description: The Mac's Sign tool in one PDF view: places a signature from the row's Sign menu as ink on the page in
 *              view, and moves, resizes by its corners and deletes a placed signature, each one step of the history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteApple

/// The Sign tool of the Mac's markup row in one PDF view. A placed signature is the page's
/// ink (`PDFSignatureInk`); while the tool is chosen, a press on ink selects the strokes
/// placed with it, which a drag moves, a corner resizes and Delete removes.
@MainActor
final class MacPDFSignatureTool: NSObject {
    private weak var session: PDFSession?
    private weak var pdfView: PDFView?
    private weak var surface: NSView?
    /// The selected placement: its page, the date its strokes share, and their frame in the
    /// page's drawing space, read again after each change of the page.
    private var selection: (page: PDFPage, creationDate: Date, frame: CGRect)?
    /// The drag under way: the corner taken, or nil for a move, where it began in the
    /// drawing space, and the frame it puts the signature in.
    private var drag: (corner: PDFSignatureCorner?, start: CGPoint, frame: CGRect)?
    /// The wall clock, for the date the strokes of a new placement share.
    private let currentDate: () -> Date

    /// How near a corner a press must be to take it, and how near ink to select it, in points of the screen.
    private static let reachPoints: CGFloat = 6
    private static let handleSidePoints: CGFloat = 7

    init(session: PDFSession, view: PDFView, surface: NSView, currentDate: @escaping () -> Date) {
        self.session = session
        self.pdfView = view
        self.surface = surface
        self.currentDate = currentDate
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(historyDidStep), name: .NSUndoManagerDidUndoChange, object: session.undoManager)
        center.addObserver(self, selector: #selector(historyDidStep), name: .NSUndoManagerDidRedoChange, object: session.undoManager)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    func toolWasPutDown() {
        selection = nil
        drag = nil
    }

    /// The frame of the selected signature in the page's drawing space, for tests and the overlay.
    var selectedFrame: CGRect? { selection?.frame }

    // MARK: Placing

    /// Places a signature in the middle of the PDF view's page in view, as one step named
    /// "Add Signature", and selects it.
    func place(_ signature: PDFSavedSignature) {
        guard let session, let pdfView else { return }
        let viewMiddle = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        guard let page = pdfView.page(for: viewMiddle, nearest: true) else { return }
        do {
            let coordinates = try PDFPointerInk.coordinates(of: page.bounds(for: .cropBox))
            let center = coordinates.overlayPoint(fromPDF: pdfView.convert(viewMiddle, to: page))
            let frame = PDFSignatureInk.placedFrame(forSignatureOf: signature.drawing.bounds.size, centeredAt: center, pageSize: coordinates.overlaySize)
            guard !frame.isNull else { return }
            let creationDate = currentDate()
            let ink = try session.pointerInk(on: page, cached: nil)
            let strokes = PDFSignatureInk.strokes(of: signature.drawing, filling: frame, creationDate: creationDate)
            _ = try session.replacePointerInk(ink, with: PKDrawing(strokes: ink.drawing.strokes + strokes), on: page, actionName: "Add Signature")
            select(on: page, creationDate: creationDate)
        } catch {
            session.reportFailedChange(error)
        }
    }

    // MARK: Pointer

    func cursor(atViewPoint viewPoint: CGPoint) -> NSCursor {
        if corner(at: viewPoint) != nil { return .crosshair }
        if let selection, let point = drawingPoint(viewPoint, on: selection.page), selection.frame.contains(point) { return .openHand }
        return .arrow
    }

    func mouseDown(at viewPoint: CGPoint) {
        drag = nil
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false), let point = drawingPoint(viewPoint, on: page) else { return }
        if let selection, selection.page === page {
            if let corner = corner(at: viewPoint) {
                drag = (corner, point, selection.frame)
            } else if selection.frame.contains(point) {
                drag = (nil, point, selection.frame)
            }
        }
        if drag == nil {
            selection = nil
            if let creationDate = creationDateOfInk(at: point, on: page) {
                select(on: page, creationDate: creationDate)
                if let frame = selection?.frame { drag = (nil, point, frame) }
            }
        }
        surface?.needsDisplay = true
    }

    func mouseDragged(to viewPoint: CGPoint) {
        guard let selection, let drag, let point = drawingPoint(viewPoint, on: selection.page) else { return }
        let frame: CGRect = if let corner = drag.corner {
            PDFSignatureInk.resized(selection.frame, draggingCorner: corner, to: point)
        } else {
            selection.frame.offsetBy(dx: point.x - drag.start.x, dy: point.y - drag.start.y)
        }
        self.drag = (drag.corner, drag.start, frame)
        surface?.needsDisplay = true
    }

    func mouseUp(at viewPoint: CGPoint) {
        mouseDragged(to: viewPoint)
        guard let drag, let selection else { return }
        self.drag = nil
        surface?.needsDisplay = true
        guard drag.frame != selection.frame else { return }
        changeSelection(to: drag.frame, actionName: drag.corner == nil ? "Move Signature" : "Resize Signature")
    }

    // MARK: Keys and menu

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard selection != nil, let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        switch Int(key.value) {
        case NSBackspaceCharacter, NSDeleteCharacter, NSDeleteFunctionKey: deleteSelection()
        case Self.escapeCharacter: selection = nil
        default: return false
        }
        surface?.needsDisplay = true
        return true
    }

    private static let escapeCharacter = 0x1B

    func menu(atViewPoint viewPoint: CGPoint) -> NSMenu? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false), let point = drawingPoint(viewPoint, on: page) else { return nil }
        if selection?.page !== page || selection?.frame.contains(point) != true {
            guard let creationDate = creationDateOfInk(at: point, on: page) else { return nil }
            select(on: page, creationDate: creationDate)
        }
        surface?.needsDisplay = true
        let menu = NSMenu()
        menu.addItem(MacPDFPageToolMenuItem(title: "Delete") { [weak self] in self?.deleteSelection() })
        return menu
    }

    func deleteSelection() {
        guard selection != nil else { return }
        changeSelection(to: nil, actionName: "Delete Signature")
        selection = nil
        surface?.needsDisplay = true
    }

    // MARK: Ink

    private func changeSelection(to newFrame: CGRect?, actionName: String) {
        guard let session, let selection else { return }
        do {
            let ink = try session.pointerInk(on: selection.page, cached: nil)
            let drawing = PDFSignatureInk.drawing(ink.drawing, movingStrokesCreatedAt: selection.creationDate, from: selection.frame, to: newFrame)
            _ = try session.replacePointerInk(ink, with: drawing, on: selection.page, actionName: actionName)
            if newFrame != nil { select(on: selection.page, creationDate: selection.creationDate) }
        } catch {
            session.reportFailedChange(error)
        }
    }

    private func select(on page: PDFPage, creationDate: Date) {
        guard let ink = pageInk(on: page),
              let frame = PDFSignatureInk.frame(ofStrokesCreatedAt: creationDate, in: ink.drawing) else {
            selection = nil
            return
        }
        selection = (page, creationDate, frame)
    }

    /// The date of the topmost stroke at a point of the page's drawing space, which its placement's strokes share.
    private func creationDateOfInk(at point: CGPoint, on page: PDFPage) -> Date? {
        guard let pdfView, let ink = pageInk(on: page) else { return nil }
        let reach = Self.reachPoints / max(pdfView.scaleFactor, 0.01)
        guard let index = PDFPointerInk.indicesOfStrokes(in: ink.drawing, touching: point, reach: reach).first else { return nil }
        return ink.drawing.strokes[index].path.creationDate
    }

    /// The page's ink, or nil when its record cannot be read: then no placement is on it to select.
    private func pageInk(on page: PDFPage) -> PDFPointerPageInk? {
        try? session?.pointerInk(on: page, cached: nil) // Unreadable ink has no placement to select.
    }

    private func coordinates(of page: PDFPage) -> PageCoordinates? {
        try? PDFPointerInk.coordinates(of: page.bounds(for: .cropBox)) // A page with no size has no point.
    }

    private func drawingPoint(_ viewPoint: CGPoint, on page: PDFPage) -> CGPoint? {
        guard let pdfView, let coordinates = coordinates(of: page) else { return nil }
        return coordinates.overlayPoint(fromPDF: pdfView.convert(viewPoint, to: page))
    }

    private func viewPoint(_ drawingPoint: CGPoint, on page: PDFPage) -> CGPoint? {
        guard let pdfView, let coordinates = coordinates(of: page) else { return nil }
        return pdfView.convert(coordinates.pdfPoint(fromOverlay: drawingPoint), from: page)
    }

    private func corner(at viewPoint: CGPoint) -> PDFSignatureCorner? {
        guard let selection else { return nil }
        return PDFSignatureCorner.allCases.first { corner in
            guard let center = self.viewPoint(corner.point(of: selection.frame), on: selection.page) else { return false }
            return hypot(viewPoint.x - center.x, viewPoint.y - center.y) <= Self.reachPoints
        }
    }

    @objc private func historyDidStep() {
        if let selection { select(on: selection.page, creationDate: selection.creationDate) }
        surface?.needsDisplay = true
    }

    // MARK: The selection's frame

    /// Draws the selected signature's frame, where a drag puts it, with a handle at each corner.
    func drawSelectionFrame(in surface: NSView, of pdfView: PDFView) {
        guard let selection else { return }
        let frame = drag?.frame ?? selection.frame
        let corners = [PDFSignatureCorner.topLeft, .topRight, .bottomRight, .bottomLeft].compactMap { corner in
            viewPoint(corner.point(of: frame), on: selection.page).map { point in surface.convert(point, from: pdfView) }
        }
        guard corners.count == 4 else { return }
        let outline = NSBezierPath()
        outline.move(to: corners[0])
        for corner in corners.dropFirst() { outline.line(to: corner) }
        outline.close()
        outline.lineWidth = 1
        outline.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        outline.stroke()
        for center in corners {
            let side = Self.handleSidePoints
            let handle = NSBezierPath(ovalIn: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.stroke()
        }
    }
}
#endif
