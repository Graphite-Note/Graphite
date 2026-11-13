/**
 * File: MacPDFTextBoxTool.swift
 * -----------------------------
 * Layer: UI
 * Description: The Mac's Text Box tool in one PDF view: placing, selecting, moving, resizing, typing in, formatting,
 *              duplicating and deleting text boxes with the pointer and the keyboard, each change one step of the
 *              PDF's history, through the session's text box model the iPad uses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The Text Box tool of the Mac's markup row in one PDF view. It changes boxes only through
/// the session (`PDFSessionTextBoxes.swift`), as the iPad's text tool does, so a box made
/// here is the iPad's own; it keeps the session's `textBoxActivity` and `textBoxFormat`
/// current for the row's text controls, which format through `applyTextBoxFormat`.
@MainActor
final class MacPDFTextBoxTool: NSObject {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    private weak var surface: NSView?
    private var editor: MacPDFTextBoxEditor?
    /// The press under way that moves or resizes the selected box: what it changes, the
    /// pointer's place on the page when it began, and the box as the drag makes it so far.
    private var drag: (box: PDFTextBox, page: PDFPage, edge: PDFTextBoxEdge?, startPagePoint: CGPoint, changed: PDFTextBox)?

    /// A handle is this far, in points of the screen, from the middle of the side it is on.
    private static let handleReachPoints: CGFloat = 6
    private static let handleSidePoints: CGFloat = 7
    /// A drag shorter than this, in points of the page, is a click, not a move.
    private static let shortestMovePoints: CGFloat = 1
    /// How far an arrow key moves the selected box, in points of the page; with Shift, the larger step.
    private static let arrowStepPoints: CGFloat = 1
    private static let shiftArrowStepPoints: CGFloat = 10

    /// Where the look of the last box formatted is kept for the next new box.
    private let preferences: UserDefaults

    init(session: PDFSession, view: PDFView, surface: NSView, preferences: UserDefaults) {
        self.preferences = preferences
        self.session = session
        self.pdfView = view
        self.surface = surface
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(viewChangedPlace), name: .PDFViewScaleChanged, object: view)
        if let clipView = view.documentView?.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(viewChangedPlace), name: NSView.boundsDidChangeNotification, object: clipView)
        }
        // Undo and redo take a box back to a former state; typing ends first and goes into
        // the history as its own step, so the undo is of what was there before.
        center.addObserver(self, selector: #selector(historyWillStep), name: .NSUndoManagerWillUndoChange, object: session.undoManager)
        center.addObserver(self, selector: #selector(historyWillStep), name: .NSUndoManagerWillRedoChange, object: session.undoManager)
        session.registerTextBoxChangeObserver(for: self) { [weak self] in self?.textBoxesDidChange() }
        session.applyTextBoxFormat = { [weak self] change in self?.applyFormat(change) }
    }

    /// Ends typing and what the tool observes; called when the PDF view is taken down.
    func stop() {
        toolWasPutDown()
        NotificationCenter.default.removeObserver(self)
        session.unregisterTextBoxChangeObserver(for: self)
        session.applyTextBoxFormat = nil
    }

    /// Another tool was chosen: typing ends and no box stays selected.
    func toolWasPutDown() {
        endEditing()
        drag = nil
        session.textBoxActivity = .idle
        showFormat(nil)
        surface?.needsDisplay = true
    }

    func editorContains(viewPoint: CGPoint) -> Bool { editor?.contains(viewPoint: viewPoint) == true }

    func cursor(atViewPoint viewPoint: CGPoint) -> NSCursor? {
        if handle(at: viewPoint) != nil { return .resizeLeftRight }
        return textBox(at: viewPoint) == nil ? .iBeam : .openHand
    }

    // MARK: Pointer

    func mouseDown(at viewPoint: CGPoint, clickCount: Int) {
        let pressed = textBox(at: viewPoint)
        let outcome = PDFTextBoxPointerPress.outcome(pressedBoxName: pressed?.box.name, pressedHandle: handle(at: viewPoint),
                                                     selectedBoxName: session.textBoxActivity.selection?.boxName, isTyping: editor != nil,
                                                     clickCount: clickCount)
        switch outcome {
        case .placeNewBox: placeNewBox(at: viewPoint)
        case .select:
            guard let pressed else { return }
            select(pressed.box, on: pressed.page)
            beginDrag(of: pressed.box, on: pressed.page, edge: nil, at: viewPoint)
        case .beginTyping:
            guard let pressed else { return }
            beginEditing(pressed.box, on: pressed.page, caretAt: viewPoint)
        case .resize(_, let edge):
            guard let selected = selectedBox() else { return }
            beginDrag(of: selected.box, on: selected.page, edge: edge, at: viewPoint)
        case .deselect: deselect()
        case .endTyping(let selectingBoxName):
            endEditing()
            if selectingBoxName != nil, let pressed { select(pressed.box, on: pressed.page) } else { deselect() }
        }
        surface?.needsDisplay = true
    }

    func mouseDragged(to viewPoint: CGPoint) {
        guard let pdfView, var drag else { return }
        let pagePoint = pdfView.convert(viewPoint, to: drag.page)
        let delta = CGVector(dx: pagePoint.x - drag.startPagePoint.x, dy: pagePoint.y - drag.startPagePoint.y)
        drag.changed = drag.edge.map { edge in PDFTextBoxPointerDrag.resized(drag.box, from: edge, by: delta) }
            ?? PDFTextBoxPointerDrag.moved(drag.box, by: delta)
        self.drag = drag
        surface?.needsDisplay = true
    }

    func mouseUp(at viewPoint: CGPoint) {
        mouseDragged(to: viewPoint)
        guard let drag else { return }
        self.drag = nil
        surface?.needsDisplay = true
        let movedFar = hypot(drag.changed.origin.x - drag.box.origin.x, drag.changed.origin.y - drag.box.origin.y) >= Self.shortestMovePoints
        let resized = abs(drag.changed.width - drag.box.width) >= Double(Self.shortestMovePoints)
        guard movedFar || resized else { return }
        changeSelectedBox(actionName: drag.edge == nil ? "Move Text Box" : "Resize Text Box") { box in
            box.origin = drag.changed.origin
            box.width = drag.changed.width
        }
    }

    private func beginDrag(of box: PDFTextBox, on page: PDFPage, edge: PDFTextBoxEdge?, at viewPoint: CGPoint) {
        guard let pdfView else { return }
        drag = (box, page, edge, pdfView.convert(viewPoint, to: page), box)
    }

    // MARK: Keyboard and menu

    /// Delete removes the selected box, Return types in it, Escape lets it go, ⌘D duplicates
    /// it and the arrow keys move it, a point at a time or ten with Shift.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard editor == nil, session.textBoxActivity.selection != nil, let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(key.value) {
        case NSBackspaceCharacter, NSDeleteCharacter, NSDeleteFunctionKey:
            perform { try session.deleteSelectedTextBox() }
        case NSCarriageReturnCharacter, NSEnterCharacter:
            if let selected = selectedBox() { beginEditing(selected.box, on: selected.page, caretAt: nil) }
        case Self.escapeCharacter:
            deselect()
        case Int(("d" as Unicode.Scalar).value) where modifiers == .command:
            perform { try session.duplicateSelectedTextBox() }
        case NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSUpArrowFunctionKey, NSDownArrowFunctionKey:
            nudgeSelectedBox(arrowKey: Int(key.value), isLargeStep: modifiers.contains(.shift))
        default:
            return false
        }
        surface?.needsDisplay = true
        return true
    }

    private static let escapeCharacter = 0x1B

    private func nudgeSelectedBox(arrowKey: Int, isLargeStep: Bool) {
        guard let pdfView, let selected = selectedBox() else { return }
        let step = isLargeStep ? Self.shiftArrowStepPoints : Self.arrowStepPoints
        // Left, right, up and down as the page is shown, which a turned page turns back.
        let shown: CGVector = switch arrowKey {
        case NSLeftArrowFunctionKey: CGVector(dx: -step, dy: 0)
        case NSRightArrowFunctionKey: CGVector(dx: step, dy: 0)
        case NSUpArrowFunctionKey: CGVector(dx: 0, dy: step)
        default: CGVector(dx: 0, dy: -step)
        }
        let middle = pdfView.convert(selected.box.middle, from: selected.page)
        let shiftedMiddle = pdfView.convert(CGPoint(x: middle.x + shown.dx * pdfView.scaleFactor, y: middle.y + shown.dy * pdfView.scaleFactor),
                                            to: selected.page)
        let delta = CGVector(dx: shiftedMiddle.x - selected.box.middle.x, dy: shiftedMiddle.y - selected.box.middle.y)
        changeSelectedBox(actionName: "Move Text Box") { box in box = PDFTextBoxPointerDrag.moved(box, by: delta) }
    }

    /// A box's right-click menu: Edit Text, Duplicate and Delete.
    func menu(atViewPoint viewPoint: CGPoint) -> NSMenu? {
        guard editor == nil, let pressed = textBox(at: viewPoint) else { return nil }
        select(pressed.box, on: pressed.page)
        surface?.needsDisplay = true
        let menu = NSMenu()
        menu.addItem(MacPDFPageToolMenuItem(title: "Edit Text") { [weak self] in
            guard let self, let selected = selectedBox() else { return }
            beginEditing(selected.box, on: selected.page, caretAt: nil)
        })
        menu.addItem(MacPDFPageToolMenuItem(title: "Duplicate", keyEquivalent: "d") { [weak self] in
            self?.perform { [weak self] in try self?.session.duplicateSelectedTextBox() }
        })
        menu.addItem(.separator())
        menu.addItem(MacPDFPageToolMenuItem(title: "Delete") { [weak self] in
            self?.perform { [weak self] in try self?.session.deleteSelectedTextBox() }
        })
        return menu
    }

    // MARK: Boxes

    private func textBox(at viewPoint: CGPoint) -> (box: PDFTextBox, page: PDFPage)? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false),
              let box = session.textBox(at: pdfView.convert(viewPoint, to: page), on: page) else { return nil }
        return (box, page)
    }

    private func selectedBox() -> (box: PDFTextBox, page: PDFPage)? {
        guard let selection = session.textBoxActivity.selection, let page = selection.page.page, let box = session.textBox(selection) else { return nil }
        return (box, page)
    }

    /// The handle of the selected box under a point of the PDF view.
    private func handle(at viewPoint: CGPoint) -> PDFTextBoxEdge? {
        guard editor == nil, let pdfView, let selected = selectedBox() else { return nil }
        let handles = Self.handleCenters(of: MacPDFTextBoxGeometry(box: selected.box, page: selected.page, pdfView: pdfView))
        if hypot(viewPoint.x - handles.leading.x, viewPoint.y - handles.leading.y) <= Self.handleReachPoints { return .leading }
        if hypot(viewPoint.x - handles.trailing.x, viewPoint.y - handles.trailing.y) <= Self.handleReachPoints { return .trailing }
        return nil
    }

    /// The middles of the box's sides along its text, turned with it, in the PDF view's coordinates.
    private static func handleCenters(of geometry: MacPDFTextBoxGeometry) -> (leading: CGPoint, trailing: CGPoint) {
        let frame = geometry.unrotatedFrame
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        // The view's coordinates rise upward, so a clockwise turn on screen is a negative angle in them.
        let angle = -geometry.clockwiseRotation
        let halfWidth = frame.width / 2
        let along = CGVector(dx: cos(angle) * halfWidth, dy: sin(angle) * halfWidth)
        return (CGPoint(x: middle.x - along.dx, y: middle.y - along.dy), CGPoint(x: middle.x + along.dx, y: middle.y + along.dy))
    }

    private func select(_ box: PDFTextBox, on page: PDFPage) {
        session.textBoxActivity = .selected(PDFTextBoxSelection(boxName: box.name, page: session.historyPage(for: page)))
        showFormat(PDFTextBoxDefaults(box: box))
    }

    private func deselect() {
        session.textBoxActivity = .idle
        showFormat(nil)
    }

    /// A box where the page was clicked, with the look last given to a box, typed in at once.
    private func placeNewBox(at viewPoint: CGPoint) {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false), session.document.index(for: page) != NSNotFound else { return }
        let defaults = PDFTextBoxDefaults.stored(in: preferences)
        let newBox = session.newTextBox(at: pdfView.convert(viewPoint, to: page), on: page, style: defaults)
        beginEditing(newBox, isNew: true, on: page, caretAt: nil, typingLooks: defaults.attributes)
    }

    private func changeSelectedBox(actionName: String, _ change: (inout PDFTextBox) -> Void) {
        perform { try session.changeSelectedTextBox(actionName: actionName, change) }
        if let selected = selectedBox() { showFormat(PDFTextBoxDefaults(box: selected.box)) }
    }

    private func perform(_ change: () throws -> Void) {
        do { try change() } catch { session.reportFailedChange(error) }
        surface?.needsDisplay = true
    }

    // MARK: Typing

    private func beginEditing(_ box: PDFTextBox, isNew: Bool = false, on page: PDFPage, caretAt viewPoint: CGPoint?,
                              typingLooks: PDFTextAttributes = PDFTextBoxDefaults.original.attributes) {
        guard let pdfView else { return }
        endEditing()
        let historyPage = session.historyPage(for: page)
        // A box another application made, without a name, gets one as Graphite writes it.
        let named = box.name.isEmpty ? box.renamed(UUID().uuidString) : box
        let step = PDFTextBoxEditStep(before: isNew ? nil : box, page: historyPage)
        let editor = MacPDFTextBoxEditor(session: session, pdfView: pdfView, box: named, step: step, typingLooks: typingLooks, owner: self)
        self.editor = editor
        session.textBoxActivity = .editing(PDFTextBoxSelection(boxName: named.name, page: historyPage))
        editor.begin(caretAt: viewPoint)
        editedBoxDidChange()
        surface?.needsDisplay = true
    }

    /// Ends typing: the document takes the box, which stays selected unless it was emptied.
    func endEditingLeavingBoxSelected() {
        guard let editor else { return }
        let page = editor.step.page.page
        endEditing()
        if let page, let box = session.textBoxes(on: page).first(where: { box in box.name == editor.box.name }) { select(box, on: page) } else { deselect() }
        surface?.needsDisplay = true
    }

    /// Commits the box typed in and takes its text view away.
    private func endEditing() {
        guard let editor else { return }
        self.editor = nil
        editor.end()
        if session.textBoxActivity.isEditing { session.textBoxActivity = .idle }
    }

    func editedBoxDidChange() {
        guard let editor else { return }
        showFormat(PDFTextBoxDefaults(attributes: editor.currentLooks, boxStyle: editor.box.style))
    }

    // MARK: Format

    private func applyFormat(_ change: PDFTextBoxFormatChange) {
        if let editor {
            editor.apply(change)
            PDFTextBoxDefaults(attributes: editor.currentLooks, boxStyle: editor.box.style).store(in: preferences)
            return
        }
        changeSelectedBox(actionName: "Format Text") { box in box = change.applied(to: box) }
        if let selected = selectedBox() { PDFTextBoxDefaults(box: selected.box).store(in: preferences) }
    }

    /// Gives the row's text controls the format, only when it changes, as each change updates the row.
    private func showFormat(_ format: PDFTextBoxDefaults?) {
        if session.textBoxFormat != format { session.textBoxFormat = format }
    }

    // MARK: Following the PDF

    @objc private func viewChangedPlace() {
        editor?.place()
        if session.textBoxActivity.selection != nil { surface?.needsDisplay = true }
    }

    @objc private func historyWillStep() {
        endEditing()
    }

    private func textBoxesDidChange() {
        if editor == nil, let selection = session.textBoxActivity.selection, session.textBox(selection) == nil { deselect() }
        surface?.needsDisplay = true
    }

    // MARK: The selection's frame

    /// Draws the frame of the selected box, where a drag puts it, with a handle at each side along its text.
    func drawSelectionFrame(in surface: NSView, of pdfView: PDFView) {
        guard editor == nil, let selected = selectedBox() else { return }
        let geometry = MacPDFTextBoxGeometry(box: drag?.changed ?? selected.box, page: selected.page, pdfView: pdfView)
        let frame = geometry.unrotatedFrame
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        let angle = -geometry.clockwiseRotation
        let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)].map { corner in
            let offset = CGVector(dx: corner.x - middle.x, dy: corner.y - middle.y)
            let turned = CGPoint(x: middle.x + offset.dx * cos(angle) - offset.dy * sin(angle), y: middle.y + offset.dx * sin(angle) + offset.dy * cos(angle))
            return surface.convert(turned, from: pdfView)
        }
        let outline = NSBezierPath()
        outline.move(to: corners[0])
        for corner in corners.dropFirst() { outline.line(to: corner) }
        outline.close()
        outline.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        outline.stroke()
        let handles = Self.handleCenters(of: geometry)
        for center in [handles.leading, handles.trailing].map({ center in surface.convert(center, from: pdfView) }) {
            let side = Self.handleSidePoints
            let handle = NSBezierPath(ovalIn: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.stroke()
        }
    }
}

/// A menu item of a page tool that runs a closure.
final class MacPDFPageToolMenuItem: NSMenuItem {
    private let perform: () -> Void

    init(title: String, keyEquivalent: String = "", perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(MacPDFPageToolMenuItem.performAction), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        perform = {}
        super.init(coder: coder)
    }

    @objc private func performAction() { perform() }
}
#endif
