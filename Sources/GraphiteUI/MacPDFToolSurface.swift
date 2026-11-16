/**
 * File: MacPDFToolSurface.swift
 * -----------------------------
 * Layer: UI
 * Description: The transparent view over a Mac PDF view that takes the pointer's presses on pages while a page tool
 *              of the markup row (Draw, Eraser, Text Box) is chosen, and draws the stroke under way and the frame of
 *              the selected text box.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit

/// The view over a Mac PDF view that the page tools draw and type through. It covers the
/// PDF view and answers a press only where the chosen tool takes it (on a page, away from a
/// text box being typed in), so scrolling, zooming and everything else reach PDFKit.
final class MacPDFToolSurface: NSView {
    private weak var tools: MacPDFPageTools?

    init(tools: MacPDFPageTools, frame: NSRect) {
        self.tools = tools
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// `point` is in the PDF view's coordinates, the surface's superview, which it covers.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let tools, tools.takesPress(atViewPoint: point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) { tools?.mouseDown(event) }
    override func mouseDragged(with event: NSEvent) { tools?.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { tools?.mouseUp(event) }
    override func menu(for event: NSEvent) -> NSMenu? { tools?.menu(for: event) }

    // The surface takes presses, not scrolling or zooming: those go on to the PDF view's
    // own scroll view and magnification, as when no tool is chosen.
    override func scrollWheel(with event: NSEvent) {
        guard let scrollView = (superview as? PDFView)?.documentView?.enclosingScrollView else { return super.scrollWheel(with: event) }
        scrollView.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        if let pdfView = superview as? PDFView { pdfView.magnify(with: event) } else { super.magnify(with: event) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(for: event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(for: event) }

    private func updateCursor(for event: NSEvent) {
        guard let tools, let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        guard let cursor = tools.cursor(atViewPoint: point) else { return }
        cursor.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tools, let pdfView = superview as? PDFView else { return }
        tools.drawOverlay(in: self, of: pdfView)
    }
}
#endif
