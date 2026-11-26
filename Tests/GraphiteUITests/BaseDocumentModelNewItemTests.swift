/**
 * File: BaseDocumentModelNewItemTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: New in a base view, on a vault on disk: the note it makes, its folder, properties and template, a
 *              Kanban column's value, and the failures it reports.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class BaseDocumentModelNewItemTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!
    private var shownNotes: [VaultPath] = []

    private static let assignmentsBase = """
        filters:
          and:
            - file.inFolder("Courses/Assignments")
        views:
          - type: table
            name: This course
            filters: 'list(course).contains(this)'
            order: [file.name, due, done]
          - type: kanban
            name: Board
            groupBy:
              property: status
        """

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "BaseNewItemVault", files: [
            "Courses/VLSI 3.md": "---\ntype: course\n---\n",
            "Courses/Assignments/Old lab.md": "---\ncourse:\n  - \"[[VLSI 3]]\"\n---\n",
            "Assignments.base": Self.assignmentsBase,
        ], for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "BaseNewItemIndex", for: self).root
        index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
        _ = try await index.reconcile(root: vault)
    }

    private var services: BaseNoteServices {
        BaseNoteServices(linkTarget: { path, _ in path.stem }, searchNotes: { _, _ in [] },
                         fillTemplate: { text, title in text.replacingOccurrences(of: "{{title}}", with: title) },
                         newNoteLocation: .vaultFolder, vaultPropertyTypes: { ["course": .multitext] },
                         showNewNote: { [weak self] path in self?.shownNotes.append(path) })
    }

    /// The base embedded in the course note, as a course page shows it.
    private func embeddedModel(base: String = "Assignments.base", viewIndex: Int = 0) async throws -> BaseDocumentModel {
        let model = BaseDocumentModel(source: .file(try VaultPath(base)), contextPath: try VaultPath("Courses/VLSI 3.md"), store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        if viewIndex != 0 { await model.selectView(viewIndex) }
        return model
    }

    private func properties(at relativePath: String) throws -> [NoteProperty] {
        let text = try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
        return try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: text).flatMap { yaml in NoteProperties.parse(yaml) }, text)
    }

    func testNewInAViewEmbeddedInACourseLinksTheNoteToTheCourseAndTheViewShowsIt() async throws {
        let model = try await embeddedModel()
        let created = await model.createNewItem(named: "Lab 2", services: services)
        let path = try XCTUnwrap(created)
        XCTAssertEqual(path.rawValue, "Courses/Assignments/Lab 2.md")
        XCTAssertEqual(shownNotes, [path])
        let properties = try properties(at: path.rawValue)
        XCTAssertEqual(properties.map(\.key), ["course", "due", "done"])
        XCTAssertEqual(properties.first?.value, .list(["[[VLSI 3]]"]))

        try await index.refresh(paths: [path], root: vault)
        await model.runQuery()
        XCTAssertEqual(model.result?.rows.map(\.path.stem).sorted(), ["Lab 2", "Old lab"])
    }

    func testASecondNoteOfTheSameNameGetsAFreeNameAndAnEmptyNameIsUntitled() async throws {
        let model = try await embeddedModel()
        _ = await model.createNewItem(named: "Old lab", services: services)
        _ = await model.createNewItem(named: "  ", services: services)
        XCTAssertEqual(shownNotes.map(\.name), ["Old lab 1.md", "Untitled.md"])
    }

    func testTheTemplatesBodyIsFilledInAndTheFiltersValuesAreSetOverItsProperties() async throws {
        try "---\ncourse: none\nweight: 10\n---\n# {{title}}\n\nTask.\n".write(to: vault.appendingPathComponent("Templates/Assignment.md").creatingParent(), atomically: true,
                                                                              encoding: .utf8)
        try (Self.assignmentsBase + "\nnewItemTemplate: Templates/Assignment\n").write(to: vault.appendingPathComponent("Assignments.base"), atomically: true,
                                                                                         encoding: .utf8)
        let model = try await embeddedModel()
        let created = await model.createNewItem(named: "Essay", services: services)
        let path = try XCTUnwrap(created)
        XCTAssertEqual(path.rawValue, "Courses/Assignments/Essay.md", "The filters' folder comes before the template's")
        let text = try String(contentsOf: vault.appendingPathComponent(path.rawValue), encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("---\n# Essay\n\nTask.\n"), text)
        let properties = try properties(at: path.rawValue)
        XCTAssertEqual(properties.map(\.key), ["course", "weight", "due", "done"])
        XCTAssertEqual(properties.first?.value, .list(["[[VLSI 3]]"]))
    }

    func testNewInAKanbanColumnSetsTheColumnsValue() async throws {
        let model = try await embeddedModel(viewIndex: 1)
        let created = await model.createNewItem(named: "Card", inGroup: .value(.string("todo")), services: services)
        let path = try XCTUnwrap(created)
        XCTAssertEqual(try properties(at: path.rawValue).first { property in property.key == "status" }?.value, .text("todo"))
    }

    func testAMissingTemplateAndAFolderThatCannotBeMadeAreReportedAndNoNoteIsMade() async throws {
        try (Self.assignmentsBase + "\nnewItemTemplate: Templates/Missing.md\n").write(to: vault.appendingPathComponent("Assignments.base"), atomically: true,
                                                                                          encoding: .utf8)
        let model = try await embeddedModel()
        let missing = await model.createNewItem(named: "Lab", services: services)
        XCTAssertNil(missing)
        XCTAssertEqual(model.actionErrorMessage, BaseNewItemError.missingTemplate("Templates/Missing.md").errorDescription)

        // A file where the folder should be: the folder cannot be made, so the note is not.
        try "not a folder".write(to: vault.appendingPathComponent("Blocked"), atomically: true, encoding: .utf8)
        try (Self.assignmentsBase + "\nnewItemFolder: Blocked\n").write(to: vault.appendingPathComponent("Assignments.base"), atomically: true, encoding: .utf8)
        let blockedModel = try await embeddedModel()
        let blocked = await blockedModel.createNewItem(named: "Lab", services: services)
        XCTAssertNil(blocked)
        XCTAssertNotNil(blockedModel.actionErrorMessage)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Blocked"), encoding: .utf8), "not a folder")
        XCTAssertTrue(shownNotes.isEmpty)
    }
}

private extension URL {
    /// The URL, after making its folder.
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
