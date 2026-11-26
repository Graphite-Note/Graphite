/**
 * File: BaseDefinitionEditorFormulasTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Setting a base's formulas and its newItemFolder and newItemTemplate keys, read back as Obsidian reads
 *              them, with the rest of the file as written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseDefinitionEditorFormulasTests: XCTestCase {
    private let base = """
        # Assignments of every course
        filters: file.inFolder("Assignments")
        formulas:
          left: (date(due) - today()).days
        views:
          - type: table
            name: All
            order: [file.name, due]
        """

    func testAFormulaIsAddedAfterTheOthersAndTheCommentStays() throws {
        var editor = try BaseDefinitionEditor(yaml: base)
        try editor.setFormula(named: "percent done", to: "if(formula.assignments.length == 0, 0, 1)")
        let yaml = try editor.yaml()
        XCTAssertTrue(yaml.hasPrefix("# Assignments of every course\n"))
        let definition = try BaseDefinition.parse(yaml)
        XCTAssertEqual(definition.formulas.map(\.name), ["left", "percent done"])
        XCTAssertEqual(definition.formulas.last?.sourceText, "if(formula.assignments.length == 0, 0, 1)")
    }

    func testAFormulaIsReplacedInPlaceAndABaseWithoutFormulasGetsThem() throws {
        var editor = try BaseDefinitionEditor(yaml: base)
        try editor.setFormula(named: "left", to: "due")
        XCTAssertEqual(try BaseDefinition.parse(editor.yaml()).formulas, [BaseFormula(name: "left", sourceText: "due")])
        var bare = try BaseDefinitionEditor(yaml: "views:\n  - type: table\n")
        try bare.setFormula(named: "count", to: "file.backlinks.length")
        XCTAssertEqual(try BaseDefinition.parse(bare.yaml()).formulas.map(\.name), ["count"])
    }

    func testFormulasThatAreNotAMappingAreRefused() throws {
        var editor = try BaseDefinitionEditor(yaml: "formulas:\n  - a\nviews: []\n")
        XCTAssertThrowsError(try editor.setFormula(named: "b", to: "1")) { error in
            XCTAssertEqual(error as? BaseDefinitionEditorError, .formulasAreNotAMapping)
        }
    }

    func testNewItemKeysAreWrittenReadAndRemoved() throws {
        var editor = try BaseDefinitionEditor(yaml: base)
        editor.setText("Courses/Assignments", for: .newItemFolder)
        editor.setText("Templates/Assignment.md", for: .newItemTemplate)
        let written = try editor.yaml()
        let definition = try BaseDefinition.parse(written)
        XCTAssertEqual(definition.newItemFolder, "Courses/Assignments")
        XCTAssertEqual(definition.newItemTemplate, "Templates/Assignment.md")
        var cleared = try BaseDefinitionEditor(yaml: written)
        cleared.setText("  ", for: .newItemFolder)
        XCTAssertNil(try BaseDefinition.parse(cleared.yaml()).newItemFolder)
        XCTAssertNil(try BaseDefinition.parse("newItemFolder: ~\nviews: []\n").newItemFolder)
    }
}
