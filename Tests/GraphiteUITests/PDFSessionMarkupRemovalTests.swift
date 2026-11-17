/**
 * File: PDFSessionMarkupRemovalTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Removing several text marks at once through the PDF session, as the iPad's eraser does with the marks
 *              one stroke passed over: one step across pages, undone and redone whole, no step for none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
import CoreText
import PDFKit
import GraphiteApple
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

@MainActor
final class PDFSessionMarkupRemovalTests: XCTestCase {
    private static let pageTexts = ["The gain sets the bandwidth of the stage.", "A second page with its own line of text."]
    private static let pageSize = CGSize(width: 400, height: 600)

    private func openSession() async throws -> PDFSession {
        let location = try TemporaryVault.make(prefix: "PDFSessionMarkupRemoval", for: self).location(of: "Lecture.pdf")
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        for pageText in Self.pageTexts {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: pageText, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            context.textPosition = CGPoint(x: 40, y: 500)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        return session
    }

    private func mark(_ kind: PDFMarkupKind, _ text: String, onPage pageIndex: Int, in session: PDFSession) throws {
        let page = try XCTUnwrap(session.document.page(at: pageIndex))
        let selection = try XCTUnwrap(page.selection(for: (Self.pageTexts[pageIndex] as NSString).range(of: text)))
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try session.addMarkup(kind, color: kind == .highlight ? .yellow : .red, for: selection)
    }

    private func marks(onPage pageIndex: Int, in session: PDFSession) -> [PDFAnnotation] {
        session.document.page(at: pageIndex)?.annotations.filter { annotation in PDFMarkup(annotation: annotation) != nil } ?? []
    }

    private func removeAsOneStep(_ marks: [(annotation: PDFAnnotation, page: PDFPage)], in session: PDFSession) throws {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try session.removeMarkups(marks)
    }

    func testThreeMarksOnTwoPagesAreRemovedAsOneStepThatOneUndoPutsBack() async throws {
        let session = try await openSession()
        try mark(.highlight, "gain", onPage: 0, in: session)
        try mark(.underline, "bandwidth", onPage: 0, in: session)
        try mark(.highlight, "second page", onPage: 1, in: session)
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let secondPage = try XCTUnwrap(session.document.page(at: 1))
        let marksBefore = (marks(onPage: 0, in: session) + marks(onPage: 1, in: session)).compactMap(PDFMarkup.init(annotation:))
        XCTAssertEqual(marksBefore.count, 3)

        try removeAsOneStep(marks(onPage: 0, in: session).map { ($0, firstPage) } + marks(onPage: 1, in: session).map { ($0, secondPage) }, in: session)

        XCTAssertTrue(marks(onPage: 0, in: session).isEmpty)
        XCTAssertTrue(marks(onPage: 1, in: session).isEmpty)
        XCTAssertEqual(session.undoAvailability.undoActionName, "Remove Marks")
        session.undoAvailability.undo()
        let marksAfterUndo = (marks(onPage: 0, in: session) + marks(onPage: 1, in: session)).compactMap(PDFMarkup.init(annotation:))
        XCTAssertEqual(Set(marksAfterUndo.map(\.kind.title)), Set(marksBefore.map(\.kind.title)))
        XCTAssertEqual(marks(onPage: 0, in: session).count, 2, "One undo puts both marks of the first page back.")
        XCTAssertEqual(marks(onPage: 1, in: session).count, 1, "And the second page's.")
        XCTAssertEqual(marksAfterUndo.map(\.lineBounds), marksBefore.map(\.lineBounds), "Each where it was.")
        session.undoAvailability.redo()
        XCTAssertTrue(marks(onPage: 0, in: session).isEmpty && marks(onPage: 1, in: session).isEmpty, "Redo removes all three again.")
    }

    func testOneMarkRemovedIsNamedForItsKind() async throws {
        let session = try await openSession()
        try mark(.underline, "bandwidth", onPage: 0, in: session)
        let page = try XCTUnwrap(session.document.page(at: 0))

        try removeAsOneStep(marks(onPage: 0, in: session).map { ($0, page) }, in: session)

        XCTAssertEqual(session.undoAvailability.undoActionName, "Remove \(PDFMarkupKind.underline.title)")
    }

    func testNoMarksOrMarksAlreadyGoneMakeNoStep() async throws {
        let session = try await openSession()
        try mark(.highlight, "gain", onPage: 0, in: session)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let gone = try XCTUnwrap(marks(onPage: 0, in: session).first)
        try removeAsOneStep([(gone, page)], in: session)
        let actionAfterRemoval = session.undoAvailability.undoActionName

        // Outside an undo group, which would itself count as a step: with grouping by event off, registering a step
        // here would raise, so none is made.
        try session.removeMarkups([])
        try session.removeMarkups([(gone, page)])

        XCTAssertEqual(session.undoAvailability.undoActionName, actionAfterRemoval, "No new step for none, nor for a mark already removed.")
        session.undoAvailability.undo()
        XCTAssertEqual(marks(onPage: 0, in: session).count, 1, "The one undo left is the first removal's.")
    }
}
