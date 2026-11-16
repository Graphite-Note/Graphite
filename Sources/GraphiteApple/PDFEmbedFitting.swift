/**
 * File: PDFEmbedFitting.swift
 * ---------------------------
 * Layer: Apple
 * Description: How tall a PDF embed without `#height` is: its page shown whole at the column's width.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import CoreGraphics

/// A PDF embed written without `#height` shows the page it opens at whole, fitted to the
/// column's width at that page's aspect ratio, as the owner asked on 2026-11-13 (HUNT-354);
/// `#height=N` keeps its height.
public enum PDFEmbedFitting {
    /// The space PDFKit leaves around each page of an embed, on every side: the page break
    /// margins `GraphitePDFView` gives an embed on the iPad, and PDFKit's own on the Mac,
    /// where the view lays its pages out with them whatever it is given (measured 2026-11-13).
    #if os(macOS)
    public static let pageMargin: CGFloat = 4.75
    #else
    public static let pageMargin: CGFloat = 6
    #endif

    /// The height of the embed's page area that shows `pageSize` (its size as shown, rotation
    /// applied) whole at `width`: the page fitted to the width less its margins, plus its
    /// margins above and below. Nil for a size or width that cannot be fitted.
    public static func pageAreaHeight(showing pageSize: CGSize, width: CGFloat) -> CGFloat? {
        let pageWidth = width - 2 * pageMargin
        guard pageSize.width > 0, pageSize.height > 0, pageWidth > 0, pageSize.width.isFinite, pageSize.height.isFinite else { return nil }
        let fittedHeight = (pageWidth * pageSize.height / pageSize.width).rounded(.up) + 2 * pageMargin
        return min(fittedHeight, CGFloat(PDFEmbedOptions.maximumHeight))
    }
}
