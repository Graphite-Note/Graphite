/**
 * File: BaseEmbedLinkTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The embed of a base's view written for a note, and that `this` in an embedded view is the embedding
 *              note in every view type Graphite draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseEmbedLinkTests: XCTestCase {
    func testTheEmbedNamesTheBaseByItsPathAndTheView() throws {
        let base = try VaultPath("Courses/Assignments.base")
        XCTAssertEqual(BaseEmbedLink.text(basePath: base, viewName: "This course"), "![[Courses/Assignments.base#This course]]")
        XCTAssertEqual(BaseEmbedLink.text(basePath: base, viewName: " "), "![[Courses/Assignments.base]]")
        XCTAssertEqual(BaseEmbedLink.text(basePath: base, viewName: nil), "![[Courses/Assignments.base]]")
    }

    /// The query of an embedded base runs with the embedding note as `this` (`BaseDocumentModel.contextPath`), and every
    /// view type reads its rows from that query: a course note shows its own assignments, whatever the view draws.
    func testThisIsTheEmbeddingNoteInEveryViewType() throws {
        let records = [
            BaseTestRecords.record("Courses/VLSI 3.md", yaml: "type: course"),
            BaseTestRecords.record("Courses/Signals.md", yaml: "type: course"),
            BaseTestRecords.record("Courses/Assignments/Lab 1.md", yaml: "course:\n  - \"[[VLSI 3]]\"\nstatus: open\nplace: [46.5, 6.6]"),
            BaseTestRecords.record("Courses/Assignments/Lab 2.md", yaml: "course: \"[[VLSI 3]]\"\nstatus: done\nplace: [46.6, 6.7]"),
            BaseTestRecords.record("Courses/Assignments/Essay.md", yaml: "course:\n  - \"[[Signals]]\"\nstatus: open\nplace: [47, 8]"),
        ]
        let viewTypes: [BaseViewType] = [.table, .cards, .list, .kanban, .map]
        let views = viewTypes.map { type in
            "  - type: \(type.rawValue)\n    name: \(type.rawValue)\n    filters: 'list(course).contains(this)'\n    groupBy:\n      property: status\n"
                + "    coordinates: note.place\n"
        }.joined()
        let definition = try BaseDefinition.parse("filters: file.inFolder(\"Courses/Assignments\")\nviews:\n" + views)
        for (course, expected) in [("Courses/VLSI 3.md", ["Lab 1", "Lab 2"]), ("Courses/Signals.md", ["Essay"])] {
            let embeddingNote = try XCTUnwrap(records.first { record in record.path.rawValue == course })
            let engine = BaseQueryEngine(definition: definition, environment: BaseTestRecords.environment(), thisRecord: embeddingNote,
                                         provider: BaseInMemoryRecordProvider(records: records))
            for (viewIndex, type) in viewTypes.enumerated() {
                let result = engine.run(viewIndex: viewIndex, records: records)
                XCTAssertEqual(result.view.type, type)
                XCTAssertEqual(result.rows.map(\.path.stem).sorted(), expected, "\(type.rawValue) embedded in \(course)")
            }
        }
    }
}
