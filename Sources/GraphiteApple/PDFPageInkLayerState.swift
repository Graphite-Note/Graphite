/**
 * File: PDFPageInkLayerState.swift
 * --------------------------------
 * Layer: Apple
 * Description: A PDF document Graphite shows, and which of its pages have their ink drawn in one layer per page on the
 *              Mac rather than by PDFKit, stroke by stroke.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import Foundation
import PDFKit
import Synchronization

/// A document Graphite shows and never writes (`PDFPageManager.prepareForDisplay`), with the state of its pages' ink
/// layers (`PDFPageInkLayerState`).
public final class PDFShownDocument: PDFDocument {
    public let pageInkLayers = PDFPageInkLayerState()
}

/// Which pages of a shown document have their Graphite ink drawn by a layer of their own on the Mac.
///
/// PDFKit on the Mac gives every annotation a layer of its own and draws each stroke in it, on the main thread, the first
/// time it makes a page's view: a page written with 520 strokes, parsed from their saved appearances one by one, stopped
/// a note's scrolling for 50 to 66 ms each time a handwritten PDF came into view (HUNT-357, 2026-11-16). On a page of
/// the file as it was read, while its view draws the page's ink in one layer from a separate copy of the file, off the
/// main thread (`MacPDFPageInkLayers`), the strokes' own layers draw nothing (`PDFShownInkAnnotation`). A page that was
/// edited, or that came from another PDF, is drawn by PDFKit as before, so what it shows is always the live document.
///
/// PDFKit may draw annotations off the main thread, so the state is behind a lock.
public final class PDFPageInkLayerState: Sendable {
    private struct Fields {
        /// How many views draw this document's ink in page layers; none, and PDFKit draws every stroke.
        var drawingViewCount = 0
        /// Pages PDFKit draws again, by identity: edited since the file was read, zoomed in too far for one picture, or
    /// whose layer could not be drawn.
        var pagesDrawnByPDFKit = Set<ObjectIdentifier>()
    }

    private let fields = Mutex(Fields())

    public init() {}

    /// A view's claim to draw the document's ink in page layers, from before PDFKit first draws a page until it is let go.
    public final class DrawingClaim: Sendable {
        private let state: PDFPageInkLayerState

        fileprivate init(state: PDFPageInkLayerState) {
            self.state = state
            state.fields.withLock { fields in fields.drawingViewCount += 1 }
        }

        // When no view claims the document, PDFKit draws every stroke again.
        deinit {
            state.fields.withLock { fields in fields.drawingViewCount = max(0, fields.drawingViewCount - 1) }
        }
    }

    /// A view starts drawing the document's ink in page layers, until it lets the claim go.
    public func claimDrawing() -> DrawingClaim {
        DrawingClaim(state: self)
    }

    /// PDFKit draws this page's ink from now on.
    public func letPDFKitDraw(_ page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        fields.withLock { fields in _ = fields.pagesDrawnByPDFKit.insert(identifier) }
    }

    /// The page's layer draws its ink again, as when a zoom that was too deep for it ends.
    public func takeBack(_ page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        fields.withLock { fields in _ = fields.pagesDrawnByPDFKit.remove(identifier) }
    }

    /// Whether PDFKit draws this page's ink because of `letPDFKitDraw(_:)`.
    public func isDrawnByPDFKit(_ page: PDFPage) -> Bool {
        let identifier = ObjectIdentifier(page)
        return fields.withLock { fields in fields.pagesDrawnByPDFKit.contains(identifier) }
    }

    /// Whether the page's Graphite ink is drawn by its page layer: a page of the file the document was read from, while a
    /// view draws page layers and PDFKit was not given the page back.
    public func drawsInk(of page: PDFPage, in document: PDFDocument) -> Bool {
        guard let corePage = page.pageRef, let documentReference = document.documentRef, corePage.document === documentReference else { return false }
        let identifier = ObjectIdentifier(page)
        return fields.withLock { fields in fields.drawingViewCount > 0 && !fields.pagesDrawnByPDFKit.contains(identifier) }
    }
}

public extension PDFAnnotation {
    /// Whether this is Graphite's ink on a page whose ink is drawn by the page's layer on the Mac
    /// (`PDFPageInkLayerState`), so its own layer draws nothing.
    var isDrawnByPageInkLayer: Bool {
        #if os(macOS)
        guard let page, let document = page.document as? PDFShownDocument, value(forAnnotationKey: PDFPageManager.groupKey) != nil else { return false }
        return document.pageInkLayers.drawsInk(of: page, in: document)
        #else
        return false
        #endif
    }
}
