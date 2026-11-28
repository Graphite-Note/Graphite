/**
 * File: PDFShapeSelection.swift
 * -----------------------------
 * Layer: UI
 * Description: Rectangles, ovals, lines and arrows on an iPad PDF page, the Mac's Shapes tool's or another application's:
 *              a tap selects one, a drag moves it, a handle reshapes it, its menu changes its border, fill and width or
 *              deletes it, each one step of the PDF's history with the Mac's names.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The selected shape of one iPad PDF view: its handles over the page (`PDFShapeFrameView`),
/// the drags that move and reshape it, and its menu. The changes are the session's
/// (`PDFSessionShapes.swift`), which the Mac's Shapes tool makes too.
@MainActor
final class PDFShapeSelectionController: NSObject, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    /// Draws the selected shape's handles and takes the finger's drags on it; made with the first selection.
    private(set) var frameView: PDFShapeFrameView?
    private var menuInteraction: UIEditMenuInteraction?
    /// The selected shape: its page and its name, which Graphite gives every shape it writes;
    /// another application's shape may have none and is kept as its annotation until it is changed.
    private var selection: (page: PDFPage, name: String?, annotation: PDFAnnotation?)?
    private var drag: Drag?
    /// The shape where the drag puts it, drawn over the page until the finger lifts.
    private(set) var shapeUnderWay: PDFShape?
    /// Where the colours of Settings › Colors are kept; a test gives its own.
    var preferences: UserDefaults = .standard
    private var observers: [NSObjectProtocol] = []
    private var scrollObservation: NSKeyValueObservation?

    private enum Drag {
        case moving(annotation: PDFAnnotation, page: PDFPage, shape: PDFShape, start: CGPoint)
        case reshaping(annotation: PDFAnnotation, page: PDFPage, shape: PDFShape, handle: PDFShapeHandle)
    }

    /// How near a shape a finger must be to select it, and a handle to take it, in points of the screen.
    static let reachPoints: CGFloat = 12
    static let handleReachPoints: CGFloat = 22

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
        super.init()
        let center = NotificationCenter.default
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            observers.append(center.addObserver(forName: name, object: pdfView, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.update() }
            })
        }
        // Undo and redo take a shape away or put it elsewhere.
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            observers.append(center.addObserver(forName: name, object: session.undoManager, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.update() }
            })
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        scrollObservation = nil
        frameView?.removeFromSuperview()
        frameView = nil
    }

    var isShapeSelected: Bool { selectedAnnotation() != nil }

    /// The name of the selected shape, for tests.
    var selectedShapeName: String? { selection?.name ?? selectedAnnotation()?.annotation.persistentName }

    /// The selected shape as it is on the page.
    var selectedShape: PDFShape? { selectedAnnotation().flatMap { selected in PDFShape(annotation: selected.annotation) } }

    // MARK: Selecting

    /// The shape that is the topmost object at a point of the view: a picture or a text box over it takes the tap.
    func shape(at viewPoint: CGPoint) -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return nil }
        let tolerance = Self.reachPoints / max(pdfView.scaleFactor, 0.01)
        guard let topmost = session.topmostObjectAnnotation(at: pdfView.convert(viewPoint, to: page), on: page, shapeTolerance: tolerance),
              PDFShape.isShape(topmost) else { return nil }
        return (topmost, page)
    }

    /// Selects the shape at a point and shows its menu; says whether there was one.
    @discardableResult
    func selectShape(at viewPoint: CGPoint) -> Bool {
        guard let (annotation, page) = shape(at: viewPoint) else { return false }
        let wasSelected = selectedAnnotation()?.annotation === annotation
        selection = (page, annotation.persistentName, annotation.persistentName == nil ? annotation : nil)
        update()
        if wasSelected, isMenuShown { dismissMenu() } else { presentMenu() }
        return true
    }

    /// Nothing is selected any more, as after a tap beside the shape.
    func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        drag = nil
        shapeUnderWay = nil
        dismissMenu()
        update()
    }

    private func selectedAnnotation() -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard let selection, selection.page.document === session.document else { return nil }
        if let name = selection.name {
            return session.shapeAnnotation(named: name, on: selection.page).map { annotation in (annotation, selection.page) }
        }
        guard let annotation = selection.annotation, selection.page.annotations.contains(where: { kept in kept === annotation }) else { return nil }
        return (annotation, selection.page)
    }

    // MARK: Dragging

    /// Whether a finger at a point of the view takes the selected shape: on one of its handles or on the shape.
    func takesTouch(at viewPoint: CGPoint) -> Bool {
        handle(at: viewPoint) != nil || isOnSelectedShape(viewPoint)
    }

    private func isOnSelectedShape(_ viewPoint: CGPoint) -> Bool {
        guard let pdfView, let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) else { return false }
        let tolerance = Self.reachPoints / max(pdfView.scaleFactor, 0.01)
        return shape.contains(pdfView.convert(viewPoint, to: selected.page), tolerance: tolerance)
    }

    private func handle(at viewPoint: CGPoint) -> PDFShapeHandle? {
        guard let pdfView, let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) else { return nil }
        let nearest = shape.handles.map { placed in
            let center = pdfView.convert(placed.pagePoint, from: selected.page)
            return (handle: placed.handle, distance: hypot(viewPoint.x - center.x, viewPoint.y - center.y))
        }.min { first, second in first.distance < second.distance }
        guard let nearest, nearest.distance <= Self.handleReachPoints else { return nil }
        return nearest.handle
    }

    /// A finger came down on the selected shape: on a handle it reshapes the shape, elsewhere on it it moves it.
    @discardableResult
    func beginDrag(at viewPoint: CGPoint) -> Bool {
        guard let pdfView, let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) else { return false }
        if let handle = handle(at: viewPoint) {
            drag = .reshaping(annotation: selected.annotation, page: selected.page, shape: shape, handle: handle)
        } else if isOnSelectedShape(viewPoint) {
            drag = .moving(annotation: selected.annotation, page: selected.page, shape: shape, start: pdfView.convert(viewPoint, to: selected.page))
        } else {
            return false
        }
        dismissMenu()
        return true
    }

    func dragChanged(to viewPoint: CGPoint) {
        guard let pdfView, let drag else { return }
        switch drag {
        case .moving(_, let page, let shape, let start):
            let pagePoint = pdfView.convert(viewPoint, to: page)
            shapeUnderWay = shape.moved(by: CGVector(dx: pagePoint.x - start.x, dy: pagePoint.y - start.y))
        case .reshaping(_, let page, let shape, let handle):
            shapeUnderWay = shape.moving(handle, to: pdfView.convert(viewPoint, to: page))
        }
        update()
    }

    /// The finger lifted: the shape is moved or reshaped as one step, Move Shape or Resize Shape.
    func endDrag(at viewPoint: CGPoint) {
        dragChanged(to: viewPoint)
        guard let drag else { return }
        let changed = shapeUnderWay
        self.drag = nil
        shapeUnderWay = nil
        switch drag {
        case .moving(let annotation, let page, let shape, _):
            if let changed, changed != shape { change(annotation, on: page, to: changed, actionName: "Move Shape") }
        case .reshaping(let annotation, let page, let shape, _):
            if let changed, changed != shape, changed.hasVisibleSize { change(annotation, on: page, to: changed, actionName: "Resize Shape") }
        }
        update()
        presentMenu()
    }

    func cancelDrag() {
        drag = nil
        shapeUnderWay = nil
        update()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let pdfView else { return }
        let viewPoint = recognizer.location(in: pdfView)
        switch recognizer.state {
        case .began:
            // The pan begins once the finger has moved a little: the drag is measured from where it came down.
            beginDrag(at: touchDownPoint ?? viewPoint)
            dragChanged(to: viewPoint)
        case .changed: dragChanged(to: viewPoint)
        case .ended: endDrag(at: viewPoint)
        case .cancelled, .failed: cancelDrag()
        default: break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let pdfView, recognizer.state == .ended else { return }
        if isMenuShown { dismissMenu() } else { presentMenu(at: recognizer.location(in: pdfView)) }
    }

    /// Where the finger of the pan came down, in the PDF view.
    private var touchDownPoint: CGPoint?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let pdfView { touchDownPoint = touch.location(in: pdfView) }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pdfView else { return false }
        return takesTouch(at: touchDownPoint ?? gestureRecognizer.location(in: pdfView))
    }

    // MARK: Changing

    /// Gives the selected shape a border colour, a fill or a width, as one Format Shape step; its kind and place stay.
    func applyStyle(_ style: PDFMarkupShapeStyle) {
        guard let selected = selectedAnnotation(), let shape = PDFShape(annotation: selected.annotation) else { return }
        change(selected.annotation, on: selected.page, to: style.restyling(shape), actionName: "Format Shape")
        presentMenu()
    }

    func deleteSelectedShape() {
        guard let selected = selectedAnnotation() else { return }
        selection = nil
        dismissMenu()
        do { try session.changeShape(selected.annotation, on: selected.page, to: nil, actionName: "Delete Shape") }
        catch { session.reportFailedChange(error) }
        update()
    }

    private func change(_ annotation: PDFAnnotation, on page: PDFPage, to shape: PDFShape, actionName: String) {
        do {
            try session.changeShape(annotation, on: page, to: shape, actionName: actionName)
            selection = (page, shape.name, nil)
        } catch {
            session.reportFailedChange(error)
        }
    }

    // MARK: The menu

    /// Border, Fill (a rectangle's or an oval's) and Line Width, each ticking the shape's own, then Delete Shape.
    func menu() -> UIMenu? {
        guard let shape = selectedShape else { return nil }
        return PDFShapeMenu.menu(for: shape, storedPalette: preferences.data(forKey: GraphitePreferences.colorPaletteKey),
                                 restyle: { [weak self] style in self?.applyStyle(style) }, delete: { [weak self] in self?.deleteSelectedShape() })
    }

    private(set) var isMenuShown = false

    /// Shows the menu above the selected shape, or at a point of the view.
    func presentMenu(at viewPoint: CGPoint? = nil) {
        guard let pdfView, pdfView.window != nil, let frameView, let menuInteraction, let anchor = viewPoint ?? menuAnchor() else { return }
        menuInteraction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: frameView.convert(anchor, from: pdfView)))
        isMenuShown = true
    }

    func dismissMenu() {
        menuInteraction?.dismissMenu()
        isMenuShown = false
    }

    private func menuAnchor() -> CGPoint? {
        guard let pdfView, let selected = selectedAnnotation() else { return nil }
        let frame = pdfView.convert(selected.annotation.bounds, from: selected.page)
        return CGPoint(x: frame.midX, y: frame.minY)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        menu()
    }

    /// The shape with its handles' reach: the menu stands beside it, never over a handle.
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let pdfView, let frameView, let selected = selectedAnnotation() else { return .null }
        let frame = pdfView.convert(selected.annotation.bounds, from: selected.page)
        return frameView.convert(frame, from: pdfView).insetBy(dx: -Self.handleReachPoints, dy: -Self.handleReachPoints)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: any UIEditMenuInteractionAnimating) {
        isMenuShown = false
    }

    // MARK: Drawing over the page

    /// Shows the handles of the selected shape where the page shows it, and the shape a drag is making.
    func update() {
        guard let pdfView, pdfView.window != nil else { return }
        if selection != nil, selectedAnnotation() == nil {
            selection = nil
            drag = nil
            shapeUnderWay = nil
            dismissMenu()
        }
        guard let selected = selectedAnnotation(), let shape = shapeUnderWay ?? PDFShape(annotation: selected.annotation) else {
            frameView?.isHidden = true
            return
        }
        let frameView = frameView ?? makeFrameView(in: pdfView)
        frameView.isHidden = false
        frameView.frame = pdfView.bounds
        func shown(_ pagePoint: CGPoint) -> CGPoint { frameView.convert(pdfView.convert(pagePoint, from: selected.page), from: pdfView) }
        frameView.show(handles: shape.handles.map { placed in shown(placed.pagePoint) },
                       outline: shapeUnderWay.map { underWay in Self.outline(of: underWay, shown: shown) },
                       outlineWidth: max(1, CGFloat(shape.lineWidth) * pdfView.scaleFactor), color: shape.borderColor.platformColor,
                       fill: shape.fillColor?.platformColor)
    }

    private static func outline(of shape: PDFShape, shown: (CGPoint) -> CGPoint) -> UIBezierPath {
        switch shape.kind {
        case .rectangle, .oval:
            let corners = [shape.start, CGPoint(x: shape.end.x, y: shape.start.y), shape.end, CGPoint(x: shape.start.x, y: shape.end.y)].map(shown)
            let xs = corners.map(\.x), ys = corners.map(\.y)
            let frame = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
            return shape.kind == .oval ? UIBezierPath(ovalIn: frame) : UIBezierPath(rect: frame)
        case .line, .arrow:
            let path = UIBezierPath()
            path.move(to: shown(shape.start))
            path.addLine(to: shown(shape.end))
            return path
        }
    }

    private func makeFrameView(in pdfView: PDFView) -> PDFShapeFrameView {
        let frameView = PDFShapeFrameView(frame: pdfView.bounds)
        frameView.takesTouch = { [weak self, weak pdfView] point in
            guard let self, let pdfView else { return false }
            return self.takesTouch(at: pdfView.convert(point, from: frameView))
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        frameView.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        frameView.addGestureRecognizer(tap)
        let menuInteraction = UIEditMenuInteraction(delegate: self)
        frameView.addInteraction(menuInteraction)
        self.menuInteraction = menuInteraction
        pdfView.addSubview(frameView)
        self.frameView = frameView
        // The page does not scroll under a finger that moves the shape, and the handles follow the page as it scrolls.
        if let scrollView = Self.scrollView(in: pdfView) {
            scrollView.panGestureRecognizer.require(toFail: pan)
            scrollObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
                // Reported on the main thread that scrolls the page.
                MainActor.assumeIsolated { self?.update() }
            }
        }
        return frameView
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let scrollView = scrollView(in: subview) { return scrollView }
        }
        return nil
    }
}

/// The menu of a selected shape on the iPad: Border, Fill (a rectangle's or an oval's) and Line Width, each
/// ticking the shape's own, then Delete Shape. The colours are those of the Mac's markup row.
@MainActor
enum PDFShapeMenu {
    static func menu(for shape: PDFShape, storedPalette: Data?, restyle: @escaping @MainActor (PDFMarkupShapeStyle) -> Void,
                     delete: @escaping @MainActor () -> Void) -> UIMenu {
        let current = PDFMarkupShapeStyle(shape: shape)
        func restyled(_ change: (inout PDFMarkupShapeStyle) -> Void) -> PDFMarkupShapeStyle {
            var style = current
            change(&style)
            return style
        }
        let border = PDFMarkupRowColors.choices(storedPalette: storedPalette, including: shape.borderColor).map { name, color in
            UIAction(title: name, image: swatch(color), state: color == shape.borderColor ? .on : .off) { _ in
                restyle(restyled { style in style.borderColor = color })
            }
        }
        var children: [UIMenuElement] = [UIMenu(title: "Border", image: UIImage(systemName: "square"), children: border)]
        if !shape.kind.isSegment {
            let noFill = UIAction(title: "No Fill", image: UIImage(systemName: "circle.slash"), state: shape.fillColor == nil ? .on : .off) { _ in
                restyle(restyled { style in style.fillColor = nil })
            }
            let fills = PDFMarkupRowColors.choices(storedPalette: storedPalette, including: shape.fillColor).map { name, color in
                UIAction(title: name, image: swatch(color), state: color == shape.fillColor ? .on : .off) { _ in
                    restyle(restyled { style in style.fillColor = color })
                }
            }
            children.append(UIMenu(title: "Fill", image: UIImage(systemName: "square.fill"), children: [noFill] + fills))
        }
        let widths = PDFMarkupInkWidth.allCases.map { width in
            UIAction(title: width.title, state: width == current.width ? .on : .off) { _ in restyle(restyled { style in style.width = width }) }
        }
        children.append(UIMenu(title: "Line Width", image: UIImage(systemName: "lineweight"), children: widths))
        children.append(UIAction(title: "Delete Shape", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in delete() })
        return UIMenu(children: children)
    }

    private static func swatch(_ color: PDFTextColor) -> UIImage? {
        UIImage(systemName: "circle.fill")?.withTintColor(color.platformColor, renderingMode: .alwaysOriginal)
    }
}

/// Covers the PDF view and draws the selected shape's handles, and the shape a drag is making.
/// It takes only the touches of a finger on the shape or a handle; the Pencil writes through it.
final class PDFShapeFrameView: UIView {
    var takesTouch: ((CGPoint) -> Bool)?
    private let outlineLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private static let handleDiameter: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        handlesLayer.fillColor = UIColor.white.cgColor
        handlesLayer.strokeColor = UIColor.tintColor.cgColor
        handlesLayer.lineWidth = 1.5
        layer.addSublayer(outlineLayer)
        layer.addSublayer(handlesLayer)
        isAccessibilityElement = true
        accessibilityLabel = "Selected shape"
    }

    required init?(coder: NSCoder) { fatalError("PDFShapeFrameView is created in code.") }

    /// The handles' places and, during a drag, the shape's outline, in this view's coordinates.
    func show(handles: [CGPoint], outline: UIBezierPath?, outlineWidth: CGFloat, color: UIColor, fill: UIColor?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let handlesPath = UIBezierPath()
        let radius = Self.handleDiameter / 2
        for center in handles {
            handlesPath.append(UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)))
        }
        handlesLayer.path = handlesPath.cgPath
        outlineLayer.path = outline?.cgPath
        outlineLayer.lineWidth = outlineWidth
        outlineLayer.strokeColor = color.cgColor
        outlineLayer.fillColor = fill?.cgColor ?? UIColor.clear.cgColor
        CATransaction.commit()
        handlesPositions = handles
    }

    /// Where the handles are drawn, for tests.
    private(set) var handlesPositions: [CGPoint] = []

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if event?.allTouches?.contains(where: { touch in touch.type == .pencil }) == true { return false }
        return takesTouch?(point) ?? false
    }
}

extension PDFTextColor {
    /// The colour as UIKit draws it, in sRGB.
    var platformColor: UIColor { UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1) }
}
#endif
