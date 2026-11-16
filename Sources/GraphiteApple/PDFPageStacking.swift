/**
 * File: PDFPageStacking.swift
 * ---------------------------
 * Layer: Apple
 * Description: The stacking order of a PDF page's pictures, text boxes, shapes and Pencil ink in its annotations
 *              (`PDFStackingOrder`): arranging an object, keeping an edited object in its place, and where new
 *              strokes and pictures go.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import Foundation
import PDFKit
import GraphiteCore

/// Why an arrangement was not made.
public enum PDFStackingError: Error, LocalizedError, Equatable {
    /// The object the arrangement names is no longer on its page, as after an undo.
    case objectMissing
    /// The annotation is not a picture, text box or shape Graphite arranges.
    case notArrangeable

    public var errorDescription: String? {
        switch self {
        case .objectMissing: "This object no longer exists."
        case .notArrangeable: "Only images, text boxes and shapes can be arranged."
        }
    }
}

/// A page's stacking order is its annotation order, which every reader follows, so the order is
/// kept in the ordinary file. PDFKit only appends annotations: a change takes the page's last
/// layers off and adds them back (`PDFStackingOrder.change(to:)`), and never takes off another
/// application's annotations other than the shapes and text boxes Graphite arranges.
extension PDFPageManager {
    /// What an annotation is to the stacking order.
    static func stackingEntry(of annotation: PDFAnnotation) -> PDFStackingEntry {
        if annotation.value(forAnnotationKey: groupKey) != nil { return .ink }
        if let ownerName = annotation.value(forAnnotationKey: textBoxLinkOwnerKey) as? String { return .attached(ownerName: ownerName) }
        if isPicture(annotation) { return .object(.picture, name: annotation.persistentName) }
        if annotation.type == PDFTextBox.annotationTypeName { return .object(.textBox, name: annotation.persistentName) }
        if PDFShape.isShape(annotation) { return .object(.shape, name: annotation.persistentName) }
        return .fixed
    }

    /// The page's annotations and their stacking order.
    static func stacking(of page: PDFPage) -> (annotations: [PDFAnnotation], order: PDFStackingOrder) {
        let annotations = page.annotations
        return (annotations, PDFStackingOrder(entries: annotations.map(stackingEntry(of:))))
    }

    /// The annotations that are over the ink, or over where a first stroke goes, which new strokes
    /// go under. Only the annotations after the last stroke are read, so a stroke costs the
    /// same on a full page (FR-104).
    public static func annotationsOverInk(of page: PDFPage) -> [PDFAnnotation] {
        let annotations = page.annotations
        let start = annotations.lastIndex { annotation in annotation.value(forAnnotationKey: groupKey) != nil } ?? annotations.startIndex
        let tail = Array(annotations[start...])
        return PDFStackingOrder(entries: tail.map(stackingEntry(of:))).annotationIndicesOverInk.map { index in tail[index] }
    }

    /// Puts the layers in `newOrder`.
    static func reorder(_ page: PDFPage, annotations: [PDFAnnotation], from order: PDFStackingOrder, to newOrder: [PDFStackingOrder.Layer]) {
        let addedBack = order.change(to: newOrder).annotationIndicesAddedBack.map { index in annotations[index] }
        for annotation in addedBack { page.removeAnnotation(annotation) }
        for annotation in addedBack { page.addAnnotation(annotation) }
    }

    /// Arranges a picture, text box or shape (`PDFEdit.arrange`).
    static func arrange(_ reference: PDFAnnotationReference, _ arrangement: PDFArrangement, on page: PDFPage) throws {
        guard let annotation = referencedAnnotation(reference, on: page) else { throw PDFStackingError.objectMissing }
        let (annotations, order) = stacking(of: page)
        guard let annotationIndex = annotations.firstIndex(where: { candidate in candidate === annotation }),
              let layer = order.layer(ofObjectAt: annotationIndex) else { throw PDFStackingError.notArrangeable }
        guard let newOrder = order.arranged(layer, arrangement) else { return }
        reorder(page, annotations: annotations, from: order, to: newOrder)
    }

    /// Arranges the page's ink as one layer (`PDFEdit.arrangeInk`).
    static func arrangeInk(_ arrangement: PDFArrangement, on page: PDFPage) {
        let (annotations, order) = stacking(of: page)
        guard let newOrder = order.arranged(.ink, arrangement) else { return }
        reorder(page, annotations: annotations, from: order, to: newOrder)
    }

    /// Where the object is among the page's layers (`PDFStackingOrder.layers`), or nil when it is not one.
    public static func stackingPosition(of annotation: PDFAnnotation, on page: PDFPage) -> Int? {
        let (annotations, order) = stacking(of: page)
        return annotations.firstIndex { candidate in candidate === annotation }
            .flatMap(order.layer(ofObjectAt:)).flatMap(order.position(of:))
    }

    /// Where the annotation a reference names is among the page's layers, or nil when it is not an object.
    public static func stackingPosition(of reference: PDFAnnotationReference, on page: PDFPage) -> Int? {
        referencedAnnotation(reference, on: page).flatMap { annotation in stackingPosition(of: annotation, on: page) }
    }

    /// The arrangements that would move the object, for the menus that offer them.
    public static func possibleArrangements(of annotation: PDFAnnotation, on page: PDFPage) -> Set<PDFArrangement> {
        let (annotations, order) = stacking(of: page)
        guard let layer = annotations.firstIndex(where: { candidate in candidate === annotation }).flatMap(order.layer(ofObjectAt:)) else { return [] }
        let arrangements: [PDFArrangement] = [.bringToFront, .bringForward, .sendBackward, .sendToBack]
        return Set(arrangements.filter { arrangement in order.arranged(layer, arrangement) != nil })
    }

    /// Where the page's ink is among its layers, or nil on a page without ink.
    public static func inkStackingPosition(on page: PDFPage) -> Int? {
        stacking(of: page).order.position(of: .ink)
    }

    /// Ink to Front and Ink to Back, those that would move the page's ink.
    public static func possibleInkArrangements(on page: PDFPage) -> Set<PDFArrangement> {
        let order = stacking(of: page).order
        let arrangements: [PDFArrangement] = [.bringToFront, .sendToBack]
        return Set(arrangements.filter { arrangement in order.arranged(.ink, arrangement) != nil })
    }

    /// The objects of the page, Graphite's pictures and text boxes and every shape, the topmost
    /// first, for finding what is under a point.
    public static func objectAnnotationsTopmostFirst(on page: PDFPage) -> [PDFAnnotation] {
        let (annotations, order) = stacking(of: page)
        return order.layers.reversed().compactMap { layer in
            guard case .object(let annotationIndex) = layer else { return nil }
            return annotations[annotationIndex]
        }
    }

    /// Takes an object off the page, with `removeFormer`, and adds what replaces it, with
    /// `addReplacement`, which adds it on top; the replacement goes where the former was.
    static func replaceKeepingItsPlace(_ former: PDFAnnotation, on page: PDFPage, removeFormer: () -> Void, addReplacement: () throws -> Void) rethrows {
        let formerPosition = stackingPosition(of: former, on: page)
        removeFormer()
        try addReplacement()
        guard let formerPosition else { return }
        let (annotations, order) = stacking(of: page)
        guard let newOrder = order.placingTopLayer(at: formerPosition) else { return }
        reorder(page, annotations: annotations, from: order, to: newOrder)
    }

    /// Adds an annotation on top of the page and puts it right under the ink, where a new picture goes.
    static func addUnderTheInk(_ annotation: PDFAnnotation, to page: PDFPage) {
        let inkPosition = stacking(of: page).order.inkPosition
        page.addAnnotation(annotation)
        let (annotations, order) = stacking(of: page)
        guard let newOrder = order.placingTopLayer(at: inkPosition) else { return }
        reorder(page, annotations: annotations, from: order, to: newOrder)
    }
}
