/**
 * File: PDFSessionTextBoxEmptyingTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: A text box whose text is all removed is deleted, whoever made it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class PDFSessionTextBoxEmptyingTests: XCTestCase {
    private func openSession() async throws -> PDFSession {
        let location = try TemporaryVault.make(prefix: "TextBoxEmptying", for: self).root.appendingPathComponent("Notebook.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        return session
    }

    /// One step of the PDF's history, as the editor makes it.
    private func inOneStep(in session: PDFSession, _ operation: () throws -> Void) rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try operation()
    }

    private func box(preservedEntries: [String: PDFPreservedValue]) -> PDFTextBox {
        PDFTextBox(runs: [PDFTextRun(text: "Typed", attributes: .plain)], origin: CGPoint(x: 50, y: 500), width: 200, height: 40, preservedEntries: preservedEntries)
    }

    /// HUNT-209: emptying a text box that another PDF app made left an invisible empty box in the file.
    func testEmptyingABoxAnotherAppMadeDeletesItWithItsKeptEntries() async throws {
        let session = try await openSession()
        let page = try XCTUnwrap(session.document.page(at: 0))
        let historyPage = session.historyPage(for: page)
        let foreign = box(preservedEntries: ["IT": .name("FreeTextTypeWriter"), "Subj": .text("Typewriter")])
        try inOneStep(in: session) { try session.changeTextBox(from: nil, to: foreign, on: historyPage, actionName: "Add Text Box") }
        XCTAssertEqual(session.textBoxes(on: page).count, 1)

        var emptied = foreign
        emptied.runs = []
        let step = PDFTextBoxEditStep(before: foreign, page: historyPage)
        try inOneStep(in: session) { try session.commitTextBox(emptied, in: step) }

        XCTAssertTrue(session.textBoxes(on: page).isEmpty)
        XCTAssertNil(step.after)
    }

    func testEmptyingABoxOfOurOwnStillDeletesIt() async throws {
        let session = try await openSession()
        let page = try XCTUnwrap(session.document.page(at: 0))
        let historyPage = session.historyPage(for: page)
        let own = box(preservedEntries: [:])
        try inOneStep(in: session) { try session.changeTextBox(from: nil, to: own, on: historyPage, actionName: "Add Text Box") }
        var emptied = own
        emptied.runs = []
        let step = PDFTextBoxEditStep(before: own, page: historyPage)
        try inOneStep(in: session) { try session.commitTextBox(emptied, in: step) }
        XCTAssertTrue(session.textBoxes(on: page).isEmpty)
    }
}
