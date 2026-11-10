/**
 * File: PDFTouchEvidence.swift
 * ----------------------------
 * Layer: UI
 * Description: What a touch on a PDF reaches and what decides whether the PDF answers it, for the health monitor's records and captures.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 10/11/2026
 */

import Foundation
import CoreGraphics

/// The link that has every PDF on screen write down what its touches reach and the state of
/// what decides whether it answers them (`PDFTouchStateCaptured-*.json`), for a PDF that takes
/// no touches while the monitor sees nothing wrong: `graphite://capture-pdf-touches`, opened
/// from the Mac while the iPad shows the PDF (`xcrun devicectl device process launch
/// --payload-url`), so the person need not touch anything.
enum PDFTouchCaptureLink {
    static let action = "capture-pdf-touches"

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "graphite" && url.host()?.lowercased() == action
    }
}

/// The last gestures a PDF's health monitor followed or left alone, and why, for a capture.
@MainActor
final class PDFGestureLog {
    static let limit = 12
    private(set) var entries: [String] = []
    private var notedCount = 0

    /// Entries are numbered from the monitor's first, so a capture shows how many came before.
    func note(_ text: String) {
        notedCount += 1
        entries.append("\(notedCount). \(text)")
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }
}

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteApple

/// What a touch on a PDF reaches and the state of everything that decides whether the PDF
/// answers it, written into the health monitor's records.
@MainActor
enum PDFTouchEvidence {
    /// What a touch at a point of the window reaches, and the state of everything that
    /// decides whether the PDF answers it.
    static func describe(touchAt pointInWindow: CGPoint, pdfView: GraphitePDFDisplayView?, coordinator: PDFAnnotationCoordinator?) -> [String: Any] {
        guard let pdfView, let window = pdfView.window else { return ["pdfView": "not in a window"] }
        let mainScrollView = pdfView.documentView?.enclosingScrollViewForHealth
        var fields: [String: Any] = [:]
        let touchedView = window.hitTest(pointInWindow, with: nil)
        fields["touchPoint"] = "\(Int(pointInWindow.x)), \(Int(pointInWindow.y))"
        fields["touchedViews"] = touchedView.map(Self.ancestry) ?? ["nothing"]
        fields["touchedViewIsInPDF"] = touchedView?.isDescendant(of: pdfView) ?? false
        fields["pdfViewAncestors"] = Self.ancestry(of: pdfView).prefix(12).map { $0 }
        fields["pdfFrameInWindow"] = NSCoder.string(for: pdfView.convert(pdfView.bounds, to: nil))
        fields["scaleFactor"] = Double(pdfView.scaleFactor)
        fields["autoScales"] = pdfView.autoScales
        if let scrollView = mainScrollView {
            fields["scrollView"] = [
                "isScrollEnabled": scrollView.isScrollEnabled,
                "isUserInteractionEnabled": scrollView.isUserInteractionEnabled,
                "contentOffset": NSCoder.string(for: scrollView.contentOffset),
                "contentSize": NSCoder.string(for: scrollView.contentSize),
                "zoomScale": Double(scrollView.zoomScale)
            ] as [String: Any]
        }
        fields["recognizers"] = recognizers(in: pdfView).map(Self.describe)
        fields["windowRecognizers"] = (window.gestureRecognizers ?? []).map(Self.describe)
        fields["pencil"] = PencilActivity.diagnosticDescription
        fields["canvases"] = coordinator?.canvasDiagnostics() ?? []
        fields["selectionFrames"] = Self.selectionFrames(in: window).map { frame in
            "\(NSCoder.string(for: frame.convert(frame.bounds, to: nil))) hidden \(frame.isHidden) alpha \(frame.alpha)"
        }
        fields["presentedViewController"] = window.rootViewController?.presentedViewController.map { String(describing: type(of: $0)) } ?? "none"
        return fields
    }

    private static func ancestry(of view: UIView) -> [String] {
        var names: [String] = []
        var current: UIView? = view
        while let shown = current {
            names.append("\(type(of: shown)) interaction \(shown.isUserInteractionEnabled) hidden \(shown.isHidden) alpha \(String(format: "%.2f", shown.alpha))")
            current = shown.superview
        }
        return names
    }

    private static func describe(_ recognizer: UIGestureRecognizer) -> String {
        let stateName: String
        switch recognizer.state {
        case .possible: stateName = "possible"
        case .began: stateName = "began"
        case .changed: stateName = "changed"
        case .ended: stateName = "ended"
        case .cancelled: stateName = "cancelled"
        case .failed: stateName = "failed"
        @unknown default: stateName = "unknown"
        }
        let viewName = recognizer.view.map { String(describing: type(of: $0)) } ?? "no view"
        return "\(type(of: recognizer)) on \(viewName): \(stateName), enabled \(recognizer.isEnabled), touches \(recognizer.numberOfTouches)"
    }

    private static func selectionFrames(in view: UIView) -> [SelectionFrameView] {
        ((view as? SelectionFrameView).map { [$0] } ?? []) + view.subviews.flatMap { subview in selectionFrames(in: subview) }
    }

    /// The PDF view's recognizers, its scroll views', and the page canvases', which a page's
    /// scrolling, zooming and drawing go through.
    static func recognizers(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap { subview in recognizers(in: subview) }
    }

    /// A followed gesture in a line: what it was, and how far the pages and the zoom went for it.
    static func summary(of gesture: UnansweredGestureCount.Gesture, reachedPDF: Bool, pagesMovedPoints: CGFloat,
                        zoomBefore: CGFloat, zoomAfter: CGFloat) -> String {
        "Followed: \(gesture.fingerCount) finger(s) moved \(Int(gesture.largestMovement)) pt, the pages \(Int(pagesMovedPoints)) pt, "
            + "zoom \(zoomBefore) to \(zoomAfter); answered \(gesture.wasAnswered), could move \(gesture.couldMove), reached the PDF \(reachedPDF), "
            + "finger draws \(gesture.drawsWithFinger), \(Int(min(gesture.secondsSincePencil, 9_999))) s since the Pencil, "
            + "on a selection frame \(gesture.beganOnSelectionFrame), at a screen edge \(gesture.beganAtSystemGestureEdge)"
    }
}

/// Has the PDFs on screen capture their touch state (`PDFTouchCaptureLink`).
@MainActor
enum PDFTouchCapture {
    /// The monitors alive, held weakly.
    static let monitors = NSHashTable<PDFPaneHealthMonitor>.weakObjects()

    /// True when the link asked for a capture, which every PDF in a window then writes.
    static func handle(_ url: URL) -> Bool {
        guard PDFTouchCaptureLink.matches(url) else { return false }
        for monitor in monitors.allObjects { monitor.captureTouchState() }
        DiagnosticContext.note("The PDFs' touch state was captured on request")
        return true
    }
}
#endif
