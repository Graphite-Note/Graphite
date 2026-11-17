/**
 * File: MacPDFNoteTool.swift
 * --------------------------
 * Layer: UI
 * Description: Notes on the Mac: the markup row's Note tool places one where the page is clicked and opens it to type;
 *              a click on a note's icon opens it to read and edit, a drag moves it, its right-click menu recolours or
 *              deletes it; a popover beside the icon holds the text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore
import PDFKit
import GraphiteApple

/// The Note tool of the Mac's markup row in one PDF view. Each note placed, edited, moved, recoloured or deleted is one
/// step of the PDF's history (`PDFSessionNotes.swift`).
@MainActor
final class MacPDFNoteTool: NSObject {
    private weak var session: PDFSession?
    private weak var pdfView: PDFView?
    private weak var surface: NSView?
    let editor: MacPDFNoteEditor
    /// The selected note, kept as its annotation: another application's note may have no name.
    private var selection: (annotation: PDFAnnotation, page: PDFPage)?
    private var drag: (annotation: PDFAnnotation, page: PDFPage, note: PDFNote, start: CGPoint)?
    /// Where a drag puts the note's icon, drawn over the page until the mouse is let go.
    private var noteUnderWay: (page: PDFPage, note: PDFNote)?
    /// Where the press that may place a new note came down, when it was on the page but on no note.
    private var placement: (page: PDFPage, pagePoint: CGPoint)?

    /// How near a note's icon a click must be to take it, in points of the screen; and how far a drag must go to move it.
    private static let reachPoints: CGFloat = 3
    private static let shortestMovePoints: CGFloat = 3

    init(session: PDFSession, view: PDFView, surface: NSView) {
        self.session = session
        self.pdfView = view
        self.surface = surface
        editor = MacPDFNoteEditor(session: session, view: view)
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(historyDidStep), name: .NSUndoManagerDidUndoChange, object: session.undoManager)
        center.addObserver(self, selector: #selector(historyDidStep), name: .NSUndoManagerDidRedoChange, object: session.undoManager)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        editor.close()
    }

    /// Another tool was chosen: the note being read closes, and nothing stays selected.
    func toolWasPutDown() {
        editor.close()
        drag = nil
        noteUnderWay = nil
        placement = nil
        selection = nil
    }

    // MARK: Pointer

    func cursor(atViewPoint viewPoint: CGPoint) -> NSCursor {
        pressedNote(at: viewPoint) != nil ? .openHand : .arrow
    }

    func mouseDown(at viewPoint: CGPoint) {
        editor.close()
        placement = nil
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return }
        if let pressed = pressedNote(at: viewPoint), let note = PDFNote(annotation: pressed.annotation) {
            selection = (pressed.annotation, pressed.page)
            drag = (pressed.annotation, pressed.page, note, pressed.pagePoint)
        } else {
            selection = nil
            placement = (page, pdfView.convert(viewPoint, to: page))
        }
        surface?.needsDisplay = true
    }

    func mouseDragged(to viewPoint: CGPoint) {
        guard let pdfView, let drag else { return }
        let pagePoint = pdfView.convert(viewPoint, to: drag.page)
        let delta = CGVector(dx: pagePoint.x - drag.start.x, dy: pagePoint.y - drag.start.y)
        noteUnderWay = (drag.page, drag.note.moved(by: delta, within: drag.page.bounds(for: pdfView.displayBox)))
        surface?.needsDisplay = true
    }

    func mouseUp(at viewPoint: CGPoint) {
        mouseDragged(to: viewPoint)
        defer {
            drag = nil
            noteUnderWay = nil
            placement = nil
            surface?.needsDisplay = true
        }
        if let drag {
            let moved = noteUnderWay?.note
            let distance = moved.map { moved in hypot(moved.iconBounds.minX - drag.note.iconBounds.minX, moved.iconBounds.minY - drag.note.iconBounds.minY) } ?? 0
            if let moved, distance * (pdfView?.scaleFactor ?? 1) >= Self.shortestMovePoints {
                perform { try session?.changeNote(drag.annotation, on: drag.page, to: moved, actionName: "Move Note") }
                selection = session?.noteAnnotation(named: moved.name, on: drag.page).map { annotation in (annotation, drag.page) }
            } else {
                editor.open(drag.annotation, on: drag.page)
            }
        } else if let placement, let pdfView {
            let note = PDFNote.placed(at: placement.pagePoint, on: placement.page.bounds(for: pdfView.displayBox), contents: "")
            editor.openNew(note, on: placement.page) { [weak self] placed in
                self?.selection = self?.session?.noteAnnotation(named: placed.name, on: placement.page).map { annotation in (annotation, placement.page) }
                self?.surface?.needsDisplay = true
            }
        }
    }

    // MARK: Keys and menu

    /// Delete removes the selected note; Escape leaves it; Return opens it.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let selected = selectedNote(), let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        switch Int(key.value) {
        case NSBackspaceCharacter, NSDeleteCharacter, NSDeleteFunctionKey: delete(selected.annotation, on: selected.page)
        case Self.escapeCharacter: selection = nil
        case NSCarriageReturnCharacter, NSEnterCharacter: editor.open(selected.annotation, on: selected.page)
        default: return false
        }
        surface?.needsDisplay = true
        return true
    }

    private static let escapeCharacter = 0x1B

    func menu(atViewPoint viewPoint: CGPoint) -> NSMenu? {
        guard let pressed = pressedNote(at: viewPoint) else { return nil }
        selection = (pressed.annotation, pressed.page)
        surface?.needsDisplay = true
        return MacPDFNoteMenu.menu(for: pressed.annotation, on: pressed.page, session: session, editor: editor) { [weak self] in
            self?.selection = nil
            self?.surface?.needsDisplay = true
        }
    }

    // MARK: Notes

    private func delete(_ annotation: PDFAnnotation, on page: PDFPage) {
        selection = nil
        editor.close()
        perform { try session?.changeNote(annotation, on: page, to: nil, actionName: "Delete Note") }
    }

    private func perform(_ change: () throws -> Void) {
        do { try change() } catch { session?.reportFailedChange(error) }
    }

    private func pressedNote(at viewPoint: CGPoint) -> (annotation: PDFAnnotation, page: PDFPage, pagePoint: CGPoint)? {
        guard let session, let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return nil }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        let tolerance = Self.reachPoints / max(pdfView.scaleFactor, 0.01)
        guard let annotation = session.noteAnnotation(at: pagePoint, on: page, tolerance: tolerance) else { return nil }
        return (annotation, page, pagePoint)
    }

    private func selectedNote() -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard let selection, selection.page.annotations.contains(where: { kept in kept === selection.annotation }) else { return nil }
        return selection
    }

    @objc private func historyDidStep() {
        if selection != nil, selectedNote() == nil { selection = nil }
        surface?.needsDisplay = true
    }

    // MARK: Drawing over the page

    /// A frame round the selected note's icon, or round where a drag puts it.
    func drawOverlay(in surface: NSView, of pdfView: PDFView) {
        let shown: (bounds: CGRect, page: PDFPage)? = if let noteUnderWay {
            (noteUnderWay.note.iconBounds, noteUnderWay.page)
        } else if let selected = selectedNote() {
            (selected.annotation.bounds, selected.page)
        } else {
            nil
        }
        guard let shown else { return }
        let frame = surface.convert(pdfView.convert(shown.bounds, from: shown.page), from: pdfView).insetBy(dx: -2, dy: -2)
        let path = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
        path.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

/// The right-click menu of a note, for the Note tool and for a note clicked with Text Selection: Open Note, a colour of
/// each of `PDFNote.colors` with the note's ticked, and Delete Note.
@MainActor
enum MacPDFNoteMenu {
    static func menu(for annotation: PDFAnnotation, on page: PDFPage, session: PDFSession?, editor: MacPDFNoteEditor,
                     deleted: @escaping () -> Void) -> NSMenu? {
        guard let note = PDFNote(annotation: annotation) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MacPDFPageToolMenuItem(title: "Open Note") { [weak editor] in editor?.open(annotation, on: page) })
        menu.addItem(.separator())
        for (name, color) in PDFNote.colors {
            let item = MacPDFPageToolMenuItem(title: name) { [weak session] in
                var recolored = note
                recolored.color = color
                do { try session?.changeNote(annotation, on: page, to: recolored, actionName: "Recolor Note") } catch { session?.reportFailedChange(error) }
            }
            item.state = note.color == color ? .on : .off
            item.image = swatch(color)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MacPDFPageToolMenuItem(title: "Delete Note") { [weak session, weak editor] in
            editor?.close()
            do { try session?.changeNote(annotation, on: page, to: nil, actionName: "Delete Note") } catch { session?.reportFailedChange(error) }
            deleted()
        })
        return menu
    }

    private static func swatch(_ color: PDFTextColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

/// The popover beside a note's icon that shows its text to read and edit. Closing it keeps the text: a new note is
/// placed only when it has some, and an edited one becomes one step, "Edit Note".
@MainActor
final class MacPDFNoteEditor: NSObject, NSPopoverDelegate, NSTextViewDelegate {
    private weak var session: PDFSession?
    private weak var pdfView: PDFView?
    private var popover: NSPopover?
    /// The note being read: the annotation for one on the page, or the note to place with what is typed.
    private var editing: (annotation: PDFAnnotation?, note: PDFNote, page: PDFPage, placed: ((PDFNote) -> Void)?)?
    /// The text view the note's text is typed in, while it is open.
    private(set) var textView: NSTextView?
    /// The typing's own history while the note is open, as a text box keeps its own: the PDF's history gets one step,
    /// "Edit Note" or "Add Note", when the note closes.
    private var typingUndoManager = UndoManager()

    static let textSize = NSSize(width: 240, height: 140)

    init(session: PDFSession, view: PDFView) {
        self.session = session
        self.pdfView = view
    }

    var isOpen: Bool { popover?.isShown == true }

    /// Opens a note on the page to read and edit.
    func open(_ annotation: PDFAnnotation, on page: PDFPage) {
        guard let note = PDFNote(annotation: annotation) else { return }
        show(note, annotation: annotation, on: page, placed: nil)
    }

    /// Opens a new note to type in; it is placed when it closes with text, and `placed` is told.
    func openNew(_ note: PDFNote, on page: PDFPage, placed: @escaping (PDFNote) -> Void) {
        show(note, annotation: nil, on: page, placed: placed)
    }

    /// Closes the note being read, keeping what was typed, at once: the popover finishes closing a moment later.
    func close() {
        let closing = popover
        commit()
        closing?.performClose(nil)
    }

    private func show(_ note: PDFNote, annotation: PDFAnnotation?, on page: PDFPage, placed: ((PDFNote) -> Void)?) {
        close()
        guard let pdfView, pdfView.window != nil else { return }
        let textView = NSTextView(frame: NSRect(origin: .zero, size: Self.textSize))
        textView.string = note.contents
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        typingUndoManager = UndoManager()
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.setAccessibilityLabel("Note")
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        let controller = NSViewController()
        controller.view = scrollView
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = Self.textSize
        popover.behavior = .transient
        popover.delegate = self
        editing = (annotation, note, page, placed)
        self.textView = textView
        self.popover = popover
        let anchor = pdfView.convert(note.iconBounds, from: page)
        popover.show(relativeTo: anchor, of: pdfView, preferredEdge: .maxX)
        popover.contentViewController?.view.window?.makeFirstResponder(textView)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { typingUndoManager }

    /// A click elsewhere closed the popover: what was typed is kept. One `close` already kept is not kept again.
    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        commit()
    }

    /// Keeps the text typed: a new note with text is placed, an edited note is changed; nothing else is a step.
    private func commit() {
        guard let editing, let session else { return }
        let typed = textView?.string ?? editing.note.contents
        self.editing = nil
        popover = nil
        textView = nil
        var changed = editing.note
        changed.contents = typed
        do {
            if let annotation = editing.annotation {
                guard typed != editing.note.contents else { return }
                try session.changeNote(annotation, on: editing.page, to: changed, actionName: "Edit Note")
            } else {
                guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                try session.addNote(changed, on: editing.page)
                editing.placed?(changed)
            }
        } catch { session.reportFailedChange(error) }
    }
}
#endif
