/**
 * File: PDFNoteTests.swift
 * ------------------------
 * Layer: Tests
 * Description: Notes as they are written into a PDF read from a file: a standard `/Text` annotation with the Comment icon,
 *              its text, colour, name, author and appearance, read back after a save; edited, moved and deleted; another
 *              application's note keeping its icon and author, and its popup going with it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

final class PDFNoteTests: XCTestCase {
    /// A blank page read from a file's bytes, as every PDF Graphite edits is: PDFKit treats annotations on such a document
    /// differently from those on a document made in memory.
    private func blankDocument() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
    }

    /// The author a test writes as, whatever the name chosen on the device.
    private func author(named name: String) throws -> PDFAnnotationAuthor {
        let suiteName = "PDFNoteTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        return PDFAnnotationAuthor(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)), ownerName: { name })
    }

    private func reread(_ document: PDFDocument) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
    }

    private let note = PDFNote(name: "question", contents: "Why does the sampling rate double?\nAsk in the exercise session.",
                               iconBounds: CGRect(x: 100, y: 700, width: 24, height: 24), color: PDFNote.colors[2].color)

    func testANoteIsATextAnnotationWithItsTextColourNameAndAuthor() throws {
        let document = try blankDocument()
        try PDFPageManager.apply(.addNote(page: 0, note: note), to: document, author: try author(named: "Ada"))
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try XCTUnwrap(document.dataRepresentation())) { dictionaries in
            XCTAssertEqual(dictionaries.count, 1, "The note alone, without a popup PDFKit would write badly.")
            let written = try XCTUnwrap(dictionaries.first)
            XCTAssertEqual(PDFAnnotationDictionaryReading.name("Subtype", in: written), "Text")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("Contents", in: written), note.contents)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("NM", in: written), "question")
            XCTAssertEqual(PDFAnnotationDictionaryReading.name("Name", in: written), "Comment")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("T", in: written), "Ada")
            XCTAssertEqual(PDFAnnotationDictionaryReading.numbers("Rect", in: written), [100, 700, 124, 724])
            XCTAssertTrue(PDFAnnotationDictionaryReading.hasKey("AP", in: written), "Readers that draw only appearances show the icon.")
            let colour = try XCTUnwrap(PDFAnnotationDictionaryReading.numbers("C", in: written))
            XCTAssertEqual(colour.count, 3)
            XCTAssertEqual(colour[2], 1, accuracy: 0.01, "The blue of the note's colours.")
        }
        let readBack = try XCTUnwrap(try reread(document).page(at: 0)?.annotations.compactMap(PDFNote.init(annotation:)).first)
        XCTAssertEqual(readBack.contents, note.contents)
        XCTAssertEqual(readBack.name, "question")
        XCTAssertEqual(readBack.iconBounds, note.iconBounds)
        XCTAssertEqual(readBack.color, note.color)
        XCTAssertEqual(readBack.iconName, "Comment")
        XCTAssertEqual(readBack.author, "Ada")
    }

    func testANewNoteIsPlacedWithItsIconOnThePage() {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        XCTAssertEqual(PDFNote.placed(at: CGPoint(x: 300, y: 400), on: page, contents: "").iconBounds, CGRect(x: 300, y: 376, width: 24, height: 24))
        XCTAssertEqual(PDFNote.placed(at: CGPoint(x: 610, y: 5), on: page, contents: "").iconBounds, CGRect(x: 588, y: 0, width: 24, height: 24))
    }

    func testEditingAndMovingANoteReplacesItKeepingItsAuthorAndDeletingRemovesIt() throws {
        let document = try blankDocument()
        try PDFPageManager.apply(.addNote(page: 0, note: note), to: document, author: try author(named: "Ada"))
        let page = try XCTUnwrap(document.page(at: 0))
        var edited = try XCTUnwrap(page.annotations.compactMap(PDFNote.init(annotation:)).first)
        edited.contents = "Answered: Nyquist."
        edited = edited.moved(by: CGVector(dx: 50, dy: -100), within: page.bounds(for: .mediaBox))
        let reference = PDFAnnotationReference(annotation: try XCTUnwrap(page.annotations.first), pageIndex: 0)
        try PDFPageManager.apply(.replaceNote(reference, with: edited), to: document, author: try author(named: "Someone Else"))
        // PDFKit gives a note a popup of its own in memory, which it does not write (the test above): the notes alone count.
        XCTAssertEqual(page.annotations.filter(PDFNote.isNote).count, 1, "One note, the former gone.")
        let replaced = try XCTUnwrap(page.annotations.first(where: PDFNote.isNote))
        XCTAssertEqual(replaced.contents, "Answered: Nyquist.")
        XCTAssertEqual(replaced.bounds.origin, CGPoint(x: 150, y: 600))
        XCTAssertEqual(replaced.userName, "Ada", "An edited note keeps the author it had.")
        try PDFPageManager.apply(.removeAnnotation(PDFAnnotationReference(annotation: replaced, pageIndex: 0)), to: document)
        XCTAssertTrue(page.annotations.isEmpty, "The note and the popup PDFKit gave it are gone.")
    }

    func testAnotherApplicationsNoteIsReadWithItsIconAndKeepsItAndItsPopupGoesWithIt() throws {
        // A note as Preview writes it into a new document, with its popup.
        let original = PDFDocument()
        original.insert(PDFPage(), at: 0)
        let originalPage = try XCTUnwrap(original.page(at: 0))
        let previewNote = PDFAnnotation(bounds: CGRect(x: 40, y: 40, width: 20, height: 20), forType: .text, withProperties: nil)
        previewNote.iconType = .key
        previewNote.contents = "From Preview"
        previewNote.userName = "Grace"
        let previewPopup = PDFAnnotation(bounds: CGRect(x: 70, y: 40, width: 150, height: 90), forType: .popup, withProperties: nil)
        previewNote.popup = previewPopup
        originalPage.addAnnotation(previewNote)
        originalPage.addAnnotation(previewPopup)

        let rereadDocument = try reread(original)
        let page = try XCTUnwrap(rereadDocument.page(at: 0))
        let noteAnnotation = try XCTUnwrap(page.annotations.first { annotation in PDFNote.isNote(annotation) })
        var read = try XCTUnwrap(PDFNote(annotation: noteAnnotation))
        XCTAssertEqual(read.contents, "From Preview")
        XCTAssertEqual(read.iconName, "Key")
        XCTAssertEqual(read.author, "Grace")
        read.contents = "From Preview, answered"
        try PDFPageManager.apply(.replaceNote(PDFAnnotationReference(annotation: noteAnnotation, pageIndex: 0), with: read), to: rereadDocument,
                                 author: try author(named: "Ada"))
        XCTAssertEqual(page.annotations.filter(PDFNote.isNote).count, 1)
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Popup" }.count, 1, "The former's popup went with it.")
        let replaced = try XCTUnwrap(page.annotations.first(where: PDFNote.isNote))
        XCTAssertEqual(replaced.iconType, .key, "Its icon stays.")
        XCTAssertEqual(replaced.userName, "Grace")
        XCTAssertEqual(replaced.contents, "From Preview, answered")
    }
}
