/**
 * File: BaseNewItemNoteTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Where New in a base view makes its note, how its values are written as properties, and its text from
 *              a template.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseNewItemNoteTests: XCTestCase {
    private let currentFile = (try? VaultPath("Courses/VLSI 3.md")) ?? .root

    func testTheFolderComesFromNewItemFolderThenTheFiltersThenTheTemplateThenTheVaultSetting() throws {
        let template = try VaultPath("Templates/Assignment.md")
        XCTAssertEqual(BaseNewItemNote.folder(newItemFolder: "Inbox/", filterFolder: "Assignments", templatePath: template,
                                              newNoteLocation: .vaultFolder, currentFile: currentFile), try VaultPath("Inbox"))
        XCTAssertEqual(BaseNewItemNote.folder(newItemFolder: nil, filterFolder: "Assignments", templatePath: template,
                                              newNoteLocation: .vaultFolder, currentFile: currentFile), try VaultPath("Assignments"))
        XCTAssertEqual(BaseNewItemNote.folder(newItemFolder: nil, filterFolder: nil, templatePath: template,
                                              newNoteLocation: .vaultFolder, currentFile: currentFile), try VaultPath("Templates"))
        XCTAssertEqual(BaseNewItemNote.folder(newItemFolder: nil, filterFolder: nil, templatePath: nil,
                                              newNoteLocation: .sameFolderAsCurrentFile, currentFile: currentFile), try VaultPath("Courses"))
        XCTAssertEqual(BaseNewItemNote.folder(newItemFolder: "/", filterFolder: "Assignments", templatePath: nil,
                                              newNoteLocation: .sameFolderAsCurrentFile, currentFile: currentFile), .root)
    }

    func testValuesAreWrittenAsTypedPropertiesWithLinksNamedFromTheNewNote() throws {
        let course = try VaultPath("Courses/VLSI 3.md")
        let linkText: (VaultPath) -> String = { path in path.stem }
        let calendar = BaseDateFormatting.displayCalendar
        XCTAssertEqual(BaseNewItemNote.propertyValue(.note(course, display: nil), linkText: linkText, calendar: calendar), .text("[[VLSI 3]]"))
        XCTAssertEqual(BaseNewItemNote.propertyValue(.list([.note(course, display: "VLSI")]), linkText: linkText, calendar: calendar),
                       .list(["[[VLSI 3|VLSI]]"]))
        XCTAssertEqual(BaseNewItemNote.propertyValue(.number(3), linkText: linkText, calendar: calendar), .number(3))
        XCTAssertEqual(BaseNewItemNote.propertyValue(.boolean(false), linkText: linkText, calendar: calendar), .checkbox(false))
        XCTAssertEqual(BaseNewItemNote.propertyValue(.empty, linkText: linkText, calendar: calendar), .empty)
        XCTAssertEqual(BaseNewItemNote.propertyValue(.unresolvedLink("Missing", display: nil), linkText: linkText, calendar: calendar), .text("[[Missing]]"))
        XCTAssertEqual(BaseNewItemNote.propertyValue(.list([.text("a"), .list([.text("b")])]), linkText: linkText, calendar: calendar), .list(["a", "b"]))
    }

    func testTheTextSetsThePlansPropertiesOverTheTemplatesAndKeepsItsBody() throws {
        let template = "---\ntype: assignment\ncourse:\ndone: false\n---\n## Task\n\nWrite it here.\n"
        let text = try BaseNewItemNote.text(template: template, properties: [
            NoteProperty(key: "Course", value: .list(["[[VLSI 3]]"])), NoteProperty(key: "due", value: .empty),
        ], declaredTypes: [:])
        let properties = try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: text).flatMap { yaml in NoteProperties.parse(yaml) })
        XCTAssertEqual(properties.map(\.key), ["type", "course", "done", "due"])
        XCTAssertEqual(properties[1].value, .list(["[[VLSI 3]]"]))
        XCTAssertTrue(text.hasSuffix("---\n## Task\n\nWrite it here.\n"))
    }

    func testWithoutATemplateTheTextIsTheFrontmatterAlone() throws {
        let text = try BaseNewItemNote.text(template: nil, properties: [NoteProperty(key: "course", value: .list(["[[VLSI 3]]"]))], declaredTypes: [:])
        XCTAssertEqual(text, "---\ncourse:\n  - \"[[VLSI 3]]\"\n---\n")
        XCTAssertEqual(try BaseNewItemNote.text(template: nil, properties: [], declaredTypes: [:]), "")
    }

    func testATemplateWhosePropertiesCannotBeReadIsRefused() {
        XCTAssertThrowsError(try BaseNewItemNote.text(template: "---\n- a list\n---\nBody\n", properties: [], declaredTypes: [:])) { error in
            XCTAssertEqual(error as? BaseNewItemError, .unreadableTemplateProperties)
        }
    }
}
