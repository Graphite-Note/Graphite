/**
 * File: BaseDocumentModelRelationsTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The relation picker's reads on a vault on disk: whether a property is a relation, the notes offered,
 *              the notes linked now, and the frontmatter a choice writes.
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
final class BaseDocumentModelRelationsTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "BaseRelationsVault", files: [
            "Courses/VLSI 3.md": "---\ntype: course\n---\n",
            "Courses/Signals.md": "---\ntype: course\n---\n",
            "Courses/Archive/Old course.md": "",
            "Assignments/Lab 1.md": "---\ncourse:\n  - \"[[VLSI 3]]\"\n---\n",
            "Assignments/Lab 2.md": "---\nstatus: open\n---\n",
            "Assignments.base": "filters: file.inFolder(\"Assignments\")\nviews:\n  - type: table\n    name: All\n    order: [file.name, course]\n",
        ], for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "BaseRelationsIndex", for: self).root
        index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
        _ = try await index.reconcile(root: vault)
    }

    private var services: BaseNoteServices {
        BaseNoteServices(linkTarget: { path, _ in path.stem }, searchNotes: { query, _ in
            query.lowercased().hasPrefix("old") ? [(try? VaultPath("Courses/Archive/Old course.md")) ?? .root] : []
        }, fillTemplate: { text, _ in text }, newNoteLocation: .vaultFolder, vaultPropertyTypes: { [:] }, showNewNote: { _ in })
    }

    private func loadedModel() async throws -> BaseDocumentModel {
        let path = try VaultPath("Assignments.base")
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        return model
    }

    func testAPropertyTheVaultFillsWithLinksIsARelationAndOtherPropertiesAreNot() async throws {
        let model = try await loadedModel()
        let isCourseARelation = await model.isRelation(.note("course"), value: nil)
        let isStatusARelation = await model.isRelation(.note("status"), value: .string("open"))
        XCTAssertTrue(isCourseARelation)
        XCTAssertFalse(isStatusARelation)
    }

    func testThePickerOffersTheLinkedNotesThenTheirFolderThenWhatTheQueryFinds() async throws {
        let model = try await loadedModel()
        let row = try VaultPath("Assignments/Lab 2.md")
        let offered = await model.relationCandidates(for: .note("course"), of: row, query: "", services: services)
        XCTAssertEqual(offered.map(\.title), ["VLSI 3", "Signals"])
        XCTAssertEqual(offered.map(\.source), [.linked, .sameFolder])
        let typed = await model.relationCandidates(for: .note("course"), of: row, query: "sig", services: services)
        XCTAssertEqual(typed.map(\.title), ["Signals"])
        let found = await model.relationCandidates(for: .note("course"), of: row, query: "old", services: services)
        XCTAssertEqual(found.map(\.title), ["Old course"])
        XCTAssertEqual(found.map(\.source), [.search])
    }

    func testTheLinkedNotesAreReadAsWrittenAndAChoiceWritesAListOfLinks() async throws {
        let model = try await loadedModel()
        let row = try VaultPath("Assignments/Lab 1.md")
        let written = await model.writtenPropertyNode(.note("course"), of: row)
        let choices = await model.relationChoices(of: row, value: nil, writtenNode: written)
        XCTAssertEqual(choices.map(\.writtenItem), ["[[VLSI 3]]"])
        XCTAssertEqual(choices.first?.path?.rawValue, "Courses/VLSI 3.md")
        XCTAssertEqual(model.relationShape(.note("course"), value: .list([])), .list)

        let saved = await model.setProperty(.note("course"), of: row,
                                            to: BaseRelation.propertyValue(chosen: ["[[VLSI 3]]", "[[Signals]]"], shape: .list))
        XCTAssertTrue(saved)
        let text = try String(contentsOf: vault.appendingPathComponent("Assignments/Lab 1.md"), encoding: .utf8)
        XCTAssertEqual(text, "---\ncourse:\n  - \"[[VLSI 3]]\"\n  - \"[[Signals]]\"\n---\n")
    }
}
