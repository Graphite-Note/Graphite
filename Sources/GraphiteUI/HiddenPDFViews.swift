/**
 * File: HiddenPDFViews.swift
 * --------------------------
 * Layer: UI
 * Description: The PDF view of a hidden tab, kept with its canvases, zoom and place, so showing the tab again shows the
 *              page at once instead of building the view, decoding every page's ink and fitting the zoom again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import SwiftUI

#if canImport(UIKit)
import UIKit

/// The PDF views a window keeps while their tabs are hidden: at most one, the PDF most recently left, as the window
/// keeps at most one hidden PDF session open (PDF-13). Showing a tab again built a new view: the document laid out
/// again, every page shown drawn again, each page's ink decoded again into a new canvas, and the zoom fitted again
/// before the place was restored, which the owner recorded on 2026-11-04 as a blank page for seconds and the wrong zoom
/// first (HUNT-308). A view kept here comes back as it was left.
///
/// A kept view goes when its session is no longer any tab's (`keepOnly`), when another view is kept, at a memory
/// warning, and when its session's view is built again (`PDFSession.viewGeneration`).
@MainActor
final class HiddenPDFViews {
    /// A view kept for its session, with the coordinator of its canvases.
    struct KeptView {
        let view: GraphitePDFDisplayView
        let coordinator: PDFAnnotationCoordinator
    }

    /// How many views are kept: the PDF most recently left.
    static let maximumKeptViewCount = 1

    private var keptViews: [KeptView] = []
    private let notificationCenter: NotificationCenter
    private var memoryWarningObserver: (any NSObjectProtocol)?
    /// For tests: how many views were kept and how many shown again.
    private(set) var keptViewCount = 0
    private(set) var shownAgainCount = 0

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        memoryWarningObserver = notificationCenter.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                               queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.letGoOfAll() }
        }
    }

    isolated deinit {
        if let memoryWarningObserver { notificationCenter.removeObserver(memoryWarningObserver) }
        for keptView in keptViews { keptView.coordinator.detach() }
    }

    /// Keeps the view of a tab being hidden; a view kept before goes beyond `maximumKeptViewCount`.
    func keep(_ view: GraphitePDFDisplayView, coordinator: PDFAnnotationCoordinator) {
        letGo { keptView in keptView.coordinator.session === coordinator.session }
        coordinator.park()
        keptViews.append(KeptView(view: view, coordinator: coordinator))
        keptViewCount += 1
        while keptViews.count > Self.maximumKeptViewCount { keptViews.removeFirst().coordinator.detach() }
    }

    /// The coordinator of the session's kept view, which still shows the session as it is now, for the view to come
    /// back with; nil when none is kept, or the kept one is out of date, which then goes.
    func coordinator(for session: PDFSession) -> PDFAnnotationCoordinator? {
        guard let keptView = keptViews.first(where: { keptView in keptView.coordinator.session === session }) else { return nil }
        guard keptView.coordinator.canShowAgain else {
            letGo { candidate in candidate.coordinator === keptView.coordinator }
            return nil
        }
        return keptView.coordinator
    }

    /// Takes the view kept with this coordinator out, to be shown again.
    func takeView(keptWith coordinator: PDFAnnotationCoordinator) -> GraphitePDFDisplayView? {
        guard let index = keptViews.firstIndex(where: { keptView in keptView.coordinator === coordinator }) else { return nil }
        let keptView = keptViews.remove(at: index)
        shownAgainCount += 1
        return keptView.view
    }

    /// Lets go of every kept view whose session is not one of these.
    func keepOnly(sessions: [PDFSession]) {
        let keptSessions = Set(sessions.map(ObjectIdentifier.init))
        letGo { keptView in !keptSessions.contains(ObjectIdentifier(keptView.coordinator.session)) }
    }

    func letGoOfAll() {
        letGo { _ in true }
    }

    private func letGo(where shouldLetGo: (KeptView) -> Bool) {
        let leaving = keptViews.filter(shouldLetGo)
        keptViews.removeAll(where: shouldLetGo)
        for keptView in leaving { keptView.coordinator.detach() }
    }
}

extension EnvironmentValues {
    /// The window's kept PDF views, set by its root view; nil outside a window, where a hidden PDF's view goes.
    @Entry var hiddenPDFViews: HiddenPDFViews? = nil
}
#endif
