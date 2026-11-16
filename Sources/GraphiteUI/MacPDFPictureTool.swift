/**
 * File: MacPDFPictureTool.swift
 * -----------------------------
 * Layer: UI
 * Description: The Mac's Images tool in one PDF view: a click selects a picture on a page, a drag moves it, a corner
 *              resizes it keeping its proportions, the arrow keys nudge it and Delete removes it, each one step of
 *              the history; the row's Add Image places a chosen image on the page in view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The Images tool of the Mac's markup row in one PDF view. The selected picture is the
/// session's (`PDFSession.selectedPicture`), as on the iPad, so a picture placed by a drop or
/// by Add Image is selected here too. A drag shows the picture's frame where it goes; the
/// picture moves when the mouse is let go, as one step.
@MainActor
final class MacPDFPictureTool: NSObject {
    private weak var session: PDFSession?
    private weak var pdfView: PDFView?
    private weak var surface: NSView?
    /// The drag under way: the corner taken, or nil for a move, where it began on the page,
    /// and the frame (before the picture is turned) it puts the picture in.
    private var drag: (corner: PictureFrameCorner?, start: CGPoint, frame: CGRect)?
    private var isObservingSelection = false

    /// How near a corner a press must be to take it, in points of the screen.
    private static let reachPoints: CGFloat = 6
    private static let handleSidePoints: CGFloat = 7
    /// The narrowest side a picture can be made by its corners, in points of the page.
    static let narrowestSidePoints: CGFloat = 12
    /// How far an arrow key moves a picture, and with Shift, in points of the page.
    static let nudgePoints: CGFloat = 1
    static let largeNudgePoints: CGFloat = 10

    init(session: PDFSession, view: PDFView, surface: NSView) {
        self.session = session
        self.pdfView = view
        self.surface = surface
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(picturesDidChange), name: .NSUndoManagerDidUndoChange, object: session.undoManager)
        center.addObserver(self, selector: #selector(picturesDidChange), name: .NSUndoManagerDidRedoChange, object: session.undoManager)
        center.addObserver(self, selector: #selector(picturesDidChange), name: PDFSession.picturesDidChange, object: session)
        observeSelection()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        isObservingSelection = false
    }

    /// The tool put down ends arranging the picture.
    func toolWasPutDown() {
        drag = nil
        if session?.selectedPicture != nil { session?.selectedPicture = nil }
    }

    /// The selected picture and its page, while both still exist.
    private var selected: (selection: PDFPictureSelection, page: PDFPage, picture: PDFPicture)? {
        guard let session, let selection = session.selectedPicture, let page = selection.page.page, page.document === session.document,
              let picture = session.pictures(on: page).first(where: { picture in picture.name == selection.pictureName }) else { return nil }
        return (selection, page, picture)
    }

    /// The frame of the selected picture where it is shown now, before it is turned, for tests and the overlay.
    var shownFrame: CGRect? { drag?.frame ?? selected?.picture.bounds }

    // MARK: Adding

    /// Places an image chosen with the row's Add Image in the middle of what the view shows of
    /// the page in view, at its own size where that fits, as one step "Add Image", and selects it.
    func addPicture(fromFileAt location: URL) {
        guard let session else { return }
        Task { [weak self] in
            do {
                let imageData = try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: location) }.value
                let preferredWidth = PictureNaturalSize.measure(ofImageData: imageData)?.widthInPoints
                try await session.addPicture(imageData: imageData, placement: nil, preferredWidth: preferredWidth)
            } catch {
                session.reportFailedChange(error)
            }
            self?.surface?.needsDisplay = true
        }
    }

    // MARK: Pointer

    func cursor(atViewPoint viewPoint: CGPoint) -> NSCursor {
        if corner(at: viewPoint) != nil { return .crosshair }
        if let pagePoint = pagePoint(viewPoint, on: nil), let session, session.picture(at: pagePoint.point, on: pagePoint.page) != nil { return .openHand }
        return .arrow
    }

    func mouseDown(at viewPoint: CGPoint) {
        drag = nil
        guard let session, let pagePoint = pagePoint(viewPoint, on: nil) else { return }
        if let selected, selected.page === pagePoint.page {
            if let corner = corner(at: viewPoint) {
                drag = (corner, pagePoint.point, selected.picture.bounds)
            } else if selected.picture.contains(pagePoint.point) {
                drag = (nil, pagePoint.point, selected.picture.bounds)
            }
        }
        if drag == nil {
            let picture = session.picture(at: pagePoint.point, on: pagePoint.page)
            session.selectedPicture = picture.map { picture in PDFPictureSelection(pictureName: picture.name, page: session.historyPage(for: pagePoint.page)) }
            if let picture { drag = (nil, pagePoint.point, picture.bounds) }
        }
        surface?.needsDisplay = true
    }

    func mouseDragged(to viewPoint: CGPoint) {
        guard let selected, let drag, let pagePoint = pagePoint(viewPoint, on: selected.page) else { return }
        let frame: CGRect = if let corner = drag.corner {
            // Page coordinates count upward, where a picture turned clockwise has a negative angle.
            PictureFrameEditing.resized(selected.picture.bounds, turnedBy: -selected.picture.rotationRadians, draggingCorner: corner,
                                        to: pagePoint.point, narrowestSide: Self.narrowestSidePoints)
        } else {
            PictureFrameEditing.moved(selected.picture.bounds, by: CGVector(dx: pagePoint.point.x - drag.start.x, dy: pagePoint.point.y - drag.start.y))
        }
        self.drag = (drag.corner, drag.start, frame)
        surface?.needsDisplay = true
    }

    func mouseUp(at viewPoint: CGPoint) {
        mouseDragged(to: viewPoint)
        guard let drag else { return }
        self.drag = nil
        surface?.needsDisplay = true
        moveSelection(to: drag.frame)
    }

    // MARK: Keys and menu

    /// Delete removes the selected picture, Escape ends arranging it, and the arrow keys move
    /// it a point the way they point on screen (ten with Shift).
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let selected, let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        let step = event.modifierFlags.contains(.shift) ? Self.largeNudgePoints : Self.nudgePoints
        switch Int(key.value) {
        case NSBackspaceCharacter, NSDeleteCharacter, NSDeleteFunctionKey: deleteSelection()
        case Self.escapeCharacter: session?.selectedPicture = nil
        case NSLeftArrowFunctionKey: nudge(selected, rightward: -step, downward: 0)
        case NSRightArrowFunctionKey: nudge(selected, rightward: step, downward: 0)
        case NSUpArrowFunctionKey: nudge(selected, rightward: 0, downward: -step)
        case NSDownArrowFunctionKey: nudge(selected, rightward: 0, downward: step)
        default: return false
        }
        surface?.needsDisplay = true
        return true
    }

    private static let escapeCharacter = 0x1B

    /// The right-click menu of a picture, which it selects: Arrange, then Delete.
    func menu(atViewPoint viewPoint: CGPoint) -> NSMenu? {
        guard let session, let pagePoint = pagePoint(viewPoint, on: nil) else { return nil }
        if selected?.page !== pagePoint.page || selected?.picture.contains(pagePoint.point) != true {
            guard let picture = session.picture(at: pagePoint.point, on: pagePoint.page) else { return nil }
            session.selectedPicture = PDFPictureSelection(pictureName: picture.name, page: session.historyPage(for: pagePoint.page))
        }
        surface?.needsDisplay = true
        let menu = NSMenu()
        if let selection = session.selectedPicture, let page = selection.page.page {
            let ink = PDFInkArrangeOptions(possibleArrangements: session.possibleInkArrangements(on: page)) { [weak self] arrangement in
                self?.perform { session in try session.arrangeInk(on: page, arrangement) }
            }
            MacPDFArrangeMenuItems.add(to: menu, possibleArrangements: session.possibleArrangements(of: selection), ink: ink) { [weak self] arrangement in
                self?.arrangeSelection(arrangement)
            }
            menu.addItem(.separator())
        }
        menu.addItem(MacPDFPageToolMenuItem(title: "Delete Image") { [weak self] in self?.deleteSelection() })
        return menu
    }

    /// Brings the selected picture forward or sends it back among its page's objects.
    func arrangeSelection(_ arrangement: PDFArrangement) {
        perform { session in
            guard let selection = session.selectedPicture else { return }
            try session.arrangePicture(selection, arrangement)
        }
    }

    /// The arrangements that would move the selected picture.
    var possibleArrangementsOfSelection: Set<PDFArrangement> {
        guard let session, let selection = session.selectedPicture else { return [] }
        return session.possibleArrangements(of: selection)
    }

    private func perform(_ change: (PDFSession) throws -> Void) {
        guard let session else { return }
        do { try change(session) } catch { session.reportFailedChange(error) }
        surface?.needsDisplay = true
    }

    func deleteSelection() {
        guard let session, let selected else { return }
        do { try session.removePicture(selected.selection) } catch { session.reportFailedChange(error) }
        surface?.needsDisplay = true
    }

    private func nudge(_ selected: (selection: PDFPictureSelection, page: PDFPage, picture: PDFPicture), rightward: CGFloat, downward: CGFloat) {
        let offset = PDFShownPage.pageVector(rightward: rightward, downward: downward, quarterTurnsClockwise: ((selected.page.rotation / 90) % 4 + 4) % 4)
        moveSelection(to: PictureFrameEditing.moved(selected.picture.bounds, by: offset))
    }

    /// Moves or resizes the selected picture, one step of the history (`PDFSession.movePicture`).
    private func moveSelection(to frame: CGRect) {
        guard let session, let selected, frame != selected.picture.bounds else { return }
        do { try session.movePicture(selected.selection, to: frame) } catch { session.reportFailedChange(error) }
        surface?.needsDisplay = true
    }

    // MARK: Geometry

    /// The page under a point of the view, or `page` when given, and the point of that page.
    private func pagePoint(_ viewPoint: CGPoint, on page: PDFPage?) -> (page: PDFPage, point: CGPoint)? {
        guard let pdfView, let page = page ?? pdfView.page(for: viewPoint, nearest: false) else { return nil }
        return (page, pdfView.convert(viewPoint, to: page))
    }

    /// The corners of the selected picture's frame as turned, in the PDF view's coordinates.
    private func viewCorners(of frame: CGRect, picture: PDFPicture, on page: PDFPage) -> [(corner: PictureFrameCorner, point: CGPoint)] {
        guard let pdfView else { return [] }
        return PictureFrameCorner.allCases.map { corner in
            (corner, pdfView.convert(corner.point(of: frame, turnedBy: -picture.rotationRadians), from: page))
        }
    }

    private func corner(at viewPoint: CGPoint) -> PictureFrameCorner? {
        guard let selected else { return nil }
        return viewCorners(of: selected.picture.bounds, picture: selected.picture, on: selected.page).first { corner in
            hypot(viewPoint.x - corner.point.x, viewPoint.y - corner.point.y) <= Self.reachPoints
        }?.corner
    }

    // MARK: Following the selection

    @objc private func picturesDidChange() {
        surface?.needsDisplay = true
    }

    /// Draws again when the session's selection changes: a drop or Add Image selects the
    /// picture it placed, and a step undone can take the picture away.
    private func observeSelection() {
        isObservingSelection = true
        withObservationTracking { _ = session?.selectedPicture } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObservingSelection else { return }
                self.surface?.needsDisplay = true
                self.observeSelection()
            }
        }
    }

    // MARK: The selection's frame

    /// Draws the selected picture's frame, where a drag puts it, turned as the picture is, with a handle at each corner.
    func drawSelectionFrame(in surface: NSView, of pdfView: PDFView) {
        guard let selected, let frame = shownFrame else { return }
        let byCorner = Dictionary(uniqueKeysWithValues: viewCorners(of: frame, picture: selected.picture, on: selected.page).map { corner in
            (corner.corner, surface.convert(corner.point, from: pdfView))
        })
        let corners = [PictureFrameCorner.minimumXMinimumY, .maximumXMinimumY, .maximumXMaximumY, .minimumXMaximumY].compactMap { corner in byCorner[corner] }
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

extension PDFView {
    /// The middle of what the view shows of the page in view, in that page's coordinates,
    /// where Add Image places a picture (`PDFSession.visiblePageCenter`).
    func visiblePageCenter() -> (pageIndex: Int, center: CGPoint)? {
        guard let document, let page = currentPage else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let visibleRegion = convert(bounds, to: page).intersection(page.bounds(for: .cropBox))
        guard !visibleRegion.isNull, visibleRegion.width > 0, visibleRegion.height > 0 else { return nil }
        return (pageIndex, CGPoint(x: visibleRegion.midX, y: visibleRegion.midY))
    }
}
#endif
