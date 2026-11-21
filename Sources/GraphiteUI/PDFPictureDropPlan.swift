/**
 * File: PDFPictureDropPlan.swift
 * ------------------------------
 * Layer: UI
 * Description: What a drop on a PDF page takes (pictures, not PDFs or other files) and where each picture of one
 *              drop goes: the first where it was dropped, the others a little further down and to the right.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/11/2026
 */

import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import GraphiteCore

/// What one dragged item is to a PDF page.
enum PDFDroppedItemKind: Equatable {
    /// An image ImageIO reads, placed as a picture.
    case picture
    /// A PDF file. It is refused rather than placed as a picture of its first page: a picture
    /// would lose the page's text, links and sharpness, and its pages belong in the PDF as
    /// pages (decided 2026-11-16, `Docs/PDF-annotation-todo.md` section 1).
    case pdfDocument
    /// A section of a note dragged from the editor, or a note from the sidebar, placed as the
    /// section's picture linking to it.
    case sectionLink
    /// Anything else (text, a link, another kind of file), which the page does not take.
    case unsupported
}

/// What a drop on a PDF page takes and where its pictures go.
enum PDFPictureDropPlan {
    /// How far each further picture of one drop is placed from the one before, down and to
    /// the right as the page is shown, in points of the page, so none hides another.
    static let cascadeStepPoints: CGFloat = 24

    /// The kind of an item from the types it is offered as, in its app's order: an image
    /// offered also as something else (Preview offers a page as an image and a PDF) is a picture.
    static func kind(ofTypes types: [UTType]) -> PDFDroppedItemKind {
        if types.contains(where: { type in type.conforms(to: .image) }) { return .picture }
        if types.contains(where: { type in type.conforms(to: .pdf) }) { return .pdfDocument }
        return .unsupported
    }

    /// The kind of a file by its name's extension, as the Finder's and Files' addresses carry it.
    static func kind(ofFileAt location: URL) -> PDFDroppedItemKind {
        guard let type = UTType(filenameExtension: location.pathExtension) else { return .unsupported }
        return kind(ofTypes: [type])
    }

    /// The middle of each of `count` pictures dropped at `center` of a page: the first there,
    /// each further one a cascade step down and to the right as shown, kept on the page.
    static func centers(ofPictureCount count: Int, droppedAt center: CGPoint, on shownPage: PDFShownPage) -> [CGPoint] {
        let step = PDFShownPage.pageVector(rightward: cascadeStepPoints, downward: cascadeStepPoints,
                                           quarterTurnsClockwise: shownPage.quarterTurnsClockwise)
        let box = shownPage.cropBox
        return (0..<max(count, 0)).map { position in
            let offset = CGFloat(position)
            return CGPoint(x: min(max(center.x + step.dx * offset, box.minX), box.maxX), y: min(max(center.y + step.dy * offset, box.minY), box.maxY))
        }
    }
}
