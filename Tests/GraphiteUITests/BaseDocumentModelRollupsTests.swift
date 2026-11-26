/**
 * File: BaseDocumentModelRollupsTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Saving a rollup and the New Note settings into a .base file on disk, and the rollup's values in the
 *              base's rows.
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
final class BaseDocumentModelRollupsTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "BaseRollupsVault", files: [
            "Courses/VLSI 3.md": "---\ntype: course\n---\n",
            "Assignments/Lab 1.md": "---\ncourse:\n  - \"[[VLSI 3]]\"\ndone: true\n---\n",
            "Assignments/Lab 2.md": "---\ncourse: \"[[VLSI 3]]\"\ndone: false\n---\n",
            "Notes/Mention.md": "See [[VLSI 3]].\n",
            "Courses.base": "# Courses\nfilters: type == \"course\"\nviews:\n  - type: table\n    name: Courses\n",
        ], for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "BaseRollupsIndex", for: self).root
        index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
        _ = try await index.reconcile(root: vault)
    }

    private func loadedModel() async throws -> BaseDocumentModel {
        let path = try VaultPath("Courses.base")
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        return model
    }

    func testARollupOverNotesLinkingHereWritesTheRelationOnceAndShowsItsValues() async throws {
        let model = try await loadedModel()
        let draft = BaseRollupDraft(name: "done", relation: .linkingHere(property: "course"), property: "done", calculation: .countChecked)
        let saved = await model.addRollup(draft)
        XCTAssertTrue(saved)
        let count = BaseRollupDraft(name: "assignments", relation: .linkingHere(property: "course"), property: "", calculation: .count)
        let savedCount = await model.addRollup(count)
        XCTAssertTrue(savedCount)

        let text = try String(contentsOf: vault.appendingPathComponent("Courses.base"), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Courses\n"))
        let definition = try BaseDefinition.parse(text)
        XCTAssertEqual(definition.formulas.map(\.name), ["course backlinks", "done", "assignments"])
        XCTAssertEqual(definition.views.first?.order, [.file("name"), .formula("done"), .formula("assignments")])

        let row = try XCTUnwrap(model.result?.rows.first)
        let columns = model.result?.columns.map(\.property) ?? []
        let doneCell = columns.firstIndex(of: .formula("done")).map { column in row.cells[column] }
        let countCell = columns.firstIndex(of: .formula("assignments")).map { column in row.cells[column] }
        XCTAssertEqual(doneCell, .value(.number(1)))
        XCTAssertEqual(countCell, .value(.number(2)))
    }

    func testTheNewNoteSettingsAreWrittenAsObsidiansKeys() async throws {
        let model = try await loadedModel()
        let saved = await model.setNewItemSettings(folder: "Courses", template: "Templates/Course.md")
        XCTAssertTrue(saved)
        XCTAssertEqual(model.definition?.newItemFolder, "Courses")
        XCTAssertEqual(model.definition?.newItemTemplate, "Templates/Course.md")
    }

    /// A course's rollup reads its assignments, which are not rows of the base: a saved assignment runs the base again
    /// rather than counting as a change the base cannot show.
    func testARollupRunsAgainWhenANoteItReadsIsSaved() async throws {
        let model = try await loadedModel()
        let saved = await model.addRollup(BaseRollupDraft(name: "done", relation: .linkingHere(property: "course"), property: "done",
                                                          calculation: .countChecked))
        XCTAssertTrue(saved)
        await model.followVaultChange(to: 1, change: nil)
        let doneColumn = try XCTUnwrap(model.result?.columns.firstIndex { column in column.property == .formula("done") })
        XCTAssertEqual(model.result?.rows.first?.cells[doneColumn], .value(.number(1)))

        try "---\ncourse: \"[[VLSI 3]]\"\ndone: true\n---\n".write(to: vault.appendingPathComponent("Assignments/Lab 2.md"), atomically: true, encoding: .utf8)
        let lab = try VaultPath("Assignments/Lab 2.md")
        try await index.refresh(paths: [lab], root: vault)
        await model.followVaultChange(to: 2, change: BaseContentChange(version: 2, paths: [lab]))
        XCTAssertEqual(model.result?.rows.first?.cells[doneColumn], .value(.number(2)))
    }
}
