/**
 * File: PDFUndoManagerTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: A PDF's undo history first records what a view shows that it has not recorded, as a step of its own,
 *              and that step is the one Undo takes back (HUNT-005).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// The history's own part of HUNT-005: a canvas holding a stroke its history had not recorded made the step undone
/// meet a drawing it did not know. Here a view's recorder stands for the canvas: it registers its change when asked
/// before a step of the history, as `PDFAnnotationCoordinator.recordUnrecordedInkBeforeHistoryStep` does.
@MainActor
final class PDFUndoManagerTests: XCTestCase {
    private func openTwoPagePDF() async throws -> PDFSession {
        let directory = try TemporaryVault.make(prefix: "PDFUndoManager", for: self).root
        let location = directory.appendingPathComponent("Pages.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 2).write(to: location)
        return try await PDFSession.open(location)
    }

    func testUndoFirstRecordsWhatAViewHasNotRecordedAndTakesThatBackFirst() async throws {
        let session = try await openTwoPagePDF()
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        try session.rotatePages([0], clockwise: true)
        try await waitUntil("the rotation's step is closed") { session.undoManager.groupingLevel == 0 }
        XCTAssertEqual(firstPage.rotation, 90)

        // A change the view shows and has not recorded: it is recorded only when the history asks.
        var hasUnrecordedChange = true
        var isUnrecordedChangeShown = true
        var recordingCount = 0
        let viewOwner = NSObject()
        session.registerUnrecordedInkRecorder(for: viewOwner) {
            guard hasUnrecordedChange else { return }
            hasUnrecordedChange = false
            recordingCount += 1
            session.registerStep(named: "Drawing") { _ in isUnrecordedChangeShown = false } redo: { _ in isUnrecordedChangeShown = true }
        }

        session.undoAvailability.undo()
        XCTAssertEqual(recordingCount, 1, "Undo first recorded the change shown")
        XCTAssertFalse(isUnrecordedChangeShown, "and took it back first")
        XCTAssertEqual(firstPage.rotation, 90, "The step before it stays")
        session.undoAvailability.undo()
        XCTAssertEqual(firstPage.rotation, 0, "The next Undo takes back the step before")
        XCTAssertEqual(recordingCount, 1, "Nothing more was recorded")

        session.undoAvailability.redo()
        XCTAssertEqual(firstPage.rotation, 90)
        session.undoAvailability.redo()
        XCTAssertTrue(isUnrecordedChangeShown, "Redo brings the recorded change back")
        XCTAssertFalse(session.undoAvailability.canRedo)

        // ⌘Z reaches the history without the toolbar: the same recording happens first.
        hasUnrecordedChange = true
        session.undoManager.undo()
        XCTAssertEqual(recordingCount, 2)
        XCTAssertFalse(isUnrecordedChangeShown, "The change undone is the one just recorded")
        XCTAssertEqual(firstPage.rotation, 90)
        session.unregisterPendingInkRecordWriter(for: viewOwner)
        hasUnrecordedChange = true
        session.undoManager.undo()
        XCTAssertEqual(recordingCount, 2, "A view that went records nothing")
        XCTAssertEqual(firstPage.rotation, 90, "The earlier change was undone, not the rotation")
    }
}
