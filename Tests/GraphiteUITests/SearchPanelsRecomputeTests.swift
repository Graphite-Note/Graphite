/**
 * File: SearchPanelsRecomputeTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The graph, Backlinks, Tags and Properties panels read the vault again only when their own
 *              inputs changed, and a web address in Outgoing Links never creates a note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteIndex
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

@MainActor
final class SearchPanelsRecomputeTests: XCTestCase {
    private var temporaryFolders: [URL] = []
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
    }

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = try TemporaryVault.make(prefix: prefix, for: self).root
        temporaryFolders.append(folder)
        return folder.resolvingSymlinksInPath()
    }

    private func indexedWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try makeFolder("SearchPanelsVault")
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let indexFolder = try makeFolder("SearchPanelsIndex")
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = device.makeWorkspace()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.index = index
        workspace.vaultSettings = try await store.settings()
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    /// Saves `text` to the note as Graphite's autosave does, and waits for the index to take it in.
    private func save(_ text: String, to relativePath: String, in vault: URL, workspace: WorkspaceModel) async throws {
        let versionBefore = workspace.indexVersion
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
        await workspace.refreshIndexAndRecordChange(for: [try VaultPath(relativePath)])
        XCTAssertGreaterThan(workspace.indexVersion, versionBefore, "The index took in the save.")
    }

    // MARK: Autosave

    func testTenAutosavesOfTypedTextRebuildNoGraphAndReloadNoTagList() async throws {
        let (workspace, vault) = try await indexedWorkspace(files: ["Note.md": "[[Other]] #topic", "Other.md": "x"])
        let graph = await workspace.vaultGraph()
        XCTAssertEqual(graph?.nodes.count, 3, "Two notes and the tag.")
        let structureVersionBefore = workspace.structureVersion
        let indexVersionBefore = workspace.indexVersion

        for count in 1...10 { try await save("[[Other]] #topic " + String(repeating: "word ", count: count), to: "Note.md", in: vault, workspace: workspace) }

        XCTAssertEqual(workspace.indexVersion - indexVersionBefore, 10, "Panels that show text still hear each save.")
        XCTAssertEqual(workspace.structureVersion, structureVersionBefore, "Before: 10 rebuilds of the graph and 10 reads of every tag and property. Now none.")
        XCTAssertEqual(workspace.graphCache?.structureVersion, structureVersionBefore, "The graph built before the saves is the one kept.")
        let backlinksVersion = workspace.indexChangeLog.newestVersionAffectingBacklinks(of: try VaultPath("Note.md"))
        XCTAssertEqual(backlinksVersion, 0, "Before: 10 reads of up to 200 notes for the open note's backlinks. Now none.")
    }

    func testAddingALinkOrATagReachesTheGraphAndTheLists() async throws {
        let (workspace, vault) = try await indexedWorkspace(files: ["Note.md": "[[Other]]", "Other.md": "x"])
        let structureVersionBefore = workspace.structureVersion

        try await save("[[Other]] [[Third]]", to: "Note.md", in: vault, workspace: workspace)
        XCTAssertGreaterThan(workspace.structureVersion, structureVersionBefore)

        let afterLink = workspace.structureVersion
        try await save("[[Other]] [[Third]] #new", to: "Note.md", in: vault, workspace: workspace)
        XCTAssertGreaterThan(workspace.structureVersion, afterLink)
        let graph = await workspace.vaultGraph()
        XCTAssertTrue(graph?.nodes.contains { node in node.id == "#new" } == true, "The new tag is in the rebuilt graph.")
    }

    func testAnotherNotesSaveReachesBacklinksButTheOpenNotesOwnTypingDoesNot() async throws {
        let (workspace, vault) = try await indexedWorkspace(files: ["Open.md": "text", "Linker.md": "nothing yet"])
        let open = try VaultPath("Open.md")

        try await save("text typed", to: "Open.md", in: vault, workspace: workspace)
        XCTAssertEqual(workspace.indexChangeLog.newestVersionAffectingBacklinks(of: open), 0)

        try await save("now [[Open]]", to: "Linker.md", in: vault, workspace: workspace)
        XCTAssertEqual(workspace.indexChangeLog.newestVersionAffectingBacklinks(of: open), workspace.indexVersion)
    }

    // MARK: The change log

    func testBacklinksCountAnUnknownChangeAndANameChange() throws {
        let note = try VaultPath("Note.md")
        var log = IndexChangeLog()
        log.record(IndexChange(version: 1, paths: [note], changedStructure: true, changedNames: false))
        XCTAssertEqual(log.newestVersionAffectingBacklinks(of: note), 0)
        log.record(IndexChange(version: 2, paths: [note], changedStructure: false, changedNames: true))
        XCTAssertEqual(log.newestVersionAffectingBacklinks(of: note), 2)
        log.record(IndexChange(version: 3, paths: nil, changedStructure: true, changedNames: true))
        XCTAssertEqual(log.newestVersionAffectingBacklinks(of: note), 3, "A scan or a move may have changed anything.")
    }

    func testTheLogKeepsOnlyTheLatestChanges() {
        var log = IndexChangeLog()
        for version in 1...(IndexChangeLog.capacity + 10) {
            log.record(IndexChange(version: version, paths: nil, changedStructure: true, changedNames: true))
        }
        XCTAssertEqual(log.changes.count, IndexChangeLog.capacity)
        XCTAssertEqual(log.changes.first?.version, 11)
    }

    // MARK: Web addresses in Outgoing Links

    func testAWebAddressInOutgoingLinksOpensInTheBrowserAndAFileLinkDoesNot() throws {
        let semantics = try MarkdownSemantics.parse("[site](https://example.com/a/b#top) [[Other]] [md](Folder/Note.md) [mail](mailto:a@b.c)\n")
        let links = NoteLinksInspector.outgoingLinks(in: semantics.links)

        let locations = links.compactMap { link in link.externalLocation?.absoluteString }.sorted()

        XCTAssertEqual(locations, ["https://example.com/a/b#top", "mailto:a@b.c"])
    }

    func testFollowingAWebAddressCreatesNoFoldersAndNoNote() async throws {
        let (workspace, vault) = try await indexedWorkspace(files: ["Source.md": "[site](https://example.com/a/b)"])
        let before = try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted()

        await workspace.follow("https://example.com/a/b", from: try VaultPath("Source.md"), isWiki: false)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted(), before, "No folder named https: or example.com.")
        XCTAssertNotNil(workspace.errorMessage)
    }
}
