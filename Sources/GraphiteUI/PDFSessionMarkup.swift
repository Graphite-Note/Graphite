/**
 * File: PDFSessionMarkup.swift
 * ----------------------------
 * Layer: UI
 * Description: Highlights, underlines and strikethroughs on PDF pages: marking selected text (changing or joining
 *              a mark of the same kind already on it, never stacking another), recolouring and removing a mark,
 *              each one step of the PDF's history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

/// One page's part of a markup step, which undo reverses and redo makes again. The page is
/// named through its history box, not its index: pages inserted, deleted or moved in
/// between would otherwise put the markup on another page.
enum PDFMarkupChange {
    /// Marks taken off the page, then marks put on it.
    case replace(removed: [PDFMarkup], added: [PDFMarkup], page: PDFHistoryPage)
    /// A mark given `color`. `previous` keeps its exact colour before, which may be none of
    /// Graphite's colours; `reference` finds it, by name or, unnamed, by its rectangle.
    case recolor(previous: PDFMarkup, reference: PDFAnnotationReference, color: PDFMarkupColor, page: PDFHistoryPage)
}

extension PDFSession {
    /// Marks the selected text with a mark of `kind`, page by page, as one step named after
    /// the kind. Where a mark of the kind is already on the text, it changes that mark or
    /// joins the marks into one (`PDFMarkupOverlap`); text marked again in the same colour
    /// is left as it is, and no step is made.
    func addMarkup(_ kind: PDFMarkupKind, color: PDFMarkupColor, for selection: PDFSelection) throws {
        let linesByPage = selection.markupLinesByPage(in: document)
        guard !linesByPage.isEmpty else { throw GraphiteError.unavailable("Select some PDF text first.") }
        var changes: [PDFMarkupChange] = []
        for (pageIndex, lineBounds) in linesByPage {
            guard let page = document.page(at: pageIndex) else { throw GraphiteError.invalidFile("Page no longer exists.") }
            if let change = try mark(lineBounds, on: page, at: pageIndex, kind: kind, color: color) { changes.append(change) }
        }
        registerMarkupStep(named: kind.title, changes)
    }

    func removeMarkup(_ annotation: PDFAnnotation, on page: PDFPage) throws {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, let markup = PDFMarkup(annotation: annotation) else { return }
        try apply(.removeAnnotation(PDFAnnotationReference(annotation: annotation, pageIndex: pageIndex)))
        registerMarkupStep(named: "Remove \(markup.kind.title)", [.replace(removed: [markup], added: [], page: historyPage(for: page))])
    }

    /// Gives a mark another colour, as one step; a mark that has the colour already is left alone.
    func recolorMarkup(_ annotation: PDFAnnotation, on page: PDFPage, to color: PDFMarkupColor) throws {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, let previousMarkup = PDFMarkup(annotation: annotation), !previousMarkup.hasColor(color) else { return }
        let reference = PDFAnnotationReference(annotation: annotation, pageIndex: pageIndex)
        try apply(.recolorMarkup(reference, color: color))
        registerMarkupStep(named: "Change Color", [.recolor(previous: previousMarkup, reference: reference, color: color, page: historyPage(for: page))])
    }

    // MARK: Marking text on one page

    /// Marks the lines on one page, applying the edits, and returns what undo reverses; nil
    /// when the text already has this mark.
    private func mark(_ lineBounds: [CGRect], on page: PDFPage, at pageIndex: Int, kind: PDFMarkupKind,
                      color: PDFMarkupColor) throws -> PDFMarkupChange? {
        let existingMarks: [(annotation: PDFAnnotation, markup: PDFMarkup)] = page.annotations.compactMap { annotation in
            guard PDFMarkupKind(annotationType: annotation.type) == kind, let markup = PDFMarkup(annotation: annotation) else { return nil }
            return (annotation, markup)
        }
        let runsVertically = lineBounds.first.map { line in page.markupLineDirection(of: line) != .leftToRight } ?? false
        let outcome = PDFMarkupOverlap.outcome(ofMarking: lineBounds, over: existingMarks.map { mark in
            PDFMarkupOverlap.ExistingMark(lineBounds: mark.markup.lineBounds, hasMarkingColor: mark.markup.hasColor(color))
        }, runsVertically: runsVertically)
        switch outcome {
        case .unchanged:
            return nil
        case .add(let addedLines):
            let markup = PDFMarkup(kind: kind, color: color, lineBounds: addedLines)
            try apply(.addMarkup(page: pageIndex, markup: markup))
            return .replace(removed: [], added: [markup], page: historyPage(for: page))
        case .recolor(let markIndex):
            let recolored = existingMarks[markIndex]
            let reference = PDFAnnotationReference(annotation: recolored.annotation, pageIndex: pageIndex)
            try apply(.recolorMarkup(reference, color: color))
            return .recolor(previous: recolored.markup, reference: reference, color: color, page: historyPage(for: page))
        case .join(let markIndices, let joinedLines):
            let absorbed = markIndices.map { markIndex in existingMarks[markIndex] }
            for mark in absorbed { try apply(.removeAnnotation(PDFAnnotationReference(annotation: mark.annotation, pageIndex: pageIndex))) }
            let joined = PDFMarkup(kind: kind, color: color, lineBounds: joinedLines,
                                   originalDetails: PDFMarkupDetails.joiningNotes(of: absorbed.map(\.markup), in: color))
            try apply(.addMarkup(page: pageIndex, markup: joined))
            return .replace(removed: absorbed.map(\.markup), added: [joined], page: historyPage(for: page))
        }
    }

    // MARK: Undo and redo

    /// Registers the changes as one step; no changes make no step.
    private func registerMarkupStep(named actionName: String, _ changes: [PDFMarkupChange]) {
        guard !changes.isEmpty else { return }
        registerStep(named: actionName) { session in
            for change in changes.reversed() { try session.reverse(change) }
        } redo: { session in
            for change in changes { try session.makeAgain(change) }
        }
    }

    private func reverse(_ change: PDFMarkupChange) throws {
        switch change {
        case .replace(let removed, let added, let page):
            for markup in added.reversed() { try removeMarkup(markup, on: page) }
            for markup in removed { try apply(.addMarkup(page: currentIndex(of: page), markup: markup)) }
        case .recolor(let previous, let reference, _, let page):
            // The exact former colour: `previous.color` is only the nearest of Graphite's.
            try apply(.restoreMarkupColor(currentReference(reference, on: page), from: previous))
        }
    }

    private func makeAgain(_ change: PDFMarkupChange) throws {
        switch change {
        case .replace(let removed, let added, let page):
            for markup in removed { try removeMarkup(markup, on: page) }
            for markup in added { try apply(.addMarkup(page: currentIndex(of: page), markup: markup)) }
        case .recolor(_, let reference, let color, let page):
            try apply(.recolorMarkup(currentReference(reference, on: page), color: color))
        }
    }

    private func currentReference(_ reference: PDFAnnotationReference, on page: PDFHistoryPage) throws -> PDFAnnotationReference {
        PDFAnnotationReference(pageIndex: try currentIndex(of: page), name: reference.name, annotationType: reference.annotationType, bounds: reference.bounds)
    }

    /// The reference carries the bounds, so the markup is still found after an older
    /// build's page change dropped its name from the file.
    private func removeMarkup(_ markup: PDFMarkup, on page: PDFHistoryPage) throws {
        let reference = PDFAnnotationReference(pageIndex: try currentIndex(of: page), name: markup.name,
                                               annotationType: markup.kind.annotationTypeName, bounds: markup.bounds)
        try apply(.removeAnnotation(reference))
    }
}
