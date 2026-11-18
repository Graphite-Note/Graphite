/**
 * File: PDFPageDuplicationTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A written page duplicated in a PDF read from a file keeps its strokes as Graphite's ink when saved: their
 *              group, names and the page's re-editing record (HUNT-370).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
import XCTest
import PDFKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

/// Package tests only: `TemporaryVault` comes from `GraphiteTestSupport`, which the hosted iPad bundle does not build.
final class PDFPageDuplicationTests: XCTestCase {
    /// Every save replays its edits on the file as read, and the replay reads every page's annotations first; the
    /// duplicate of such a page lost its strokes' Graphite keys until HUNT-370.
    func testADuplicatedWrittenPageKeepsItsStrokesAsGraphitesInkWhenSaved() async throws {
        let location = try TemporaryVault.make(prefix: "PDFDuplicate", for: self).location(of: "Written.pdf")
        let created = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1),
                                                        at: location)
        let strokes = ["A", "B", "C"].enumerated().map { index, name in
            let height = 300 + CGFloat(index) * 60
            return PortableInkStroke(name: name, segments: [[CGPoint(x: 100, y: height), CGPoint(x: 400, y: height)]], width: 2,
                                     red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        }
        let written = try await PDFFileService().save(url: location, revision: created, edits: [
            .updateInk(PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]), addedStrokes: strokes,
                                    editableRecord: PDFEditableInkRecord(drawingData: Data([1]), strokeNames: ["A", "B", "C"]))),
        ])
        _ = try await PDFFileService().save(url: location, revision: written, edits: [.duplicate(page: 0)])

        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(saved.pageCount, 2)
        for pageIndex in 0..<2 {
            let page = try XCTUnwrap(saved.page(at: pageIndex))
            let ink = page.annotations.filter { annotation in annotation.type == "Ink" }
            XCTAssertEqual(ink.compactMap { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String }, ["ink", "ink", "ink"],
                           "Page \(pageIndex + 1)'s strokes are Graphite's ink.")
            XCTAssertEqual(ink.compactMap(\.persistentName), ["A", "B", "C"])
            XCTAssertEqual(PDFInkGroups.editableGroup(on: page)?.record.strokeNames, ["A", "B", "C"], "Page \(pageIndex + 1) can be edited stroke by stroke.")
        }
    }
}
