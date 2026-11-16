/**
 * File: PDFSessionPictureDrops.swift
 * ----------------------------------
 * Layer: UI
 * Description: Pictures dropped onto a PDF page, on the iPad and the Mac: the page and point a drop landed on, as
 *              the view shows the page, and the pictures placed there, each one step "Add Image" of the history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

/// Where a drop landed on a PDF view: the page under it, or the nearest, as the view shows
/// it, and the point of that page, inside its crop box.
struct PDFDropLocation: Equatable {
    let pageIndex: Int
    let shownPage: PDFShownPage
    let pagePoint: CGPoint
}

extension PDFView {
    /// Where a drop at a point of the view lands, or nil when the view shows no page.
    func dropLocation(atViewPoint viewPoint: CGPoint) -> PDFDropLocation? {
        guard let document, let page = page(for: viewPoint, nearest: true) else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let cropBox = page.bounds(for: .cropBox)
        #if os(macOS)
        let viewIsFlipped = isFlipped
        #else
        let viewIsFlipped = true
        #endif
        let shownPage = PDFShownPage(cropBox: cropBox, rotationDegrees: page.rotation, frameInView: convert(cropBox, from: page), viewIsFlipped: viewIsFlipped)
        return PDFDropLocation(pageIndex: pageIndex, shownPage: shownPage, pagePoint: shownPage.pagePoint(ofViewPoint: viewPoint))
    }
}

extension PDFSession {
    /// Places the pictures of one drop: the first with its middle where it was dropped, the
    /// others cascading from there (`PDFPictureDropPlan`), each at its own size where that
    /// fits and at most 60% of the page wide, each one step "Add Image", the last one selected.
    /// A picture that cannot be placed says why in the PDF's banner, and the others still go.
    ///
    /// - Returns: How many pictures were placed.
    @discardableResult
    func placeDroppedPictures(_ imagesData: [Data], at location: PDFDropLocation) async -> Int {
        let centers = PDFPictureDropPlan.centers(ofPictureCount: imagesData.count, droppedAt: location.pagePoint, on: location.shownPage)
        var placedCount = 0
        for (imageData, center) in zip(imagesData, centers) {
            do {
                try await addPicture(imageData: imageData, placement: (location.pageIndex, center),
                                     preferredWidth: PictureNaturalSize.measure(ofImageData: imageData)?.widthInPoints)
                placedCount += 1
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return placedCount
    }

    /// Why a drop was not taken, in the PDF's banner: a PDF file, which is not placed as a
    /// picture, or a dragged item that is no picture at all.
    func reportRefusedDrop(of kinds: [PDFDroppedItemKind]) {
        if kinds.contains(.pdfDocument) {
            errorMessage = "A PDF can't be placed on a page as an image. Drop a picture, such as a PNG or JPEG."
        } else if !kinds.isEmpty {
            errorMessage = "Only pictures can be dropped onto a page."
        }
    }
}
