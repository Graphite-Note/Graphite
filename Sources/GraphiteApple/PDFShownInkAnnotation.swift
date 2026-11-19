/**
 * File: PDFShownInkAnnotation.swift
 * ---------------------------------
 * Layer: Apple
 * Description: The ink annotations of a PDF Graphite shows, which draw nothing while a page's canvas hides them on the
 *              iPad or while the page's ink layer draws them on the Mac, the drawing of hidden ink for thumbnails, and the
 *              stroke that draws its whole combined ink group (`PDFCombinedInkGroup`).
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 19/11/2026
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
/// at each step of a zoom (`DenseInkPageSmoothnessHostedTests`). On the Mac it draws nothing while its page's ink layer
/// draws the page's ink (`PDFPageInkLayerState`). A shown annotation draws as PDFKit draws it, and the file is not
/// changed: the class only says how the shown document draws what it read.
///
/// The first stroke of a group the shown page holds combined (`PDFShownInkCombining`) draws the picture of the whole
/// group instead of itself (`combinedGroup`), over the whole page.
final class PDFShownInkAnnotation: PDFAnnotation {
    /// The subtype PDFKit asks its document's delegate about, without its slash.
    static let annotationTypeName = "Ink"

    /// The group this stroke draws, when it is the one stroke of a combined group the shown page holds.
    fileprivate(set) var combinedGroup: PDFCombinedInkGroup?

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard shouldDisplay, !isDrawnByPageInkLayer else { return }
        #if os(iOS)
        // On the iPad the page's overlay shows the group's picture as a layer's contents; drawn here, PDFKit drew 16 MB
        // of it into a layer of the page's size on the main thread each time it arrived (54 ms frames, 2026-11-18).
        if combinedGroup != nil { return }
        #endif
        drawEvenWhenHidden(with: box, in: context)
    }

    /// Draws the annotation as it shows, also while it is hidden.
    fileprivate func drawEvenWhenHidden(with box: PDFDisplayBox, in context: CGContext) {
        guard let combinedGroup else {
            super.draw(with: box, in: context)
            return
        }
        guard let page else { return }
        combinedGroup.drawPicture(of: page, box: box, in: context)
    }
}

public extension PDFAnnotation {
    /// The combined ink group this annotation draws (`PDFShownInkCombining`), when it is the one stroke of such a group
    /// a shown page holds.
    var combinedInkGroup: PDFCombinedInkGroup? { (self as? PDFShownInkAnnotation)?.combinedGroup }

    /// Makes this annotation, the first stroke of a group the shown page holds combined, draw the whole group over the
    /// page. Returns false when it is not the shown document's ink. Call before the page is shown.
    @discardableResult
    func becomeCombinedInk(_ group: PDFCombinedInkGroup) -> Bool {
        guard let shownInk = self as? PDFShownInkAnnotation, let page else { return false }
        shownInk.combinedGroup = group
        #if !os(iOS)
        // PDFKit draws an annotation within its bounds; the group's strokes cover the page. On the iPad it draws
        // nothing, the page's overlay showing the group, so its layer stays the size of its own stroke.
        shownInk.bounds = page.bounds(for: .mediaBox)
        #endif
        return true
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
