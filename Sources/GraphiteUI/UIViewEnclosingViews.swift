/**
 * File: UIViewEnclosingViews.swift
 * --------------------------------
 * Layer: UI
 * Description: The scroll view and the PDF page canvas a view sits in, found by walking up its superviews.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit

extension UIView {
    /// The nearest scroll view above this view, such as the one PDFKit scrolls pages in.
    var enclosingScrollView: UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

    /// The page canvas this view is, or is inside, as PencilKit's recognizers are.
    var enclosingPageCanvas: PDFPageCanvasView? {
        var candidate: UIView? = self
        while let view = candidate {
            if let canvas = view as? PDFPageCanvasView { return canvas }
            candidate = view.superview
        }
        return nil
    }
}
#endif
