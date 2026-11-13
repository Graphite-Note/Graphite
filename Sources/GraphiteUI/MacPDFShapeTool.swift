/**
 * File: MacPDFShapeTool.swift
 * ---------------------------
 * Layer: UI
 * Description: The Mac's Shapes tool in one PDF view: dragging draws the row's rectangle, oval, line or arrow; a click
 *              selects a shape, which a drag moves, a handle reshapes, the row restyles and Delete removes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import GraphiteApple

/// The Shapes tool of the Mac's markup row in one PDF view. Each shape drawn, moved,
/// reshaped, restyled or deleted is one step of the PDF's history (`PDFSessionShapes.swift`).
@MainActor
final class MacPDFShapeTool: NSObject {
    private weak var session: PDFSession?
    private weak var pdfView: PDFView?
    private weak var surface: NSView?
    /// The pane's markup row: the look of the next shape, and where the selected one's is shown.
    weak var toolbar: PDFMarkupToolbar?
    /// The selected shape: its page and its name, which Graphite gives every shape it writes;
    /// another application's shape may have none and is kept as its annotation until it is changed.
    private var selection: (page: PDFPage, name: String?, annotation: PDFAnnotation?)?

    private enum Drag {
        /// A new shape from where the press was.
        case drawing(page: PDFPage, start: CGPoint)
        case moving(annotation: PDFAnnotation, page: PDFPage, shape: PDFShape, start: CGPoint)
        case reshaping(annotation: PDFAnnotation, page: PDFPage, shape: PDFShape, handle: PDFShapeHandle)
    }

    private var drag: Drag?
    /// The shape where the drag puts it, drawn over the page until the mouse is let go.
    private var shapeUnderWay: (page: PDFPage, shape: PDFShape)?

    /// How near a shape a click must be to select it, and a handle to take it, in points of the screen.
    private static let reachPoints: CGFloat = 5
    private static let handleSidePoints: CGFloat = 7

    init(session: PDFSession, view: PDFView, surface: NSView) {
        self.session = session
        self.pdfView = view
        self.surface = surface
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(historyDidStep), name: .NSUndoManagerDidUndoChange, object: session.undoManager)
        center.addObserver(self, selector: #selector(historyDidStep), name: .NSUndoManagerDidRedoChange, object: session.undoManager)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    /// Another tool was chosen: nothing stays selected or under way.
    func toolWasPutDown() {
        drag = nil
        shapeUnderWay = nil
        selection = nil
    }

    var selectedShapeName: String? { selection?.name ?? selectedAnnotation()?.annotation.persistentName }

    // MARK: Pointer

    func cursor(atViewPoint viewPoint: CGPoint) -> NSCursor {
        if handle(at: viewPoint) != nil { return .crosshair }
        return pressedShape(at: viewPoint) != nil ? .openHand : .crosshair
    }

    func mouseDown(at viewPoint: CGPoint) {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        if let selected = selectedAnnotation(), let handle = handle(at: viewPoint), let shape = PDFShape(annotation: selected.annotation) {
            drag = .reshaping(annotation: selected.annotation, page: selected.page, shape: shape, handle: handle)
        } else if let pressed = pressedShape(at: viewPoint), let shape = PDFShape(annotation: pressed.annotation) {
            select(pressed.annotation, shape: shape, on: pressed.page)
            drag = .moving(annotation: pressed.annotation, page: pressed.page, shape: shape, start: pressed.pagePoint)
        } else {
            selection = nil
            drag = .drawing(page: page, start: pagePoint)
        }
        surface?.needsDisplay = true
    }

    func mouseDragged(to viewPoint: CGPoint) {
        guard let pdfView, let drag else { return }
        switch drag {
        case .drawing(let page, let start):
            let style = toolbar?.shapeStyle ?? .default
            shapeUnderWay = (page, style.shape(from: start, to: pdfView.convert(viewPoint, to: page)))
        case .moving(_, let page, let shape, let start):
            let pagePoint = pdfView.convert(viewPoint, to: page)
            shapeUnderWay = (page, shape.moved(by: CGVector(dx: pagePoint.x - start.x, dy: pagePoint.y - start.y)))
        case .reshaping(_, let page, let shape, let handle):
            shapeUnderWay = (page, shape.moving(handle, to: pdfView.convert(viewPoint, to: page)))
        }
        surface?.needsDisplay = true
    }

    func mouseUp(at viewPoint: CGPoint) {
        mouseDragged(to: viewPoint)
        guard let drag else { return }
        let changed = shapeUnderWay?.shape
        self.drag = nil
        shapeUnderWay = nil
        surface?.needsDisplay = true
        switch drag {
        case .drawing(let page, _):
            guard let changed, changed.hasVisibleSize else { return }
            perform {
                try session?.addShape(changed, on: page)
                selection = (page, changed.name, nil)
            }
        case .moving(let annotation, let page, let shape, _):
            guard let changed, changed != shape else { return }
            change(annotation, on: page, to: changed, actionName: "Move Shape")
        case .reshaping(let annotation, let page, let shape, _):
            guard let changed, changed != shape, changed.hasVisibleSize else { return }
            change(annotation, on: page, to: changed, actionName: "Resize Shape")
        }
    }

    // MARK: Keys and menu

    /// Delete removes the selected shape; Escape leaves it.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard selection != nil, let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        switch Int(key.value) {
        case NSBackspaceCharacter, NSDeleteCharacter, NSDeleteFunctionKey: deleteSelectedShape()
        case Self.escapeCharacter: selection = nil
        default: return false
        }
        surface?.needsDisplay = true
        return true
    }

    private static let escapeCharacter = 0x1B

    func menu(atViewPoint viewPoint: CGPoint) -> NSMenu? {
        guard let pressed = pressedShape(at: viewPoint), let shape = PDFShape(annotation: pressed.annotation) else { return nil }
        select(pressed.annotation, shape: shape, on: pressed.page)
        surface?.needsDisplay = true
        let menu = NSMenu()
        menu.addItem(MacPDFPageToolMenuItem(title: "Delete") { [weak self] in self?.deleteSelectedShape() })
        return menu
    }

    /// Gives the selected shape a look chosen in the row; its kind and place stay.
    func applyStyle(_ style: PDFMarkupShapeStyle) {
        guard let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) else { return }
        change(selected.annotation, on: selected.page, to: style.restyling(shape), actionName: "Format Shape")
    }

    private func deleteSelectedShape() {
        guard let selected = selectedAnnotation() else { return }
        selection = nil
        perform { try session?.changeShape(selected.annotation, on: selected.page, to: nil, actionName: "Delete Shape") }
        surface?.needsDisplay = true
    }

    // MARK: Shapes

    private func change(_ annotation: PDFAnnotation, on page: PDFPage, to shape: PDFShape, actionName: String) {
        perform {
            try session?.changeShape(annotation, on: page, to: shape, actionName: actionName)
            selection = (page, shape.name, nil)
        }
        surface?.needsDisplay = true
    }

    private func perform(_ change: () throws -> Void) {
        do { try change() } catch { session?.reportFailedChange(error) }
    }

    private func select(_ annotation: PDFAnnotation, shape: PDFShape, on page: PDFPage) {
        selection = (page, annotation.persistentName, annotation.persistentName == nil ? annotation : nil)
        toolbar?.showShapeStyle(PDFMarkupShapeStyle(shape: shape))
    }

    private func pressedShape(at viewPoint: CGPoint) -> (annotation: PDFAnnotation, page: PDFPage, pagePoint: CGPoint)? {
        guard let session, let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return nil }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        let tolerance = Self.reachPoints / max(pdfView.scaleFactor, 0.01)
        guard let annotation = session.shapeAnnotation(at: pagePoint, on: page, tolerance: tolerance) else { return nil }
        return (annotation, page, pagePoint)
    }

    private func selectedAnnotation() -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard let session, let selection else { return nil }
        if let name = selection.name {
            return session.shapeAnnotation(named: name, on: selection.page).map { annotation in (annotation, selection.page) }
        }
        guard let annotation = selection.annotation, selection.page.annotations.contains(where: { kept in kept === annotation }) else { return nil }
        return (annotation, selection.page)
    }

    private func handle(at viewPoint: CGPoint) -> PDFShapeHandle? {
        guard let pdfView, let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) else { return nil }
        return shape.handles.first { placed in
            let center = pdfView.convert(placed.pagePoint, from: selected.page)
            return hypot(viewPoint.x - center.x, viewPoint.y - center.y) <= Self.reachPoints
        }?.handle
    }

    @objc private func historyDidStep() {
        if selection != nil, selectedAnnotation() == nil { selection = nil }
        surface?.needsDisplay = true
    }

    // MARK: Drawing over the page

    /// Draws the shape a drag is making or changing, and the selected shape's handles.
    func drawOverlay(in surface: NSView, of pdfView: PDFView) {
        if let shapeUnderWay {
            drawOutline(of: shapeUnderWay.shape, on: shapeUnderWay.page, in: surface, of: pdfView)
            drawHandles(of: shapeUnderWay.shape, on: shapeUnderWay.page, in: surface, of: pdfView)
        } else if let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) {
            drawHandles(of: shape, on: selected.page, in: surface, of: pdfView)
        }
    }

    private func drawOutline(of shape: PDFShape, on page: PDFPage, in surface: NSView, of pdfView: PDFView) {
        func shown(_ pagePoint: CGPoint) -> CGPoint { surface.convert(pdfView.convert(pagePoint, from: page), from: pdfView) }
        let path = NSBezierPath()
        switch shape.kind {
        case .rectangle, .oval:
            let corners = [shape.start, CGPoint(x: shape.end.x, y: shape.start.y), shape.end, CGPoint(x: shape.start.x, y: shape.end.y)].map(shown)
            let frame = CGRect(x: corners.map(\.x).min() ?? 0, y: corners.map(\.y).min() ?? 0,
                               width: (corners.map(\.x).max() ?? 0) - (corners.map(\.x).min() ?? 0),
                               height: (corners.map(\.y).max() ?? 0) - (corners.map(\.y).min() ?? 0))
            path.append(shape.kind == .oval ? NSBezierPath(ovalIn: frame) : NSBezierPath(rect: frame))
            if let fill = shape.fillColor {
                NSColor(srgbRed: CGFloat(fill.red), green: CGFloat(fill.green), blue: CGFloat(fill.blue), alpha: 1).setFill()
                path.fill()
            }
        case .line, .arrow:
            path.move(to: shown(shape.start))
            path.line(to: shown(shape.end))
        }
        path.lineWidth = max(1, CGFloat(shape.lineWidth) * pdfView.scaleFactor)
        let color = shape.borderColor
        NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1).setStroke()
        path.stroke()
    }

    private func drawHandles(of shape: PDFShape, on page: PDFPage, in surface: NSView, of pdfView: PDFView) {
        for placed in shape.handles {
            let center = surface.convert(pdfView.convert(placed.pagePoint, from: page), from: pdfView)
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
