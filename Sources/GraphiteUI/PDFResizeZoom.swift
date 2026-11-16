/**
 * File: PDFResizeZoom.swift
 * -------------------------
 * Layer: UI
 * Description: The zoom of a PDF when its view's width began to change, and the zoom it takes after.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
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
}
