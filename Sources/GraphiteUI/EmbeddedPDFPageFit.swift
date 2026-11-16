/**
 * File: EmbeddedPDFPageFit.swift
 * ------------------------------
 * Layer: UI
 * Description: The height of a PDF embed's page area without `#height`: the page it opens at, shown whole at the
 *              area's width.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteApple

/// Makes an embed's PDF view as tall as the page it opens at, shown whole at the view's own
/// width (`PDFEmbedFitting`), in Live Preview and the reading view alike. The width does not
/// depend on the height, so measuring it and setting the height settle at once. A nil page
/// size leaves the height to the viewer's `#height`.
struct EmbeddedPDFPageFit: ViewModifier {
    /// The page area's height while the PDF loads, before its page's size is known: the
    /// fixed height embeds had before (560 points with the 41-point toolbar and its divider).
    static let pageAreaHeightWhileLoading: CGFloat = 519

    let pageSize: CGSize?
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        // One structure whatever the size, so the PDF view is never made again.
        content
            .frame(height: pageSize.map { size in PDFEmbedFitting.pageAreaHeight(showing: size, width: width) ?? Self.pageAreaHeightWhileLoading })
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { newWidth in width = newWidth }
    }

    /// The size of the page the embed opens at (`#page=N`, else the first), as PDFKit shows
    /// it: its crop box, turned by its rotation.
    static func shownSize(of document: PDFDocument, pageNumber: Int?) -> CGSize? {
        guard document.pageCount > 0 else { return nil }
        let pageIndex = min(max(0, (pageNumber ?? 1) - 1), document.pageCount - 1)
        guard let page = document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        let isTurned = (page.rotation / 90) % 2 != 0
        return isTurned ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    }
}
