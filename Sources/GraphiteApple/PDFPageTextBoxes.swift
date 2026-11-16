/**
 * File: PDFPageTextBoxes.swift
 * ----------------------------
 * Layer: Apple
 * Description: Adding, replacing and removing the text boxes on a PDF page.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 16/11/2026
 */
import Foundation
import PDFKit
import GraphiteCore

/// Text boxes on PDF pages, as edits (`PDFEdit.addTextBox`, `.replaceTextBox`,
/// `.removeTextBox`) applied the same way to the shown document and to the one saving writes.
///
/// A new box goes on top of the page, followed by the links over its text, so it is over the
/// ink in every reader, as it is on screen; a box changed or moved keeps its place in the
/// page's stacking order (`PDFPageStacking`), and its links go with it.
extension PDFPageManager {
    static func addTextBox(_ textBox: PDFTextBox, to page: PDFPage, isForWrittenDocument: Bool, authorName: String?) throws {
        try add(textBox, to: page, isForWrittenDocument: isForWrittenDocument, authorName: authorName)
    }

    static func replaceTextBox(_ reference: PDFAnnotationReference, with textBox: PDFTextBox, in document: PDFDocument, isForWrittenDocument: Bool) throws {
        let (page, annotation) = try textBoxAnnotation(reference, in: document)
        var replacement = textBox
        // The box keeps the keys of the application that made it, whatever the edit says.
        replacement.preservedEntries = PDFTextBox(annotation: annotation)?.preservedEntries ?? textBox.preservedEntries
        // The box keeps its author, as it keeps the keys of the application that made it.
        try replaceKeepingItsPlace(annotation, on: page, removeFormer: { removeTextBox(annotation, from: page) }, addReplacement: {
            try add(replacement, to: page, isForWrittenDocument: isForWrittenDocument, authorName: annotation.userName)
        })
    }

    static func removeTextBox(_ reference: PDFAnnotationReference, from document: PDFDocument) throws {
        let (page, annotation) = try textBoxAnnotation(reference, in: document)
        removeTextBox(annotation, from: page)
    }

    /// The text boxes on a page, the lowest first: Graphite's and other applications'.
    public static func textBoxes(on page: PDFPage) -> [PDFTextBox] {
        page.annotations.compactMap(PDFTextBox.init(annotation:))
    }

    private static func add(_ textBox: PDFTextBox, to page: PDFPage, isForWrittenDocument: Bool, authorName: String?) throws {
        let annotation = try textBox.makeAnnotation(isForWrittenDocument: isForWrittenDocument, authorName: authorName)
        // Added after everything: the page's text boxes are its last annotations.
        page.addAnnotation(annotation)
        let layout = PDFTextBoxLayout(box: textBox)
        for link in textBox.makeLinkAnnotations(layout: layout) { page.addAnnotation(link) }
    }

    private static func textBoxAnnotation(_ reference: PDFAnnotationReference, in document: PDFDocument) throws -> (PDFPage, PDFAnnotation) {
        guard reference.pageIndex >= 0, reference.pageIndex < document.pageCount, let page = document.page(at: reference.pageIndex) else {
            throw PDFTextBoxError.pageMissing
        }
        let annotations = page.annotations
        guard let annotation = annotations.first(where: reference.matches) ?? annotations.first(where: reference.matchesAfterNameWasLost),
              annotation.type == PDFTextBox.annotationTypeName else { throw PDFTextBoxError.boxMissing }
        return (page, annotation)
    }

    /// Removes the box and the links that belong to it. A popup another application gave the
    /// box goes with it, as it would be left without a parent.
    private static func removeTextBox(_ annotation: PDFAnnotation, from page: PDFPage) {
        if let name = annotation.persistentName {
            for link in page.annotations where link.value(forAnnotationKey: textBoxLinkOwnerKey) as? String == name { page.removeAnnotation(link) }
        }
        if let popup = annotation.popup, popup.page === page { page.removeAnnotation(popup) }
        page.removeAnnotation(annotation)
    }

    // MARK: Page tree rewrites

    /// When a write also rewrites the page tree, PDFKit drops keys it does not read; a text
    /// box Graphite wrote gets its kept keys and its `/Rotate` again
    /// (`preserveGraphiteKeysThroughPageTreeRewrite`).
    static func preserveTextBoxEntriesThroughPageTreeRewrite(of annotation: PDFAnnotation) {
        guard PDFTextBox.hasRecord(annotation), let box = PDFTextBox(annotation: annotation) else { return }
        box.setKeysPageTreeRewritesDrop(on: annotation)
    }
}
