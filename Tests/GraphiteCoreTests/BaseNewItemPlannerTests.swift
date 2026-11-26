/**
 * File: BaseNewItemPlannerTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The folder and properties New in a base view gives its note, rule by rule as Obsidian 1.15 reads the
 *              filters.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseNewItemPlannerTests: XCTestCase {
    private let course = BaseTestRecords.record("Courses/VLSI 3.md", yaml: "type: course")

    private func plan(_ yaml: String, viewIndex: Int = 0, this: BaseFileRecord? = nil, lists: Set<String> = []) throws -> BaseNewItemPlan {
        let definition = try BaseDefinition.parse(yaml)
        let newNote = BaseTestRecords.record("Untitled.md")
        let evaluator = BaseEvaluator(formulas: definition.formulas, environment: BaseTestRecords.environment(), thisRecord: this ?? course,
                                      knownRecords: [newNote])
        return BaseNewItemPlanner.plan(definition: definition, viewIndex: viewIndex, evaluator: evaluator, newNote: newNote,
                                       isListProperty: { name in lists.contains(name) })
    }

    private func value(_ name: String, in plan: BaseNewItemPlan) -> BaseNewItemValue? {
        plan.properties.first { property in property.name == name }?.value
    }

    func testAnEqualityWithThisSetsTheEmbeddingNoteAsALink() throws {
        let plan = try plan("views:\n  - type: table\n    filters:\n      and:\n        - course == this\n")
        XCTAssertEqual(value("course", in: plan), .note(try VaultPath("Courses/VLSI 3.md"), display: nil))
    }

    func testContainsOnAListPropertyGivesAOneItemListAndListOfThePropertyCountsAsIt() throws {
        let listPlan = try plan("filters: 'list(course).contains(this)'\nviews:\n  - type: table\n", lists: ["course"])
        XCTAssertEqual(value("course", in: listPlan), .list([.note(try VaultPath("Courses/VLSI 3.md"), display: nil)]))
        let textPlan = try plan("filters: 'course.contains(this)'\nviews:\n  - type: table\n")
        XCTAssertEqual(value("course", in: textPlan), .note(try VaultPath("Courses/VLSI 3.md"), display: nil))
    }

    func testComparisonsKeepTheirTypesAndALaterRuleReplacesAnEarlierOne() throws {
        let plan = try plan("""
            filters:
              and:
                - 'status == "open"'
                - 'weight >= 10'
                - 'done == false'
                - 'status == "todo"'
            views:
              - type: table
            """)
        XCTAssertEqual(plan.properties.map(\.name), ["status", "weight", "done"])
        XCTAssertEqual(value("status", in: plan), .text("todo"))
        XCTAssertEqual(value("weight", in: plan), .number(10))
        XCTAssertEqual(value("done", in: plan), .boolean(false))
    }

    func testRulesUnderAnOddNumberOfNotAndInequalitiesAreLeftOut() throws {
        let plan = try plan("""
            filters:
              and:
                - not:
                    - 'status == "done"'
                - not:
                    - not:
                        - 'priority == 1'
                - 'kind != "exam"'
                - 'size > 3'
            views:
              - type: table
            """)
        XCTAssertEqual(plan.properties, [BaseNewItemProperty(name: "priority", value: .number(1))])
    }

    func testFileRulesNameTheFolderTagsAndAddedProperties() throws {
        let plan = try plan("""
            filters:
              and:
                - file.inFolder("Courses/Assignments")
                - file.hasTag("eth/vlsi")
                - file.hasTag("homework")
                - file.hasProperty("due")
                - '!grade.isEmpty()'
            views:
              - type: table
            """)
        XCTAssertEqual(plan.filterFolder, "Courses/Assignments")
        XCTAssertEqual(value("tags", in: plan), .list([.text("eth/vlsi"), .text("homework")]))
        XCTAssertEqual(value("due", in: plan), .empty)
        XCTAssertEqual(value("grade", in: plan), .empty)
        XCTAssertEqual(try self.plan("filters: 'file.folder == \"Lectures\"'\nviews:\n  - type: table\n").filterFolder, "Lectures")
    }

    func testContainsAnySetsTheFirstValueAndTagsContainsSetsTags() throws {
        let plan = try plan("""
            filters:
              or:
                - 'kind.containsAny("lab", "exercise")'
                - 'file.tags.contains("week1")'
            views:
              - type: table
            """, lists: ["kind"])
        XCTAssertEqual(value("kind", in: plan), .list([.text("lab")]))
        XCTAssertEqual(value("tags", in: plan), .list([.text("week1")]))
    }

    func testTheViewsColumnsAreAddedEmptyAfterTheFiltersValuesAndTheViewsFiltersJoinTheBases() throws {
        let plan = try plan("""
            filters: 'type == "assignment"'
            views:
              - type: table
                name: All
              - type: table
                name: This course
                filters: 'course == this'
                order: [file.name, course, due, formula.left, done]
            """, viewIndex: 1)
        XCTAssertEqual(plan.properties.map(\.name), ["type", "course", "due", "done"])
        XCTAssertEqual(value("due", in: plan), .empty)
    }

    func testARuleThatCannotBeEvaluatedIsLeftOut() throws {
        let plan = try plan("filters: 'due == date(\"not a date\")'\nviews:\n  - type: table\n")
        XCTAssertEqual(plan.properties, [])
    }

    func testTargetsReadEveryFormObsidianReads() {
        XCTAssertEqual(BaseNewItemPlanner.target(of: .member(.identifier("note"), "due")), .note("due"))
        XCTAssertEqual(BaseNewItemPlanner.target(of: .subscripted(.identifier("note"), .literal(.string("due date")))), .note("due date"))
        XCTAssertEqual(BaseNewItemPlanner.target(of: .identifier("due")), .note("due"))
        XCTAssertEqual(BaseNewItemPlanner.target(of: .identifier("file")), .file("file"))
        XCTAssertEqual(BaseNewItemPlanner.target(of: .functionCall("list", [.identifier("course")])), .note("course"))
        XCTAssertNil(BaseNewItemPlanner.target(of: .member(.identifier("this"), "course")))
        XCTAssertNil(BaseNewItemPlanner.target(of: .literal(.number(1))))
    }
}
