/**
 * File: PDFShownInkAnnotation.swift
 * ---------------------------------
 * Layer: Apple
 * Description: The ink annotations of a PDF Graphite shows on the iPad, which draw nothing while a page's canvas
 *              hides them, and the drawing of hidden ink for thumbnails.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import Foundation
import CoreGraphics
import PDFKit

/// An `/Ink` annotation of a document Graphite shows (`PDFAnnotationDrawingDelegate`), which draws nothing while it is
/// hidden.
///
/// PDFKit on the iPad gives every annotation of a page a layer of its own and keeps it while the annotation is hidden,
/// as Graphite's ink is while the page's canvas shows it. It draws such a layer again, on the main thread, each time it
/// makes the page's view (as a zoom or a scroll shows the page again) or changes the layer's resolution, and it drew
/// each hidden stroke from its saved appearance: decompressed, parsed and filled, for a layer nobody sees. On a page of
/// 6,000 strokes, as Goodnotes' import of a formula sheet makes, that froze the iPad for one to two and a half seconds
/// at each step of a zoom (`DenseInkPageSmoothnessHostedTests`). A shown annotation draws as PDFKit draws it, and the
/// file is not changed: the class only says how the shown document draws what it read.
final class PDFShownInkAnnotation: PDFAnnotation {
    /// The subtype PDFKit asks its document's delegate about, without its slash.
    static let annotationTypeName = "Ink"

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard shouldDisplay else { return }
        super.draw(with: box, in: context)
    }

    /// Draws the annotation as it shows, also while it is hidden.
    fileprivate func drawEvenWhenHidden(with box: PDFDisplayBox, in context: CGContext) {
        super.draw(with: box, in: context)
    }
}

public extension PDFAnnotation {
    /// Draws the annotation as it shows when displayed, also while a page's canvas hides it: a thumbnail draws the ink a
    /// canvas shows (`PDFThumbnailRenderer`). Hidden ink of the shown document draws nothing by itself
    /// (`PDFShownInkAnnotation`, `PDFOutlinedInkAnnotation`).
    func drawAsShown(with box: PDFDisplayBox, in context: CGContext) {
        if let shownInk = self as? PDFShownInkAnnotation {
            shownInk.drawEvenWhenHidden(with: box, in: context)
        } else if let outlinedInk = self as? PDFOutlinedInkAnnotation {
            outlinedInk.drawEvenWhenHidden(with: box, in: context)
        } else {
            draw(with: box, in: context)
        }
    }
}
