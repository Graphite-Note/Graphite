/**
 * File: PDFViewPageObserver.swift
 * -------------------------------
 * Layer: UI
 * Description: Follows the page a PDF view shows and its scrolling, on the iPad, the iPhone and the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple

/// Follows what a PDF view shows, on both platforms.
///
/// The session's current page stays on the page in view: page actions, the page field and
/// "Open in PDF View" act on it. Form fields on the pages shown are made read-only in the
/// live document. Graphite records no edit for a typed value, so a save, which replays the
/// recorded edits on the file as it was read, would drop the value without a word.
@MainActor
final class PDFViewPageObserver: NSObject {
    private let session: PDFSession
    private weak var view: PDFView?
    private var notificationObservers: [NSObjectProtocol] = []
    private let readingHighlighter = PDFReadAloudHighlighter()
    private var suspendReadingFollow: (() -> Void)?
    #if canImport(UIKit)
    private weak var observedScrollView: UIScrollView?
    #else
    private var scrollMonitor: Any?
    #endif

    init(session: PDFSession, view: PDFView) {
        self.session = session
        self.view = view
        super.init()
        notificationObservers = [
            NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCurrentPage() }
            },
            NotificationCenter.default.addObserver(forName: .PDFViewVisiblePagesChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.makeFormFieldsReadOnlyOnVisiblePages() }
            },
            NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let selection = self.view?.currentSelection
                    // Capture geometry here; extract bounded text only when the
                    // user asks to read, rather than on every selection change.
                    self.session.readAloudSelection = selection?.pages.isEmpty == false ? selection?.copy() as? PDFSelection : nil
                }
            },
        ]
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewDisplayModeChanged, .PDFViewDisplayBoxChanged,
                     .PDFViewVisiblePagesChanged, .PDFViewDocumentChanged] {
            notificationObservers.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let view = self.view else { return }
                    self.readingHighlighter.refreshGeometry(in: view)
                    self.reportHighlightFrameIfNeeded()
                }
            })
        }
        makeFormFieldsReadOnlyOnVisiblePages()
    }

    func stop() {
        if let view { readingHighlighter.clear(in: view) }
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        notificationObservers.removeAll()
        #if canImport(UIKit)
        observedScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(manualScrollBegan(_:)))
        observedScrollView?.pinchGestureRecognizer?.removeTarget(self, action: #selector(manualScrollBegan(_:)))
        observedScrollView = nil
        scrollOffsetObservation = nil
        #else
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        #endif
        suspendReadingFollow = nil
    }

    func highlightReading(_ highlights: [PDFReadAloudHighlight], followsReading: Bool = false, suspendFollowing: (() -> Void)? = nil,
                          reportFrame: ((CGRect?, CGRect?) -> Void)? = nil) {
        suspendReadingFollow = suspendFollowing
        reportHighlightFrame = reportFrame
        installManualScrollObservation()
        if let view { readingHighlighter.update(highlights, in: view, followsReading: followsReading) }
        reportHighlightFrameIfNeeded()
    }

    private var reportHighlightFrame: ((CGRect?, CGRect?) -> Void)?
    #if canImport(UIKit)
    private var scrollOffsetObservation: NSKeyValueObservation?
    #endif

    /// Tells the floating player where the word being read is on screen, as the page moves.
    private func reportHighlightFrameIfNeeded() {
        guard let reportHighlightFrame else { return }
        #if canImport(UIKit)
        if let scrollView = view?.documentView?.enclosingScrollView, scrollOffsetObservation == nil {
            scrollOffsetObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportHighlightFrameIfNeeded() }
            }
        }
        guard let view, let window = view.window else { reportHighlightFrame(nil, nil); return }
        guard let wordFrame = readingHighlighter.highlightFrame(in: view) else { reportHighlightFrame(nil, window.bounds); return }
        let frameInWindow = view.convert(wordFrame, to: nil)
        reportHighlightFrame(view.bounds.intersects(wordFrame) ? frameInWindow : nil, window.bounds)
        #endif
    }

    private func installManualScrollObservation() {
        guard suspendReadingFollow != nil else { return }
        #if canImport(UIKit)
        guard let scrollView = view?.documentView?.enclosingScrollView, scrollView !== observedScrollView else { return }
        observedScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(manualScrollBegan(_:)))
        observedScrollView?.pinchGestureRecognizer?.removeTarget(self, action: #selector(manualScrollBegan(_:)))
        observedScrollView = scrollView
        // A pinch pauses following as a scroll does: following took back every pinch.
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(manualScrollBegan(_:)))
        scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(manualScrollBegan(_:)))
        #else
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let view = self.view, event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return }
                self.suspendReadingFollow?()
            }
            return event
        }
        #endif
    }

    #if canImport(UIKit)
    @objc private func manualScrollBegan(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began { suspendReadingFollow?() }
    }
    #endif

    func updateCurrentPage() {
        guard let page = view?.currentPage else { return }
        let pageIndex = session.document.index(for: page)
        if pageIndex != NSNotFound, session.currentPageIndex != pageIndex { session.currentPageIndex = pageIndex }
    }

    /// Reads PDFKit's annotations only of the pages that hold form fields (`PDFFormFieldPages`): reading them makes
    /// every annotation of the page, each stroke of a handwritten page among them.
    func makeFormFieldsReadOnlyOnVisiblePages() {
        for page in view?.visiblePages ?? []
        where PDFFormFieldPages.mayHaveFormField(page, in: session.document, pageNumbers: session.formFieldPageNumbers) {
            // PDFKit reports the subtype without the leading slash of `PDFAnnotationSubtype`.
            for annotation in page.annotations where annotation.type == "Widget" && !annotation.isReadOnly {
                annotation.isReadOnly = true
            }
        }
    }
}
