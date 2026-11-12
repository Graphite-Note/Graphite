/**
 * File: SyntheticTextNotebooksTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The synthetic notebooks with typed text: their builders write the same bytes each time, and they plan
 *              their text as text boxes and flowing text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import CoreGraphics
import Foundation
import XCTest
@testable import NotebookImport

/// The synthetic notebooks with typed text of `Tests/SyntheticNotebooks`, which the app's import tests convert: they
/// plan as the import should. Setting `GRAPHITE_WRITE_SYNTHETIC_NOTEBOOKS` to that folder writes them again from the
/// builders (the builders write the same bytes at every run: fixed ZIP dates and a PDF written byte by byte).
final class SyntheticTextNotebooksTests: XCTestCase {
    private static let writeVariable = "GRAPHITE_WRITE_SYNTHETIC_NOTEBOOKS"

    func testTheBuildersWriteTheSameBytesEachTimeAndIntoTheFolderAskedFor() throws {
        let builtFiles = [(SyntheticTextNotebooks.goodnotesFileName, SyntheticTextNotebooks.goodnotesNotebook().archiveBytes()),
                          (SyntheticTextNotebooks.notabilityFileName, SyntheticTextNotebooks.notabilityNote().noteArchiveBytes())]
        XCTAssertEqual(builtFiles.map(\.1), [SyntheticTextNotebooks.goodnotesNotebook().archiveBytes(), SyntheticTextNotebooks.notabilityNote().noteArchiveBytes()])
        guard let folderPath = ProcessInfo.processInfo.environment[Self.writeVariable] else { return }
        for (name, bytes) in builtFiles { try bytes.write(to: URL(fileURLWithPath: folderPath, isDirectory: true).appendingPathComponent(name)) }
    }

    func testTheGoodnotesPagePlansEveryKindOfTypedTextAsATextBoxOverItsInk() throws {
        let reader = try GoodnotesNotebookReader(archiveBytes: SyntheticTextNotebooks.goodnotesNotebook().archiveBytes(), limits: .standard)
        XCTAssertEqual(reader.notebook.issues, [])
        let page = try reader.page(at: 0)
        XCTAssertEqual(page.issues, [])
        guard case .planned(let plan) = GoodnotesPagePlanner.plan(page, pageNumber: 1) else { return XCTFail("expected a page") }
        XCTAssertEqual(plan.sizeInPoints.width, 455.04, accuracy: 0.01)
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(plan.textBoxes.count, 4, "the heading, the turned box, the sticky note and the older box")
        XCTAssertEqual(plan.textBoxes.map(\.rotationRadiansClockwise), [0, Double(SyntheticTextNotebooks.turnedAngleRadians), 0, 0])
        guard case .runs(let headingRuns) = plan.textBoxes[0].content, case .rtf = plan.textBoxes[3].content else { return XCTFail("text kinds") }
        XCTAssertEqual(headingRuns.first?.link, URL(string: SyntheticTextNotebooks.headingLink))
        XCTAssertNotNil(plan.textBoxes[2].fillColor, "the sticky note keeps its paper colour")
        XCTAssertEqual(plan.report, [.stickyNotesAsTextBoxes(count: 1)])
    }

    func testTheNotabilityNoteIsLaidOutAtTheMacsWidthWithItsTextFlowingFromTheFirstPage() throws {
        let reader = try NotabilityNoteReader(archiveBytes: SyntheticTextNotebooks.notabilityNote().noteArchiveBytes(), limits: .standard)
        XCTAssertNil(reader.pageCount, "a reflowable note stores no page width")
        let laidOut = reader.layingOutReflowableNote(atPageWidthInUnits: NotabilityPageGeometry.macPageWidthInUnits)
        XCTAssertEqual(laidOut.pageCount, 1)
        guard case .planned(let plan) = NotabilityPagePlanner.plan(try laidOut.page(number: 1), note: laidOut.note) else {
            return XCTFail("expected a page")
        }
        XCTAssertEqual(plan.strokes.count, 1)
        let flowing = try XCTUnwrap(plan.flowingText)
        XCTAssertEqual(flowing.runs.map(\.isUnderlined), [false, true, false])
        XCTAssertEqual(flowing.runs.first?.font, .postScriptName("HelveticaNeue-Bold"))
        XCTAssertTrue(flowing.runs.last?.text.hasSuffix("note.") ?? false, "the empty lines after the last word are left out")
        XCTAssertEqual(plan.report, [.pageWidthAssumed])
    }
}
