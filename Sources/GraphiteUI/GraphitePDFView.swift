/**
 * File: GraphitePDFView.swift
 * ---------------------------
 * Layer: UI
 * Description: The PDF view's SwiftUI representables on the iPad, the iPhone and the Mac; the views, the canvases and
 *              the coordinator they make have files of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.44
 * Date: 17/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple

#if canImport(UIKit)
import UIKit
import PencilKit

struct GraphitePDFView: UIViewRepresentable {
    let session: PDFSession
    var input: PDFAnnotationInput
    /// Smaller gaps between pages, for the viewer embedded in a note.
    var isEmbedded = false
    /// The page shown first, once the view has its size. Read when the view is made, not
    /// in the body that makes it, so a page turned does not update the pane around it.
    var initialPageIndex: () -> Int? = { nil }
    /// Called when drawing or selecting text begins, so the PDF's side of the split is focused.
    var beginInteraction: (() -> Void)?
    /// Links and quotes offered for selected text; nil where there is no note to link from.
    var linkActions: PDFLinkActions?
    /// Called when an Apple Pencil touches a page while reading: picking up the Pencil
    /// switches to writing, as Apple asks that a Pencil can mark without a mode being chosen
    /// first. Nil where reading stays reading (a protected PDF, an embed).
    var beginWritingWithPencil: (() -> Void)?
    var readingHighlights: [PDFReadAloudHighlight] = []
    var followsReading = false
    var suspendReadingFollow: (() -> Void)?
    /// Where the word being read is in the window, and the window, so the floating player
    /// keeps out of its way.
    var reportReadingHighlightFrame: ((CGRect?, CGRect?) -> Void)?
    /// Where the Read Aloud pen tapped; nil where the PDF is not read aloud.
    var readAloudPen: ((PDFReadAloudPenTap) -> Void)?
    /// The Read Aloud pen's start and end, shown over their pages.
    var readAloudMarkers: [PDFReadAloudMarker] = []
    /// Where the floating Pencil palette covers the window, or nil, for the floating player.
    var reportPaletteFrame: ((CGRect?) -> Void)?
    /// The note a PDF embedded in a note belongs to, for the lasso's pictures; a PDF pane's
    /// is the note beside it, from `linkActions`.
    var noteDestination: LassoNoteDestination?
    /// Where the view is kept while its tab is hidden, to come back as it was; nil outside a
    /// window, where it goes. An embed's view always goes with its note.
    @Environment(\.hiddenPDFViews) private var hiddenViews

    func makeCoordinator() -> PDFAnnotationCoordinator {
        if !isEmbedded, let keptCoordinator = hiddenViews?.coordinator(for: session) { return keptCoordinator }
        let coordinator = PDFAnnotationCoordinator(session: session, isEmbedded: isEmbedded)
        coordinator.viewGeneration = session.viewGeneration
        return coordinator
    }

    func makeUIView(context: Context) -> GraphitePDFDisplayView {
        // The view of a tab shown again, as it was left: its pages drawn, its canvases with
        // their ink, its zoom and place (HUNT-308).
        if !isEmbedded, let keptView = hiddenViews?.takeView(keptWith: context.coordinator) {
            keptView.removeFromSuperview()
            context.coordinator.resume()
            session.livePlace = { [weak keptView] in keptView?.pagePlace }
            session.pdfView = keptView
            return keptView
        }
        let view = GraphitePDFDisplayView()
        view.contentChangeCount = { [weak session] in session?.changeVersion ?? 0 }
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .secondarySystemBackground
        // A picture placed on a page is drawn from all its pixels at any size: below high
        // quality, a picture made smaller than its pixels shows jagged, pixelated edges.
        view.interpolationQuality = .high
        if isEmbedded {
            let margin = PDFEmbedFitting.pageMargin
            view.pageBreakMargins = UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
            PDFViewDocumentAnalysis.turnOff(in: view)
        }
        // PDFKit asks for page overlays only when it creates page views, so the provider
        // must be in place before the document is.
        view.pageOverlayViewProvider = context.coordinator
        view.document = session.document
        // The place the PDF was left at, when there is one: back from another tab, after a
        // reload, or after Graphite quit. It is the page at the top edge, which can be the
        // one before the page PDFKit counts as current, across the view's middle.
        let keptPlace = session.keptPlace.flatMap { place in place.pageIndex < session.document.pageCount ? place : nil }
        view.pendingInitialPage = (keptPlace?.pageIndex ?? initialPageIndex()).flatMap(session.document.page(at:))
        view.pendingInitialFractionFromTop = keptPlace.map { place in CGFloat(place.fractionFromTop) }
        session.livePlace = { [weak view] in view?.pagePlace }
        // The system find bar (⌘F, or the toolbar's Find), which PDFKit fills with its
        // matches. A PDF embedded in a note leaves ⌘F to the note.
        view.isFindInteractionEnabled = !isEmbedded
        context.coordinator.attach(to: view)
        context.coordinator.beginInteraction = beginInteraction
        context.coordinator.linkActions = linkActions
        context.coordinator.noteDestination = noteDestination ?? linkActions?.noteDestination
        context.coordinator.beginWritingWithPencil = beginWritingWithPencil
        session.pdfView = view
        return view
    }

    func updateUIView(_ view: GraphitePDFDisplayView, context: Context) {
        context.coordinator.hiddenViews = isEmbedded ? nil : hiddenViews
        context.coordinator.beginInteraction = beginInteraction
        context.coordinator.linkActions = linkActions
        context.coordinator.noteDestination = noteDestination ?? linkActions?.noteDestination
        context.coordinator.beginWritingWithPencil = beginWritingWithPencil
        context.coordinator.readAloudPen = readAloudPen
        context.coordinator.reportPaletteFrame = reportPaletteFrame
        context.coordinator.update(input: input)
        context.coordinator.highlightReading(readingHighlights, followsReading: followsReading, suspendFollowing: suspendReadingFollow,
                                             reportFrame: reportReadingHighlightFrame)
        context.coordinator.showReadAloudMarkers(readAloudMarkers)
    }

    static func dismantleUIView(_ view: GraphitePDFDisplayView, coordinator: PDFAnnotationCoordinator) {
        // A view made for the PDF again comes back here, unless a newer view of it already shows it.
        let isNewestView = coordinator.session.pdfView === view || coordinator.session.pdfView == nil
        if isNewestView, let place = view.pagePlace { coordinator.session.keptPlace = place }
        // A tab hidden keeps its view, so showing it again builds nothing; a view built again,
        // or one a newer view replaced, goes.
        if isNewestView, !coordinator.isEmbedded, coordinator.session.viewGeneration == coordinator.viewGeneration,
           let hiddenViews = coordinator.hiddenViews {
            hiddenViews.keep(view, coordinator: coordinator)
        } else {
            coordinator.detach()
        }
    }
}

#else
import AppKit

struct GraphitePDFView: NSViewRepresentable {
    let session: PDFSession
    var input: PDFAnnotationInput
    var isEmbedded = false
    var initialPageIndex: () -> Int? = { nil }
    /// The Mac viewer has no Pencil canvases; accepted so both platforms share one call.
    var beginInteraction: (() -> Void)?
    var linkActions: PDFLinkActions?
    /// The Mac has no Apple Pencil; accepted so both platforms share one call.
    var beginWritingWithPencil: (() -> Void)?
    var readingHighlights: [PDFReadAloudHighlight] = []
    var followsReading = false
    var suspendReadingFollow: (() -> Void)?
    /// Accepted so both platforms share one call; the Mac has no floating player.
    var reportReadingHighlightFrame: ((CGRect?, CGRect?) -> Void)?
    /// The Mac has no Pencil canvases, so no Read Aloud pen; accepted so both platforms share one call.
    var readAloudPen: ((PDFReadAloudPenTap) -> Void)?
    var readAloudMarkers: [PDFReadAloudMarker] = []
    var reportPaletteFrame: ((CGRect?) -> Void)?
    /// The Mac viewer has no lasso; accepted so both platforms share one call.
    var noteDestination: LassoNoteDestination?

    final class Coordinator {
        var pageObserver: PDFViewPageObserver?
        weak var session: PDFSession?
        var markupInteraction: MacPDFMarkupInteraction?
        /// Draws each page's ink in one layer (`MacPDFPageInkLayers`); nil when PDFKit draws every stroke.
        var pageInkLayers: MacPDFPageInkLayers?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = GraphiteMacPDFView()
        view.contentChangeCount = { [weak session] in session?.changeVersion ?? 0 }
        view.documentUndoManager = session.undoManager
        // Before the document is shown, so PDFKit never draws the strokes of a page whose layer draws them.
        let pageInkLayers = MacPDFPageInkLayers(session: session, view: view)
        context.coordinator.pageInkLayers = pageInkLayers
        view.pageInkLayers = pageInkLayers
        view.pageOverlayViewProvider = pageInkLayers
        if isEmbedded { PDFViewDocumentAnalysis.turnOff(in: view) }
        view.document = session.document
        view.autoScales = true
        view.interpolationQuality = .high
        view.displayMode = .singlePageContinuous
        // Back where the PDF was left, as on the iPad: from another tab, or after Graphite
        // quit. The Mac went to the top of the current page at best, before the view had
        // a size, which PDFKit can ignore.
        let keptPlace = session.keptPlace.flatMap { place in place.pageIndex < session.document.pageCount ? place : nil }
        view.pendingPlace = keptPlace ?? initialPageIndex().map { pageIndex in PDFPagePlace(pageIndex: pageIndex, fractionFromTop: 0) }
        session.livePlace = { [weak view] in view?.pagePlace }
        context.coordinator.session = session
        context.coordinator.pageObserver = PDFViewPageObserver(session: session, view: view)
        let markupInteraction = MacPDFMarkupInteraction(session: session, view: view)
        context.coordinator.markupInteraction = markupInteraction
        view.markupInteraction = markupInteraction
        session.visiblePageCenter = { [weak view] in view?.visiblePageCenter() }
        if !isEmbedded {
            let pictureDrops = MacPDFPictureDropTarget(session: session, view: view)
            pictureDrops.picturesWerePlaced = { [weak view] in view?.markupInteraction?.toolbar?.choose(.pictures) }
            view.pictureDrops = pictureDrops
            view.registerForDraggedTypes(MacPDFPictureDropTarget.pasteboardTypes)
        }
        session.pdfView = view
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.pageObserver?.highlightReading(readingHighlights, followsReading: followsReading, suspendFollowing: suspendReadingFollow)
        if let markupInteraction = context.coordinator.markupInteraction {
            markupInteraction.input = input
            markupInteraction.linkActions = linkActions
            if markupInteraction.toolbar !== context.environment.pdfMarkupToolbar { markupInteraction.toolbar = context.environment.pdfMarkupToolbar }
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        if let session = coordinator.session, session.pdfView === view || session.pdfView == nil,
           let place = (view as? GraphiteMacPDFView)?.pagePlace {
            session.keptPlace = place
        }
        coordinator.pageObserver?.stop()
        coordinator.markupInteraction?.stopObservingSelection()
        coordinator.pageInkLayers?.stop()
    }
}

#endif
