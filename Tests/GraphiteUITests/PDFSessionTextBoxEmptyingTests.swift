/**
 * File: PDFSessionTextBoxEmptyingTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: A text box whose text is all removed is deleted, whoever made it, and one nobody removed text from stays.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 02/11/2026
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

    /// A box as another PDF app can leave it: an annotation with empty `/Contents`, and entries of its own.
    private func addForeignBoxWithoutText(in session: PDFSession) throws -> (box: PDFTextBox, historyPage: PDFHistoryPage, page: PDFPage) {
        let page = try XCTUnwrap(session.document.page(at: 0))
        let historyPage = session.historyPage(for: page)
        var empty = box(preservedEntries: ["IT": .name("FreeTextTypeWriter")])
        empty.runs = []
        try inOneStep(in: session) { try session.changeTextBox(from: nil, to: empty, on: historyPage, actionName: "Add Text Box") }
        return (try XCTUnwrap(session.textBoxes(on: page).first), historyPage, page)
    }

    /// Tapping into a box without text and leaving removes no text, so nothing changes.
    func testLeavingABoxThatHadNoTextChangesNothing() async throws {
        let session = try await openSession()
        let (foreign, historyPage, page) = try addForeignBoxWithoutText(in: session)
        let stepsBefore = session.undoManager.groupingLevel
        let step = PDFTextBoxEditStep(before: foreign, page: historyPage)
        // The editor names a box that has no name as it begins typing.
        let typed = foreign.renamed(UUID().uuidString)
        try inOneStep(in: session) { try session.commitTextBox(typed, in: step) }

        XCTAssertEqual(session.textBoxes(on: page), [foreign], "The box is as the other app left it.")
        XCTAssertEqual(step.after, foreign)
        XCTAssertEqual(session.undoManager.groupingLevel, stepsBefore)
    }

    func testABoxThatHadNoTextGoesBackToHowItWasWhenWhatWasTypedIsRemoved() async throws {
        let session = try await openSession()
        let (foreign, historyPage, page) = try addForeignBoxWithoutText(in: session)
        let step = PDFTextBoxEditStep(before: foreign, page: historyPage)
        var typed = foreign
        typed.runs = [PDFTextRun(text: "Hello", attributes: .plain)]
        try inOneStep(in: session) {
            try session.commitTextBox(typed, in: step)
            XCTAssertEqual(session.textBoxes(on: page).first?.plainText, "Hello")
            typed.runs = []
            try session.commitTextBox(typed, in: step)
        }
        XCTAssertEqual(session.textBoxes(on: page).map(\.plainText), [foreign.plainText], "Nobody removed the box's own text, for it had none.")
    }

    func testANewBoxLeftWithoutTextIsNotAdded() async throws {
        let session = try await openSession()
        let page = try XCTUnwrap(session.document.page(at: 0))
        var empty = box(preservedEntries: [:])
        empty.runs = []
        try session.commitTextBox(empty, in: PDFTextBoxEditStep(before: nil, page: session.historyPage(for: page)))
        XCTAssertTrue(session.textBoxes(on: page).isEmpty)
    }

    /// A save while typing pauses takes what is typed. All the text being selected and deleted at that moment does not
    /// delete the box: the next key fills it again, and taking the box away would close the editor under the keyboard.
    func testASaveWhileTheTextIsEmptiedKeepsTheBoxAndItsEditor() async throws {
        let session = try await openSession()
        let page = try XCTUnwrap(session.document.page(at: 0))
        let historyPage = session.historyPage(for: page)
        let own = box(preservedEntries: [:])
        try inOneStep(in: session) { try session.changeTextBox(from: nil, to: own, on: historyPage, actionName: "Add Text Box") }
        let step = PDFTextBoxEditStep(before: own, page: historyPage)
        session.textBoxActivity = .editing(PDFTextBoxSelection(boxName: own.name, page: historyPage))
        var typed = own
        typed.runs = []
        try inOneStep(in: session) {
            try session.commitTextBox(typed, in: step, typingContinues: true)
            XCTAssertEqual(session.textBoxes(on: page).map(\.plainText), ["Typed"], "The box stays while typing goes on.")
            XCTAssertTrue(session.textBoxActivity.isEditing)
            typed.runs = [PDFTextRun(text: "Again", attributes: .plain)]
            try session.commitTextBox(typed, in: step, typingContinues: true)
            XCTAssertEqual(session.textBoxes(on: page).map(\.plainText), ["Again"])
            typed.runs = []
            try session.commitTextBox(typed, in: step)
        }
        XCTAssertTrue(session.textBoxes(on: page).isEmpty, "Typing ended with no text, so the person removed it.")
    }
}
