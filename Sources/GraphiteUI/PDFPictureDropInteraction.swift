/**
 * File: PDFPictureDropInteraction.swift
 * -------------------------------------
 * Layer: UI
 * Description: Takes pictures dropped onto the pages of an iPad PDF view (from Photos, Files, Safari or Graphite's
 *              own sidebar) and places each where it landed; a protected or signed PDF takes none, and PDF files let go
 *              over a page are refused with the reason in the banner.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 21/11/2026
 */

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore

/// The drop interaction of a PDF pane's view. It is added when the view is made and costs
/// nothing until something is dragged over the view.
@MainActor
final class PDFPictureDropInteraction: NSObject, UIDropInteractionDelegate {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    private(set) var interaction: UIDropInteraction?
    /// The drag's last place was a page and it carries PDF files alone.
    private var refusedDragIsOverPage = false
    /// The workspace's part in section links; nil where the PDF takes none, as in a test of pictures.
    var sectionLinks: PDFSectionLinkActions?

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
        super.init()
        let interaction = UIDropInteraction(delegate: self)
        pdfView.addInteraction(interaction)
        self.interaction = interaction
    }

    func stop() {
        if let interaction { pdfView?.removeInteraction(interaction) }
        interaction = nil
    }

    /// Whether the PDF takes the dragged items: it can be changed, and one of them is a picture,
    /// or a note's section where the workspace draws sections.
    func takesDrop(of providers: [NSItemProvider]) -> Bool {
        !session.isProtected && providers.contains { provider in
            let kind = PDFPictureDropReader.kind(of: provider)
            return kind == .picture || (kind == .sectionLink && sectionLinks != nil)
        }
    }

    /// Whether a drag the PDF does not take is one a person expects to land, so letting go over
    /// the page says why not in the banner: PDF files, onto a PDF that can be changed.
    func isRefusedWithReason(_ providers: [NSItemProvider]) -> Bool {
        !session.isProtected && !takesDrop(of: providers) && providers.contains { provider in PDFPictureDropReader.kind(of: provider) == .pdfDocument }
    }

    /// What the drop interaction answers for a drag at a point of the view: a copy for a picture
    /// over a page; a forbidden drop for PDF files, which UIKit then never hands over, so the
    /// end of the drag says why (`dragEnded`); nothing taken otherwise.
    func operation(forDragOf providers: [NSItemProvider], atViewPoint viewPoint: CGPoint) -> UIDropOperation {
        let isOverPage = pdfView?.page(for: viewPoint, nearest: true) != nil
        refusedDragIsOverPage = isOverPage && isRefusedWithReason(providers)
        return isOverPage && takesDrop(of: providers) ? .copy : .forbidden
    }

    /// The drag ended at a point of the view, dropped or not: PDF files let go over the page say
    /// in the banner why they were not placed.
    func dragEnded(atViewPoint viewPoint: CGPoint) {
        defer { refusedDragIsOverPage = false }
        guard refusedDragIsOverPage, let pdfView, pdfView.bounds.contains(viewPoint) else { return }
        session.reportRefusedDrop(of: [.pdfDocument])
    }

    /// Reads the dropped items and places their pictures where they landed. Called when the
    /// drop ends, and by tests with item providers of their own.
    ///
    /// - Returns: How many pictures were placed.
    @discardableResult
    func placePictures(of providers: [NSItemProvider], atViewPoint viewPoint: CGPoint) async -> Int {
        guard takesDrop(of: providers), let location = pdfView?.dropLocation(atViewPoint: viewPoint) else { return 0 }
        let items = await PDFPictureDropReader.read(providers)
        let imagesData = items.compactMap { item in if case .picture(let imageData) = item { imageData } else { nil } }
        let sections = items.compactMap { item in if case .sectionLink(let transfer) = item { transfer } else { nil } }
        if let sectionLinks, !sections.isEmpty {
            let placedSections = await placeSections(sections, actions: sectionLinks, at: location)
            return placedSections + (imagesData.isEmpty ? 0 : await session.placeDroppedPictures(imagesData, at: location))
        }
        guard !imagesData.isEmpty else {
            if items.contains(.unreadable) {
                session.errorMessage = "The dropped image couldn't be read."
            } else {
                session.reportRefusedDrop(of: items.compactMap { item in if case .refused(let kind) = item { kind } else { nil } })
            }
            return 0
        }
        return await session.placeDroppedPictures(imagesData, at: location)
    }

    /// Places each section of the vault the PDF is in where it landed, the first at the drop.
    private func placeSections(_ sections: [SectionLinkTransfer], actions: PDFSectionLinkActions, at location: PDFDropLocation) async -> Int {
        let ownSections = sections.filter { transfer in transfer.isInVault(at: actions.vaultRoot) }
        guard !ownSections.isEmpty else {
            session.errorMessage = "A section of a note in another vault can't be linked from this PDF."
            return 0
        }
        var placedCount = 0
        for transfer in ownSections where await session.placeDroppedSectionLink(transfer.link, actions: actions, at: location) { placedCount += 1 }
        return placedCount
    }

    // MARK: UIDropInteractionDelegate

    func dropInteraction(_ interaction: UIDropInteraction, canHandle dropSession: any UIDropSession) -> Bool {
        let providers = dropSession.items.map(\.itemProvider)
        return takesDrop(of: providers) || isRefusedWithReason(providers)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate dropSession: any UIDropSession) -> UIDropProposal {
        guard let pdfView else { return UIDropProposal(operation: .forbidden) }
        return UIDropProposal(operation: operation(forDragOf: dropSession.items.map(\.itemProvider), atViewPoint: dropSession.location(in: pdfView)))
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd dropSession: any UIDropSession) {
        guard let pdfView else { return }
        dragEnded(atViewPoint: dropSession.location(in: pdfView))
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop dropSession: any UIDropSession) {
        guard let pdfView else { return }
        let viewPoint = dropSession.location(in: pdfView)
        let providers = dropSession.items.map(\.itemProvider)
        Task { await placePictures(of: providers, atViewPoint: viewPoint) }
    }
}
#endif
