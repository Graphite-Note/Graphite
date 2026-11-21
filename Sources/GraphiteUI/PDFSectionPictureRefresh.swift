/**
 * File: PDFSectionPictureRefresh.swift
 * ------------------------------------
 * Layer: UI
 * Description: Keeps the pictures of notes' sections on a PDF's pages up to date: when a page with one comes into
 *              view, or a note changes while it is in view, a section whose text changed is drawn again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple

extension PDFSession {
    /// Draws again the section pictures of these pages whose section's text changed since
    /// they were drawn (`PDFPicture.sectionTextDigest`), keeping each picture's width, top
    /// edge and place in the stacking order. Not a step of the history: nobody changed the
    /// PDF by hand, and a picture an undo puts back is drawn again in turn.
    ///
    /// - Returns: How many pictures were drawn again.
    @discardableResult
    func refreshSectionPictures(onPages pageIndices: [Int], actions: PDFSectionLinkActions) async -> Int {
        guard !isProtected else { return 0 }
        var refreshedCount = 0
        for pageIndex in pageIndices where !Task.isCancelled {
            guard let page = document.page(at: pageIndex) else { continue }
            for picture in pictures(on: page) {
                guard let address = picture.sectionLinkAddress, let url = URL(string: address), let link = SectionLink(openingURL: url),
                      let digest = await actions.currentDigest(link), digest != picture.sectionTextDigest,
                      let prepared = try? await actions.prepare(link), // A section that cannot be drawn keeps its picture.
                      let size = PictureNaturalSize.measure(ofImageData: prepared.imageData)?.shownPixelSize, size.width > 0 else { continue }
                // The page may have changed while the section was drawn.
                guard page.document === document, let currentIndex = Optional(document.index(for: page)), currentIndex != NSNotFound,
                      let current = pictures(on: page).first(where: { candidate in candidate.name == picture.name }) else { continue }
                var refreshed = current
                refreshed.imageData = prepared.imageData
                refreshed.sectionTextDigest = prepared.textDigest
                let height = current.bounds.width * size.height / size.width
                refreshed.bounds = CGRect(x: current.bounds.minX, y: current.bounds.maxY - height, width: current.bounds.width, height: height)
                do {
                    try apply(.replacePicture(current.reference(onPageAt: currentIndex), with: refreshed))
                    NotificationCenter.default.post(name: PDFSession.picturesDidChange, object: self)
                    refreshedCount += 1
                } catch {
                    reportFailedChange(error)
                }
            }
        }
        return refreshedCount
    }
}

/// Drawn behind a PDF pane: refreshes the section pictures of the pages in view when the set
/// of pages in view changes and when the vault's notes change. It alone reads the index's
/// version, so the pane is not drawn again for each change of a note; a new change or new
/// pages cancel the refresh under way and start another.
struct PDFSectionPictureRefresh: View {
    /// The index's version (`WorkspaceModel.indexVersion`), which moves with every change of a note.
    let indexVersion: () -> Int
    let session: PDFSession
    let actions: PDFSectionLinkActions
    @State private var pagesInView: [Int] = []

    private struct RefreshKey: Equatable {
        let indexVersion: Int
        let pagesInView: [Int]
    }

    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .PDFViewVisiblePagesChanged)) { notification in
                if (notification.object as? PDFView) === session.pdfView { pagesInView = currentPagesInView() }
            }
            .onAppear { pagesInView = currentPagesInView() }
            .task(id: RefreshKey(indexVersion: indexVersion(), pagesInView: pagesInView)) {
                await session.refreshSectionPictures(onPages: pagesInView, actions: actions)
            }
    }

    private func currentPagesInView() -> [Int] {
        guard let pdfView = session.pdfView, let document = pdfView.document else { return [] }
        return pdfView.visiblePages.map { page in document.index(for: page) }.filter { pageIndex in pageIndex != NSNotFound }
    }
}
