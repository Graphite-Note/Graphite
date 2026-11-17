/**
 * File: PDFSessionNotes.swift
 * ---------------------------
 * Layer: UI
 * Description: Notes on PDF pages: found under a point, added, edited, moved, recoloured and deleted, each change an
 *              ordinary edit that saving replays and one step of the PDF's history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

/// Notes on PDF pages, Graphite's and other applications' `/Text` annotations.
extension PDFSession {
    /// The topmost note whose icon is under a point of the page, in the page's coordinates.
    func noteAnnotation(at pagePoint: CGPoint, on page: PDFPage, tolerance: CGFloat) -> PDFAnnotation? {
        page.annotations.last { annotation in
            PDFNote.isNote(annotation) && annotation.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(pagePoint)
        }
    }

    /// The note named `name` on the page, as Graphite names every note it writes.
    func noteAnnotation(named name: String, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.first { annotation in PDFNote.isNote(annotation) && annotation.persistentName == name }
    }

    /// Places a note on the page, as one step named "Add Note".
    func addNote(_ note: PDFNote, on page: PDFPage) throws {
        try transitionNote(from: nil, to: note, on: historyPage(for: page), firstReference: nil, actionName: "Add Note")
    }

    /// Puts `next` in the place of a note on the page, or deletes it (with another application's popup) when `next` is nil, as one step named
    /// `actionName` ("Edit Note", "Move Note", "Recolor Note", "Delete Note").
    func changeNote(_ annotation: PDFAnnotation, on page: PDFPage, to next: PDFNote?, actionName: String) throws {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, let previous = PDFNote(annotation: annotation) else { return }
        // Read again, an unnamed note of another application gets a new name each time: compared without it.
        if let next, next.contents == previous.contents, next.iconBounds == previous.iconBounds, next.color == previous.color { return }
        // The annotation as it is in the file: another application's note may have no name, and is found by its subtype
        // and rectangle the first time. Undo and redo name it.
        let reference = PDFAnnotationReference(annotation: annotation, pageIndex: pageIndex)
        try transitionNote(from: previous, to: next, on: historyPage(for: page), firstReference: reference, actionName: actionName)
    }

    private func transitionNote(from previous: PDFNote?, to next: PDFNote?, on page: PDFHistoryPage, firstReference: PDFAnnotationReference?,
                                actionName: String) throws {
        try applyNoteTransition(from: previous, to: next, on: page, reference: firstReference)
        registerStep(named: actionName) { session in
            try session.applyNoteTransition(from: next, to: previous, on: page, reference: nil)
        } redo: { session in
            try session.applyNoteTransition(from: previous, to: next, on: page, reference: nil)
        }
    }

    /// - Parameter reference: Finds `previous` on the page; by its name when nil.
    private func applyNoteTransition(from previous: PDFNote?, to next: PDFNote?, on historyPage: PDFHistoryPage,
                                     reference: PDFAnnotationReference?) throws {
        let pageIndex = try currentIndex(of: historyPage)
        func previousReference(_ note: PDFNote) -> PDFAnnotationReference {
            reference ?? PDFAnnotationReference(pageIndex: pageIndex, name: note.name, annotationType: PDFNoteAnnotation.typeName, bounds: note.iconBounds)
        }
        switch (previous, next) {
        case (nil, nil): return
        case (nil, let added?): try apply(.addNote(page: pageIndex, note: added))
        case (let removed?, nil): try apply(.removeAnnotation(previousReference(removed)))
        case (let replaced?, let replacement?): try apply(.replaceNote(previousReference(replaced), with: replacement))
        }
    }
}
