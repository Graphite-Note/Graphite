/**
 * File: PDFResizeZoom.swift
 * -------------------------
 * Layer: UI
 * Description: The zoom of a PDF when its view's width began to change, and the zoom it takes after.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The zoom of a PDF when its view's width began to change, and the zoom it takes after.
struct PDFResizeZoom: Equatable {
    /// Within this fraction of the fitting zoom, a page is taken to fit the width: a pinch
    /// rarely lands on it exactly.
    static let fittingTolerance: CGFloat = 0.03

    /// The zoom past fitting the old width, 1 when the pages fitted it.
    let zoomPastFitting: CGFloat
    let fittedWidth: Bool

    init(isScaledByPDFKit: Bool, scale: CGFloat, fittingScale: CGFloat) {
        let zoomPastFitting = fittingScale > 0 && scale.isFinite ? scale / fittingScale : 1
        fittedWidth = isScaledByPDFKit || abs(zoomPastFitting - 1) <= Self.fittingTolerance
        self.zoomPastFitting = fittedWidth ? 1 : zoomPastFitting
    }

    enum ScaleAfterResize: Equatable {
        /// PDFKit fits the pages to the width, as it does until a pinch.
        case fitsByPDFKit
        case scale(CGFloat)
    }

    func scaleAfterResize(fittingScale: CGFloat) -> ScaleAfterResize {
        fittedWidth ? .fitsByPDFKit : .scale(fittingScale * zoomPastFitting)
    }

    /// The width, in the pages' own points, that the zoom fitting the pages spreads across
    /// the view: the widest page as shown and the margins PDFKit keeps beside it. The fitting
    /// zoom is the view's width over it. Worked out from the pages, it follows the view's
    /// width at every step of a resize, where PDFKit's `scaleFactorForSizeToFit`, read from its
    /// own views, lags behind: during a window's resize it gave the zoom of other widths, and
    /// the pages ended zoomed twice past their side (HUNT-378). Nil without a page.
    static func fittedSpan(pageWidthsAsShown: [CGFloat], horizontalMargins: CGFloat) -> CGFloat? {
        guard let widestPage = pageWidthsAsShown.max(), widestPage > 0 else { return nil }
        return widestPage + max(horizontalMargins, 0)
    }
}
