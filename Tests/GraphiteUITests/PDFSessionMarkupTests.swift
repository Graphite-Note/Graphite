/**
 * File: PDFSessionMarkupTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Marking text that a mark of the same kind is already on, through the PDF session on the Mac and the
 *              iPad: the same text marked again changes the mark, overlapping text joins the marks, a highlight
 *              and an underline stay two, each one step, and the saved file holds one annotation per run of text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import CoreText
import PDFKit
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class PDFSessionMarkupTests: XCTestCase {
    private static let pageText = "The gain sets the bandwidth of the stage."
    private static let pageSize = CGSize(width: 400, height: 600)

    private func openSession() async throws -> (session: PDFSession, page: PDFPage, location: URL) {
        let location = try TemporaryVault.make(prefix: "PDFSessionMarkup", for: self).location(of: "Lecture.pdf")
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: Self.pageText, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        context.textPosition = CGPoint(x: 40, y: 500)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        return (session, try XCTUnwrap(session.document.page(at: 0)), location)
    }

    private func selection(of text: String, on page: PDFPage) throws -> PDFSelection {
        try XCTUnwrap(page.selection(for: (Self.pageText as NSString).range(of: text)))
    }

    private func marks(on page: PDFPage) -> [PDFMarkup] {
        page.annotations.compactMap(PDFMarkup.init(annotation:))
    }

    /// The text under a mark's lines, read back from the page.
    private func markedText(of mark: PDFMarkup, on page: PDFPage) -> String {
        mark.lineBounds.compactMap { line in page.selection(for: line.insetBy(dx: 1, dy: 2))?.string }.joined(separator: " ")
    }

    private func step(in session: PDFSession, _ operation: () throws -> Void) rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try operation()
    }

    func testTheSameTextHighlightedAgainInAnotherColourChangesTheMarkAndNeverStacksOne() async throws {
        let (session, page, _) = try await openSession()
        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "bandwidth", on: page)) }
        let name = try XCTUnwrap(marks(on: page).first?.name)

        try step(in: session) { try session.addMarkup(.highlight, color: .green, for: selection(of: "bandwidth", on: page)) }

        XCTAssertEqual(marks(on: page).map(\.color), [.green])
        XCTAssertEqual(marks(on: page).map(\.name), [name], "The mark itself changed, not a new one over it.")
        XCTAssertEqual(session.undoAvailability.undoActionName, "Highlight")
        session.undoAvailability.undo()
        XCTAssertEqual(marks(on: page).map(\.color), [.yellow])
        session.undoAvailability.redo()
        XCTAssertEqual(marks(on: page).map(\.color), [.green])
    }

    func testTheSameTextHighlightedAgainInTheSameColourMakesNoStep() async throws {
        let (session, page, _) = try await openSession()
        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "the bandwidth of", on: page)) }
        let versionBefore = session.changeVersion

        // Not in a group of its own: an empty group would be a step of its own to undo.
        try session.addMarkup(.highlight, color: .yellow, for: selection(of: "bandwidth", on: page))

        XCTAssertEqual(marks(on: page).count, 1)
        XCTAssertEqual(session.changeVersion, versionBefore, "Nothing changed, so nothing is saved.")
        session.undoAvailability.undo()
        XCTAssertEqual(marks(on: page), [], "The only step is the first highlight.")
    }

    func testOverlappingTextJoinsTheMarksIntoOneAsOneStep() async throws {
        let (session, page, location) = try await openSession()
        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "gain sets", on: page)) }
        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "the bandwidth", on: page)) }
        XCTAssertEqual(marks(on: page).count, 2, "Text past a space is a mark of its own.")

        try step(in: session) { try session.addMarkup(.highlight, color: .blue, for: selection(of: "sets the", on: page)) }

        let joined = try XCTUnwrap(marks(on: page).first)
        XCTAssertEqual(marks(on: page).count, 1)
        XCTAssertEqual(joined.color, .blue)
        XCTAssertEqual(joined.lineBounds.count, 1, "One run of text, one quadrilateral.")
        XCTAssertEqual(markedText(of: joined, on: page).trimmingCharacters(in: .whitespaces), "gain sets the bandwidth")

        try await session.save()
        let written = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
        XCTAssertEqual(written.annotations.filter { annotation in annotation.type == "Highlight" }.count, 1)

        session.undoAvailability.undo()
        XCTAssertEqual(Set(marks(on: page).map(\.color)), [.yellow])
        XCTAssertEqual(marks(on: page).count, 2, "Undo gives back both marks.")
        session.undoAvailability.redo()
        XCTAssertEqual(marks(on: page).map(\.color), [.blue])
    }

    func testAHighlightAndAnUnderlineOnTheSameTextStayTwoMarks() async throws {
        let (session, page, _) = try await openSession()
        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "bandwidth", on: page)) }
        try step(in: session) { try session.addMarkup(.underline, color: .red, for: selection(of: "bandwidth", on: page)) }
        XCTAssertEqual(marks(on: page).map(\.kind), [.highlight, .underline])
        try step(in: session) { try session.addMarkup(.underline, color: .blue, for: selection(of: "bandwidth", on: page)) }
        XCTAssertEqual(marks(on: page).map(\.kind), [.highlight, .underline])
        XCTAssertEqual(marks(on: page).map(\.color), [.yellow, .blue])
    }

    func testAMarkAnotherApplicationMadeIsJoinedAndKeepsItsNote() async throws {
        let (session, page, _) = try await openSession()
        let bounds = try selection(of: "bandwidth", on: page).bounds(for: page)
        let foreign = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        foreign.color = PDFMarkupColor.pink.platformColor
        foreign.contents = "Ask about this"
        page.addAnnotation(foreign)

        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "the bandwidth of", on: page)) }

        let annotations = page.annotations.filter { annotation in annotation.type == "Highlight" }
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.contents, "Ask about this")
        session.undoAvailability.undo()
        XCTAssertEqual(marks(on: page).map(\.color), [.pink], "Undo puts the other application's mark back as it was.")
        XCTAssertEqual(page.annotations.first { annotation in annotation.type == "Highlight" }?.contents, "Ask about this")
    }

    func testRecolouringAMarkToItsOwnColourMakesNoStep() async throws {
        let (session, page, _) = try await openSession()
        try step(in: session) { try session.addMarkup(.highlight, color: .yellow, for: selection(of: "bandwidth", on: page)) }
        let annotation = try XCTUnwrap(page.annotations.first)
        try session.recolorMarkup(annotation, on: page, to: .yellow)
        session.undoAvailability.undo()
        XCTAssertEqual(marks(on: page), [])
    }
}
