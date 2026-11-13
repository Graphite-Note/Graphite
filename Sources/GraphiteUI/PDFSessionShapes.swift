/**
 * File: PDFSessionShapes.swift
 * ----------------------------
 * Layer: UI
 * Description: Rectangles, ovals, lines and arrows on PDF pages: found under a point, added, changed and deleted,
 *              each change an ordinary edit that saving replays and one step of the PDF's history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import PDFKit
import GraphiteApple

/// Shapes on PDF pages, Graphite's and other applications' `/Square`, `/Circle` and `/Line`.
extension PDFSession {
    /// The topmost shape's annotation at a point of the page, in the page's coordinates.
    func shapeAnnotation(at pagePoint: CGPoint, on page: PDFPage, tolerance: CGFloat) -> PDFAnnotation? {
        page.annotations.last { annotation in
            PDFShape(annotation: annotation)?.contains(pagePoint, tolerance: tolerance) == true
        }
    }

    /// The shape named `name` on the page, as Graphite names every shape it writes.
    func shapeAnnotation(named name: String, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.first { annotation in PDFShape.isShape(annotation) && annotation.persistentName == name }
    }

    /// Draws a shape on the page, as one step named after its kind ("Add Rectangle").
    func addShape(_ shape: PDFShape, on page: PDFPage) throws {
        try transitionShape(from: nil, to: shape, on: historyPage(for: page), firstReference: nil, actionName: "Add \(shape.kind.title)")
    }

    /// Puts `next` in the place of a shape on the page, or deletes it when `next` is nil, as
    /// one step named `actionName`.
    func changeShape(_ annotation: PDFAnnotation, on page: PDFPage, to next: PDFShape?, actionName: String) throws {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, let previous = PDFShape(annotation: annotation), previous != next else { return }
        // The annotation as it is in the file: another application's shape may have no name,
        // and is found by its subtype and rectangle the first time. Undo and redo name it.
        let reference = PDFAnnotationReference(annotation: annotation, pageIndex: pageIndex)
        try transitionShape(from: previous, to: next, on: historyPage(for: page), firstReference: reference, actionName: actionName)
    }

    private func transitionShape(from previous: PDFShape?, to next: PDFShape?, on page: PDFHistoryPage, firstReference: PDFAnnotationReference?,
                                 actionName: String) throws {
        try applyShapeTransition(from: previous, to: next, on: page, reference: firstReference)
        registerStep(named: actionName) { session in
            try session.applyShapeTransition(from: next, to: previous, on: page, reference: nil)
        } redo: { session in
            try session.applyShapeTransition(from: previous, to: next, on: page, reference: nil)
        }
    }

    /// - Parameter reference: Finds `previous` on the page; by its name when nil.
    private func applyShapeTransition(from previous: PDFShape?, to next: PDFShape?, on historyPage: PDFHistoryPage,
                                      reference: PDFAnnotationReference?) throws {
        let pageIndex = try currentIndex(of: historyPage)
        func previousReference(_ shape: PDFShape) -> PDFAnnotationReference {
            reference ?? PDFAnnotationReference(pageIndex: pageIndex, name: shape.name, annotationType: shape.kind.annotationTypeName, bounds: shape.bounds)
        }
        switch (previous, next) {
        case (nil, nil): return
        case (nil, let added?): try apply(.addShape(page: pageIndex, shape: added))
        case (let removed?, nil): try apply(.removeAnnotation(previousReference(removed)))
        case (let replaced?, let replacement?): try apply(.replaceShape(previousReference(replaced), with: replacement))
        }
    }
}
