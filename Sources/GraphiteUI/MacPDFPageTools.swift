/**
 * File: MacPDFPageTools.swift
 * ---------------------------
 * Layer: UI
 * Description: The Mac markup row's page tools in one PDF view: Draw, Eraser and Text Box, which take the pointer
 *              from PDFKit through a surface over the view while one of them is chosen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import GraphiteApple

/// The page tools of the Mac's markup row in one PDF view. Nothing of them exists until a
/// page tool is first chosen: then a surface (`MacPDFToolSurface`) goes over the view while
/// that tool stays chosen, and hands each press to the tool's handler.
@MainActor
final class MacPDFPageTools {
    private weak var session: PDFSession?
    private weak var view: PDFView?
    private(set) var tool = PDFMarkupTool.textSelection
    private var surface: MacPDFToolSurface?
    private var pointerInk: MacPDFPointerInkTool?
    private var textBoxes: MacPDFTextBoxTool?
    /// The pane's markup row, whose colour and width the next stroke takes.
    weak var toolbar: PDFMarkupToolbar?
    /// Where the Text Box tool keeps the look of the last box formatted (`PDFTextBoxDefaults`).
    private let preferences: UserDefaults
    /// The date a stroke is given when it is drawn.
    private let currentDate: () -> Date

    init(session: PDFSession, view: PDFView, preferences: UserDefaults, currentDate: @escaping () -> Date) {
        self.session = session
        self.view = view
        self.preferences = preferences
        self.currentDate = currentDate
    }

    /// Follows the row's tool: a page tool puts the surface over the view, any other takes it away.
    func use(_ newTool: PDFMarkupTool) {
        guard newTool != tool else { return }
        if tool == .textBox { textBoxes?.toolWasPutDown() }
        pointerInk?.cancelStroke()
        tool = newTool
        guard let view, let session else { return }
        if newTool.takesPagePresses {
            let surface = surface ?? MacPDFToolSurface(tools: self, frame: view.bounds)
            self.surface = surface
            if surface.superview !== view {
                surface.frame = view.bounds
                view.addSubview(surface)
            }
            if newTool == .textBox, textBoxes == nil { textBoxes = MacPDFTextBoxTool(session: session, view: view, surface: surface, preferences: preferences) }
            if newTool == .draw || newTool == .eraseInk, pointerInk == nil { pointerInk = MacPDFPointerInkTool(session: session, view: view, surface: surface) }
            view.window?.invalidateCursorRects(for: surface)
        } else {
            surface?.removeFromSuperview()
        }
    }

    /// Ends what the tools observe; called when the PDF view is taken down.
    func stop() {
        textBoxes?.stop()
        pointerInk?.cancelStroke()
        surface?.removeFromSuperview()
    }

    // MARK: Events from the surface

    /// Whether a press at a point of the PDF view is the chosen tool's: on a page, and not
    /// in the text box being typed in, whose own view takes it.
    func takesPress(atViewPoint viewPoint: CGPoint) -> Bool {
        guard tool.takesPagePresses, let view, view.page(for: viewPoint, nearest: false) != nil else { return false }
        if tool == .textBox, textBoxes?.editorContains(viewPoint: viewPoint) == true { return false }
        return true
    }

    func cursor(atViewPoint viewPoint: CGPoint) -> NSCursor? {
        guard takesPress(atViewPoint: viewPoint) else { return nil }
        switch tool {
        case .draw, .eraseInk: return .crosshair
        case .textBox: return textBoxes?.cursor(atViewPoint: viewPoint) ?? .iBeam
        case .textSelection, .highlight: return nil
        }
    }

    func mouseDown(_ event: NSEvent) {
        guard let view else { return }
        // Delete, Escape and ⌘D reach the tools through the PDF view's keyboard handling.
        if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
        let viewPoint = view.convert(event.locationInWindow, from: nil)
        switch tool {
        case .draw: pointerInk?.beginStroke(at: viewPoint, timeSeconds: event.timestamp, style: toolbar?.inkStyle ?? .default)
        case .eraseInk: pointerInk?.beginErasing(at: viewPoint)
        case .textBox: textBoxes?.mouseDown(at: viewPoint, clickCount: event.clickCount)
        case .textSelection, .highlight: break
        }
    }

    func mouseDragged(_ event: NSEvent) {
        guard let view else { return }
        let viewPoint = view.convert(event.locationInWindow, from: nil)
        switch tool {
        case .draw: pointerInk?.continueStroke(to: viewPoint, timeSeconds: event.timestamp)
        case .eraseInk: pointerInk?.continueErasing(at: viewPoint)
        case .textBox: textBoxes?.mouseDragged(to: viewPoint)
        case .textSelection, .highlight: break
        }
    }

    func mouseUp(_ event: NSEvent) {
        guard let view else { return }
        let viewPoint = view.convert(event.locationInWindow, from: nil)
        switch tool {
        case .draw: pointerInk?.endStroke(at: viewPoint, timeSeconds: event.timestamp, creationDate: currentDate())
        case .eraseInk: pointerInk?.endErasing()
        case .textBox: textBoxes?.mouseUp(at: viewPoint)
        case .textSelection, .highlight: break
        }
    }

    /// Takes the keys of the chosen tool: Delete, Escape, Return and ⌘D for a text box.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard tool == .textBox, let textBoxes else { return false }
        return textBoxes.handleKeyDown(event)
    }

    func menu(for event: NSEvent) -> NSMenu? {
        guard tool == .textBox, let view, let textBoxes else { return nil }
        return textBoxes.menu(atViewPoint: view.convert(event.locationInWindow, from: nil))
    }

    func drawOverlay(in surface: NSView, of pdfView: PDFView) {
        switch tool {
        case .draw: pointerInk?.drawStrokeUnderWay(in: surface, of: pdfView)
        case .textBox: textBoxes?.drawSelectionFrame(in: surface, of: pdfView)
        case .eraseInk, .textSelection, .highlight: break
        }
    }
}
#endif
