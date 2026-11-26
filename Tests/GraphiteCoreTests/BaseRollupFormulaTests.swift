/**
 * File: BaseRollupFormulaTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The formulas of a relation's reverse side and of rollups, evaluated over records of courses and their
 *              assignments.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseRollupFormulaTests: XCTestCase {
    private let course = BaseTestRecords.record("Courses/VLSI 3.md", yaml: "type: course\ncredits: 6")
    private let otherCourse = BaseTestRecords.record("Courses/Signals.md", yaml: "type: course\ncredits: 4")
    private lazy var records: [BaseFileRecord] = [
        course, otherCourse,
        BaseTestRecords.record("Courses/Assignments/Lab 1.md", yaml: "course:\n  - \"[[VLSI 3]]\"\ndone: true\nweight: 10",
                               links: [BaseTestRecords.wikiLink("VLSI 3")]),
        BaseTestRecords.record("Courses/Assignments/Lab 2.md", yaml: "course: \"[[VLSI 3]]\"\ndone: false\nweight: 30",
                               links: [BaseTestRecords.wikiLink("VLSI 3")]),
        BaseTestRecords.record("Courses/Assignments/Essay.md", yaml: "course:\n  - \"[[Signals]]\"\ndone: true\nweight: 50",
                               links: [BaseTestRecords.wikiLink("Signals")]),
        // Links to the course in its body only: a backlink, not an assignment of it.
        BaseTestRecords.record("Notes/Mention.md", yaml: "", links: [BaseTestRecords.wikiLink("VLSI 3")]),
    ]

    private func evaluate(_ sourceText: String, for record: BaseFileRecord, formulas: [BaseFormula] = []) throws -> BaseValue {
        let evaluator = BaseEvaluator(formulas: formulas, environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: records)
        return try evaluator.evaluate(sourceText: sourceText, for: record)
    }

    private var assignmentsFormula: BaseFormula {
        BaseFormula(name: "assignments", sourceText: BaseRollupFormula.relatedNotes(.linkingHere(property: "course")))
    }

    func testTheReverseSideIsTheNotesWhosePropertyLinksHereAndNotEveryBacklink() throws {
        let value = try evaluate(BaseRollupFormula.relatedNotes(.linkingHere(property: "course")), for: course)
        guard case .list(let elements) = value else { return XCTFail("Expected a list, got \(value)") }
        let paths = elements.compactMap { element -> String? in
            if case .file(let path) = element { return path.rawValue }
            return nil
        }
        XCTAssertEqual(Set(paths), ["Courses/Assignments/Lab 1.md", "Courses/Assignments/Lab 2.md"])
    }

    func testRollupsOverTheReverseSideCountSumAndShareTheCheckedNotes() throws {
        let formulas = [assignmentsFormula]
        let through = BaseRollupRelation.formula(name: "assignments")
        func rollup(_ property: String?, _ calculation: BaseRollupCalculation) throws -> BaseValue {
            let sourceText = try XCTUnwrap(BaseRollupFormula.sourceText(relation: through, property: property, calculation: calculation))
            return try evaluate(sourceText, for: course, formulas: formulas)
        }
        XCTAssertEqual(try rollup(nil, .count), .number(2))
        XCTAssertEqual(try rollup("weight", .sum), .number(40))
        XCTAssertEqual(try rollup("weight", .average), .number(20))
        XCTAssertEqual(try rollup("weight", .minimum), .number(10))
        XCTAssertEqual(try rollup("weight", .maximum), .number(30))
        XCTAssertEqual(try rollup("done", .countChecked), .number(1))
        XCTAssertEqual(try rollup("done", .percentChecked), .number(50))
        let lonely = BaseTestRecords.record("Courses/Empty.md", yaml: "type: course")
        let percentText = try XCTUnwrap(BaseRollupFormula.sourceText(relation: through, property: "done", calculation: .percentChecked))
        XCTAssertEqual(try evaluate(percentText, for: lonely, formulas: formulas), .number(0))
    }

    func testARollupThroughALinkPropertyReadsTheLinkedNotes() throws {
        let lab = try XCTUnwrap(records.first { record in record.path.stem == "Lab 1" })
        let creditsText = try XCTUnwrap(BaseRollupFormula.sourceText(relation: .linkedBy(property: "course"), property: "credits", calculation: .sum))
        XCTAssertEqual(try evaluate(creditsText, for: lab), .number(6))
        let countText = try XCTUnwrap(BaseRollupFormula.sourceText(relation: .linkedBy(property: "course"), property: nil, calculation: .count))
        XCTAssertEqual(try evaluate(countText, for: BaseTestRecords.record("Loose.md")), .number(0))
    }

    func testACalculationThatReadsAPropertyNeedsOneAndNamesAreWrittenSafely() {
        XCTAssertNil(BaseRollupFormula.sourceText(relation: .formula(name: "a"), property: " ", calculation: .sum))
        XCTAssertEqual(BaseRollupFormula.noteProperty("due date"), "note[\"due date\"]")
        XCTAssertEqual(BaseRollupFormula.member("course"), ".course")
        XCTAssertEqual(BaseRollupFormula.uniqueName("Assignments", existing: ["assignments", "Assignments 2"]), "Assignments 3")
        XCTAssertEqual(BaseRollupFormula.uniqueName("", existing: []), "rollup")
    }

    func testAsFileOnAFileReturnsTheFile() throws {
        XCTAssertEqual(try evaluate("file.asFile()", for: course), .file(course.path))
    }
}
