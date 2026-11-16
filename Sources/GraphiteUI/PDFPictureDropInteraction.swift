/**
 * File: PDFPictureDropInteraction.swift
 * -------------------------------------
 * Layer: UI
 * Description: Takes pictures dropped onto the pages of an iPad PDF view (from Photos, Files, Safari or Graphite's
 *              own sidebar) and places each where it landed; a protected or signed PDF, and a PDF file, take none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
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

    /// Whether the PDF takes the dragged items: it can be changed, and one of them is a picture.
    func takesDrop(of providers: [NSItemProvider]) -> Bool {
        !session.isProtected && providers.contains { provider in PDFPictureDropReader.kind(of: provider) == .picture }
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

    // MARK: UIDropInteractionDelegate

    func dropInteraction(_ interaction: UIDropInteraction, canHandle dropSession: any UIDropSession) -> Bool {
        takesDrop(of: dropSession.items.map(\.itemProvider))
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate dropSession: any UIDropSession) -> UIDropProposal {
        guard let pdfView, takesDrop(of: dropSession.items.map(\.itemProvider)),
              pdfView.page(for: dropSession.location(in: pdfView), nearest: true) != nil else { return UIDropProposal(operation: .forbidden) }
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop dropSession: any UIDropSession) {
        guard let pdfView else { return }
        let viewPoint = dropSession.location(in: pdfView)
        let providers = dropSession.items.map(\.itemProvider)
        Task { await placePictures(of: providers, atViewPoint: viewPoint) }
    }
}
#endif
