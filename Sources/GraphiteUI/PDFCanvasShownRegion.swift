/**
 * File: PDFCanvasShownRegion.swift
 * --------------------------------
 * Layer: UI
 * Description: Which part of a PDF page its Pencil canvas draws, and at what scale: the whole page
 *              while it fits a bound of pixels, otherwise as much around what is on screen as fits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
import CoreGraphics

/// Which part of a PDF page its Pencil canvas draws, and how many times the page's size.
///
/// The canvas draws its ink at the PDF view's zoom, so a pixel of its tiles is a pixel of the
/// screen at any zoom (`Docs/solid/invariants.md`, INK-22 and P-18). PencilKit keeps tiles for
/// all of a canvas, so a canvas the size of the page zoomed far in would take more memory than
/// a page may: an A4 page at 4.2 times on a 2x screen already takes 36 megapixels. Past that
/// the canvas covers only the part of the page around what is on screen, as large as the
/// bound allows, and follows the page as it scrolls; before HUNT-320 it drew the whole page
/// at a lower scale instead, and the ink was magnified and soft.
enum PDFCanvasShownRegion {
    /// The most pixels a page's canvas is drawn with: 144 MB at four bytes a pixel.
    static let maximumCanvasPixelCount: CGFloat = 36_000_000
    /// The least a canvas is reduced: a zoomed-out page needs no sharper ink than this, and a
    /// smaller canvas takes less memory than the page's own size.
    static let minimumRenderingScale: CGFloat = 0.5
    /// The most a canvas is enlarged, far past any zoom PDFKit allows, against a zoom that is
    /// not a number a canvas can take.
    static let maximumRenderingScale: CGFloat = 64
    /// The region is moved once what is on screen comes within this fraction of its own size
    /// of the region's edge, so the tiles PencilKit draws for the moved region are off screen.
    static let followingMarginFraction: CGFloat = 0.25

    /// The scale to draw ink at for a PDF view's zoom: the zoom itself, so a pixel of the ink's
    /// tiles is a pixel of the screen and settled ink is as sharp as a line can be. It does not
    /// depend on the tool in hand: a tool's width is its width in the drawing at any zoom of the
    /// canvas (INK-22), nor on the memory a page may take, which `region` bounds instead.
    static func renderingScale(forZoom zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite, zoom > 0 else { return 1 }
        return min(max(zoom, minimumRenderingScale), maximumRenderingScale)
    }

    /// The part of the page, in its points from its top-left corner, the canvas draws at
    /// `scale` on a screen of `screenScale` pixels per point, within `pixelBudget` pixels:
    /// the whole page when it fits; otherwise the part around `visibleRegion` that fits, kept
    /// as `currentRegion` while that still has room around what is on screen. What is on
    /// screen is always drawn, should it alone be over the bound. Nil `visibleRegion` (a page
    /// not yet in a window) is taken as the page's top, and a page off screen as its edge nearest it.
    static func region(pageSize: CGSize, visibleRegion: CGRect?, currentRegion: CGRect?, scale: CGFloat,
                       screenScale: CGFloat, pixelBudget: CGFloat) -> CGRect {
        let page = CGRect(origin: .zero, size: pageSize)
        let pixelsPerPoint = max(scale, minimumRenderingScale) * max(screenScale, 1)
        let budgetArea = pixelBudget / (pixelsPerPoint * pixelsPerPoint)
        guard page.width > 0, page.height > 0, page.width * page.height > budgetArea else { return page }
        let visible = shownPart(of: visibleRegion, on: page)
        let size = regionSize(around: visible.size, budgetArea: budgetArea, pageSize: pageSize)
        if let currentRegion, abs(currentRegion.width - size.width) < 0.5, abs(currentRegion.height - size.height) < 0.5 {
            let neededAround = visible.insetBy(dx: -visible.width * followingMarginFraction, dy: -visible.height * followingMarginFraction).intersection(page)
            if currentRegion.insetBy(dx: -0.5, dy: -0.5).contains(neededAround) { return currentRegion }
        }
        let originX = min(max((visible.midX - size.width / 2).rounded(), 0), page.width - size.width)
        let originY = min(max((visible.midY - size.height / 2).rounded(), 0), page.height - size.height)
        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    /// What is on screen of the page. A page off screen gives the point of the page nearest to
    /// what is on screen, where it will come into view; a page outside a window, its top.
    private static func shownPart(of visibleRegion: CGRect?, on page: CGRect) -> CGRect {
        guard let visibleRegion, visibleRegion.width.isFinite, visibleRegion.height.isFinite, !visibleRegion.isNull else {
            return CGRect(x: page.midX - 0.5, y: 0, width: 1, height: 1)
        }
        let shown = visibleRegion.intersection(page)
        if !shown.isNull, shown.width > 0, shown.height > 0 { return shown }
        let nearestX = min(max(visibleRegion.midX, page.minX + 0.5), page.maxX - 0.5)
        let nearestY = min(max(visibleRegion.midY, page.minY + 0.5), page.maxY - 0.5)
        return CGRect(x: nearestX - 0.5, y: nearestY - 0.5, width: 1, height: 1)
    }

    /// A region of `budgetArea` square points around a visible part of `visibleSize`, enlarged
    /// alike in both directions, within the page, and never smaller than the visible part.
    private static func regionSize(around visibleSize: CGSize, budgetArea: CGFloat, pageSize: CGSize) -> CGSize {
        let visibleArea = max(visibleSize.width * visibleSize.height, 1)
        let enlargement = max((budgetArea / visibleArea).squareRoot(), 1)
        var width = min(pageSize.width, visibleSize.width * enlargement)
        var height = min(pageSize.height, max(visibleSize.height, budgetArea / max(width, 1)))
        if height >= pageSize.height { width = min(pageSize.width, max(visibleSize.width, budgetArea / max(height, 1))) }
        height = min(pageSize.height, max(height, visibleSize.height))
        width = min(pageSize.width, max(width, visibleSize.width))
        return CGSize(width: min(pageSize.width, width.rounded(.up)), height: min(pageSize.height, height.rounded(.up)))
    }
}
