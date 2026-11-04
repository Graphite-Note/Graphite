/**
 * File: SearchPanelsRecomputeTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The graph, Backlinks, Tags and Properties panels read the vault again only when their own
 *              inputs changed, a web address in Outgoing Links never creates a note, and the quick switcher's rows.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
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

    // MARK: Bookmarks, tags and mentions

    func testABookmarkAddedElsewhereFollowsARenameBeforeThePanelWasShown() async throws {
        let (workspace, vault) = try await indexedWorkspace(files: [
            "Old.md": "text", ".obsidian/bookmarks.json": "{\"items\":[{\"type\":\"file\",\"path\":\"Old.md\"}]}",
        ])
        XCTAssertTrue(workspace.bookmarks.allBookmarks.isEmpty, "The copy in memory has not been loaded.")

        await workspace.updateBookmarksFollowingMove(from: try VaultPath("Old.md"), to: try VaultPath("New.md"))

        let saved = try String(contentsOf: vault.appendingPathComponent(".obsidian/bookmarks.json"), encoding: .utf8)
        XCTAssertTrue(saved.contains("New.md"), saved)
        XCTAssertFalse(saved.contains("Old.md"), saved)
    }

    func testATagChosenInTheInspectorSearchesAndBringsTheSidebarForward() async throws {
        let (workspace, _) = try await indexedWorkspace(files: ["Note.md": "#topic"])
        let requestBefore = workspace.searchResultsRevealRequest

        workspace.searchForTagAndShowResults("topic")

        XCTAssertEqual(workspace.searchQuery, "tag:#topic")
        XCTAssertEqual(workspace.searchResultsRevealRequest, requestBefore + 1)
    }

    func testUnlinkedMentionsPastTheFirstTwoHundredNotesAreFoundAndASmallerListIsNotCut() async throws {
        var files = ["Zebra.md": "the target", "Zlate.md": "a zebra walks by"]
        for number in 0..<210 { files[String(format: "A%03d.md", number)] = "[[Zebra]] linked only" }
        let (workspace, _) = try await indexedWorkspace(files: files)

        let result = await workspace.unlinkedMentions(of: try VaultPath("Zebra.md"), names: ["Zebra"])

        XCTAssertEqual(result.groups.map(\.path.rawValue), ["Zlate.md"], "The 210 notes before it only link, and the search follows its pages to the note after them.")
        XCTAssertFalse(result.isCut)
    }

    func testAListLongerThanTheLimitSaysItIsCut() async throws {
        var files = ["Zebra.md": "the target"]
        for number in 0..<230 { files[String(format: "B%03d.md", number)] = "a zebra here" }
        let (workspace, _) = try await indexedWorkspace(files: files)

        let result = await workspace.unlinkedMentions(of: try VaultPath("Zebra.md"), names: ["Zebra"])

        XCTAssertEqual(result.groups.count, 200)
        XCTAssertTrue(result.isCut)
    }
}

final class SwitcherQueryTests: XCTestCase {
    func testAFolderAndANameMakeANoteInThatFolder() throws {
        let query = SwitcherQuery("Course/Week 1/New note")

        XCTAssertEqual(query.folder, try VaultPath("Course/Week 1"))
        XCTAssertEqual(query.newName, "New note")
        XCTAssertEqual(query.noteQuery, "Course/Week 1/New note")
        XCTAssertNil(query.creationProblem)
    }

    func testAPlainNameHasNoFolder() {
        let query = SwitcherQuery("  Ideas ")

        XCTAssertNil(query.folder)
        XCTAssertEqual(query.newName, "Ideas")
        XCTAssertNil(query.fragment)
    }

    func testAHashOrACaretGoesToAPlaceInTheNote() throws {
        let heading = SwitcherQuery("Lecture 3#Sampling theorem")
        XCTAssertEqual(heading.noteQuery, "Lecture 3")
        XCTAssertEqual(heading.fragment, "Sampling theorem")
        XCTAssertEqual(heading.linkTarget(to: try VaultPath("Course/Lecture 3.md")), "Course/Lecture 3.md#Sampling theorem")

        let block = SwitcherQuery("Lecture 3#^abc")
        XCTAssertEqual(block.fragment, "^abc")
        XCTAssertEqual(SwitcherQuery("Lecture 3^abc").fragment, "^abc")
        XCTAssertEqual(block.linkTarget(to: try VaultPath("Lecture 3.md")), "Lecture 3.md#^abc")
    }

    func testNoNoteIsCreatedFromAPlaceAndTheReasonIsGiven() {
        XCTAssertNotNil(SwitcherQuery("Note#Heading").creationProblem)
        XCTAssertNotNil(SwitcherQuery("Folder/bad:name").creationProblem)
        XCTAssertNil(SwitcherQuery("#only").fragment, "A field that starts with # names no note.")
    }
}

/// The quick switcher's rows for the fields of HUNT-158, run as a tap runs them, against a
/// real vault folder.
@MainActor
final class QuickSwitcherRowsTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    private func openWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "SwitcherRowsVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let workspace = WorkspaceModel(processServices: device.makeServices(), clock: LiveApplicationClock())
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        return (workspace, vault)
    }

    /// `Folder/New note` offers to create the note in that folder, and the row does, making the folder.
    func testAFolderAndANameOfferANoteInThatFolderAndTheRowMakesIt() async throws {
        let (workspace, vault) = try await openWorkspace(files: ["Other.md": ""])
        let switcher = QuickSwitcher(workspace: workspace, close: {})

        let row = switcher.creationItem(for: SwitcherQuery("Course/Week 1/New note"))

        XCTAssertEqual(row.title, "Create “New note”")
        XCTAssertEqual(row.subtitle, "New note in Course/Week 1")
        XCTAssertFalse(row.requiresExplicitChoice, "Return creates it once the vault is read")
        row.run()
        let created = vault.appendingPathComponent("Course/Week 1/New note.md")
        try await waitUntil("the note is created in the folder") { FileManager.default.fileExists(atPath: created.path) }
        try await waitUntil("the new note is opened") { workspace.selection == (try? VaultPath("Course/Week 1/New note.md")) }
    }

    /// A name a file cannot have, and a heading or block, give a row saying why no note is
    /// created instead of "No files match." alone; the row does nothing.
    func testAFieldThatNamesNoPossibleNoteSaysWhy() async throws {
        let (workspace, vault) = try await openWorkspace(files: ["Other.md": ""])
        let switcher = QuickSwitcher(workspace: workspace, close: {})
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted()

        for field in ["bad:name", "Lecture#Sampling", "Lecture#^abc"] {
            let row = switcher.creationItem(for: SwitcherQuery(field))
            XCTAssertTrue(row.title.hasPrefix("Can’t create"), "\(field): \(row.title)")
            XCTAssertFalse(row.subtitle?.isEmpty ?? true, "\(field) gives a reason")
            XCTAssertTrue(row.requiresExplicitChoice, "Return does not choose the explanation")
            row.run()
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted(), filesBefore, "Nothing is created")
    }

    /// `Note#Heading` on a found note opens it at the heading, as a link to it does.
    func testANoteAndAHeadingOpenTheNoteAtTheHeading() async throws {
        let (workspace, _) = try await openWorkspace(files: ["Course/Lecture.md": "# Lecture\n\ntext\n\n## Sampling theorem\n\nmore\n", "Other.md": ""])
        let switcher = QuickSwitcher(workspace: workspace, close: {})
        let lecture = try VaultPath("Course/Lecture.md")

        let row = switcher.fileItem(lecture, title: "Lecture", highlights: [], alias: nil, switcher: SwitcherQuery("Lecture#Sampling theorem"))
        row.run()

        try await waitUntil("the note opens") { workspace.selection == lecture }
        let tabID = try XCTUnwrap(workspace.activeTabID)
        try await waitUntil("the note is asked to show the heading") { workspace.document(for: tabID).headingScrollRequest != nil }
        XCTAssertEqual(workspace.document(for: tabID).headingScrollRequest?.anchor, NotePreviewDocument.anchor(forHeading: "Sampling theorem"))
    }
}
