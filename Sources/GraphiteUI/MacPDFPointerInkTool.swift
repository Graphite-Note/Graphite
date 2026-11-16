/**
 * File: MacPDFPointerInkTool.swift
 * --------------------------------
 * Layer: UI
 * Description: The Mac's Draw tool and stroke eraser in one PDF view: the pointer's places while dragging, the
 *              stroke under way drawn over the page, and the strokes written to and removed from the page's ink.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import PencilKit
import GraphiteApple

/// The Draw tool and the stroke eraser of the Mac's markup row in one PDF view. A stroke
/// is drawn over the page while the mouse is down and written to the page's ink when it
/// is let go, one step of the history; the eraser removes each stroke it passes over and
/// records the whole pass as one step.
@MainActor
final class MacPDFPointerInkTool {
    private weak var session: PDFSession?
    private weak var view: PDFView?
    private weak var surface: NSView?
    /// The stroke under way: its page, its style, and the pointer's places on the page.
    private var strokeUnderWay: (page: PDFPage, style: PDFMarkupInkStyle, samples: [PDFPointerInkSample])?
    /// The eraser's pass under way: its page, the page's drawing when the pass began, and
    /// the pointer's last place in the page's drawing space.
    private var erasing: (page: PDFPage, drawingBefore: PKDrawing, lastDrawingPoint: CGPoint?)?
    /// The last page's ink as this tool left it, so a stroke reads the page's record again
    /// only after the page changed otherwise (`PDFSession.pointerInk(on:cached:)`).
    private var lastPageInk: (page: PDFPage, ink: PDFPointerPageInk)?

    init(session: PDFSession, view: PDFView, surface: NSView) {
        self.session = session
        self.view = view
        self.surface = surface
    }

    // MARK: Drawing

    func beginStroke(at viewPoint: CGPoint, timeSeconds: TimeInterval, style: PDFMarkupInkStyle) {
        guard let view, let page = view.page(for: viewPoint, nearest: false) else { return }
        strokeUnderWay = (page, style, [PDFPointerInkSample(pagePoint: view.convert(viewPoint, to: page), timeSeconds: timeSeconds)])
        surface?.needsDisplay = true
    }

    func continueStroke(to viewPoint: CGPoint, timeSeconds: TimeInterval) {
        guard let view, var stroke = strokeUnderWay else { return }
        stroke.samples.append(PDFPointerInkSample(pagePoint: view.convert(viewPoint, to: stroke.page), timeSeconds: timeSeconds))
        strokeUnderWay = stroke
        surface?.needsDisplay = true
    }

    /// - Parameter creationDate: The stroke's date, as PencilKit keeps one per stroke; it tells
    ///   two strokes of the same points apart (`PDFStrokeFingerprint`).
    func endStroke(at viewPoint: CGPoint, timeSeconds: TimeInterval, creationDate: Date) {
        continueStroke(to: viewPoint, timeSeconds: timeSeconds)
        guard let session, let stroke = strokeUnderWay else { return }
        strokeUnderWay = nil
        surface?.needsDisplay = true
        do {
            let coordinates = try PDFPointerInk.coordinates(of: stroke.page.bounds(for: .cropBox))
            guard let pencilStroke = PDFPointerInk.stroke(through: stroke.samples, style: stroke.style, coordinates: coordinates,
                                                          creationDate: creationDate) else { return }
            let ink = try session.pointerInk(on: stroke.page, cached: cachedInk(on: stroke.page))
            lastPageInk = (stroke.page, try session.addPointerStroke(pencilStroke, on: stroke.page, to: ink))
        } catch {
            session.reportFailedChange(error)
        }
    }

    /// Drops the stroke under way, as when another tool is chosen while the mouse is down.
    func cancelStroke() {
        strokeUnderWay = nil
        erasing = nil
        surface?.needsDisplay = true
    }

    private func cachedInk(on page: PDFPage) -> PDFPointerPageInk? {
        guard let lastPageInk, lastPageInk.page === page else { return nil }
        return lastPageInk.ink
    }

    // MARK: Erasing

    func beginErasing(at viewPoint: CGPoint) {
        guard let session, let view, let page = view.page(for: viewPoint, nearest: false) else { return }
        do {
            let ink = try session.pointerInk(on: page, cached: cachedInk(on: page))
            lastPageInk = (page, ink)
            erasing = (page, ink.drawing, nil)
            erase(at: viewPoint)
        } catch {
            session.reportFailedChange(error)
        }
    }

    func continueErasing(at viewPoint: CGPoint) {
        guard erasing != nil else { return }
        erase(at: viewPoint)
    }

    /// Records the pass as one step of the history.
    func endErasing() {
        guard let session, let erasing else { return }
        self.erasing = nil
        guard let ink = cachedInk(on: erasing.page) else { return }
        session.registerPointerInkStep(from: erasing.drawingBefore, to: ink.drawing, on: erasing.page)
    }

    private func erase(at viewPoint: CGPoint) {
        guard let session, let view, let erasing, let ink = cachedInk(on: erasing.page) else { return }
        do {
            let coordinates = try PDFPointerInk.coordinates(of: erasing.page.bounds(for: .cropBox))
            let drawingPoint = coordinates.overlayPoint(fromPDF: view.convert(viewPoint, to: erasing.page))
            self.erasing?.lastDrawingPoint = drawingPoint
            let touched = PDFPointerInk.indicesOfStrokes(in: ink.drawing, alongSegmentFrom: erasing.lastDrawingPoint ?? drawingPoint, to: drawingPoint)
            guard !touched.isEmpty else { return }
            lastPageInk = (erasing.page, try session.removePointerStrokes(at: touched, on: erasing.page, from: ink))
        } catch {
            session.reportFailedChange(error)
        }
    }

    // MARK: The stroke under way

    /// Draws the stroke under way over the page, at its width as the page is shown, until
    /// its ink is written when the mouse is let go.
    func drawStrokeUnderWay(in surface: NSView, of pdfView: PDFView) {
        guard let stroke = strokeUnderWay, let firstSample = stroke.samples.first else { return }
        let path = NSBezierPath()
        path.move(to: surface.convert(pdfView.convert(firstSample.pagePoint, from: stroke.page), from: pdfView))
        for sample in stroke.samples.dropFirst() { path.line(to: surface.convert(pdfView.convert(sample.pagePoint, from: stroke.page), from: pdfView)) }
        if stroke.samples.count == 1 { path.line(to: path.currentPoint) }
        path.lineWidth = max(1, CGFloat(stroke.style.width.points) * pdfView.scaleFactor)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let color = stroke.style.color
        NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1).setStroke()
        path.stroke()
    }
}
#endif
