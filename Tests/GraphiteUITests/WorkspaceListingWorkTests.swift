/**
 * File: WorkspaceListingWorkTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: What a change in the vault costs the workspace, counted in listings done and versions moved.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 04/11/2026
 */

import XCTest
import Observation
import PDFKit
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// What a change costs, in listings done and versions moved. The owner's vault has 24,712 files
/// at its root, where one listing is one metadata read each and about 360,000 comparisons.
@MainActor
final class WorkspaceListingWorkTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
        try await super.tearDown()
    }

    private func opened(files: [String: String], clock: (any ApplicationClock)? = nil) async throws -> (workspace: WorkspaceModel, vault: URL, store: VaultStore) {
        let vault = try testBed.makeVault(files: files)
        let device = try testBed.isolatedDevice()
        let workspace = clock.map { clock in device.makeWorkspace(clock: clock) } ?? device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        return (workspace, vault, try XCTUnwrap(workspace.store))
    }

    // MARK: HUNT-026

    func testTheRestoredNoteIsShownBeforeTheRootIsListed() async throws {
        let vault = try testBed.makeVault(files: ["Note.md": "text", "Other.md": "text"])
        let device = try testBed.isolatedDevice()
        let firstLaunch = device.makeWorkspace()
        try await firstLaunch.openFolderAsVault(vault)
        await firstLaunch.open(try VaultPath("Note.md"))
        firstLaunch.saveTabLayout()
        let vaultToReopen = try XCTUnwrap(firstLaunch.vaultLibrary.list.mostRecentlyOpened)
        firstLaunch.windowDidClose()

        let workspace = device.makeWorkspace()
        @MainActor final class FirstListing { var tabPathWhenItArrived: VaultPath?; var storeWasSet = false }
        let firstListing = FirstListing()
        // Stands by until the root's entries are about to be set for the first time with
        // anything in them; the switch to the vault sets them to nothing first.
        func watchForFirstListing() {
            withObservationTracking { _ = workspace.hasListedRoot } onChange: {
                MainActor.assumeIsolated {
                    guard !workspace.hasListedRoot else { return }
                    firstListing.tabPathWhenItArrived = workspace.layout.activeTab.path
                    firstListing.storeWasSet = workspace.store != nil
                }
            }
        }
        watchForFirstListing()
        await workspace.openVaultOfWindow(vaultToReopen.id, tabs: .vaultsLast, showing: nil)

        XCTAssertTrue(firstListing.storeWasSet)
        XCTAssertEqual(firstListing.tabPathWhenItArrived, try VaultPath("Note.md"), "The note's tab is back before the root's listing arrives.")
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["Note.md", "Other.md"])
        XCTAssertEqual(try XCTUnwrap(workspace.store).directoryListingCount, 1, "The root is listed once when a vault opens.")
        XCTAssertTrue(workspace.hasListedRoot)
    }

    func testAVaultThatCannotBeReadIsRefusedAndTheOpenOneStays() async throws {
        let (workspace, _, store) = try await opened(files: ["Note.md": "text"])
        let missingFolder = try TemporaryVault.make(prefix: "MissingParent", for: self).root.appendingPathComponent("Missing")
        do {
            try await workspace.openFolderAsVault(missingFolder)
            XCTFail("A folder that is not there does not open")
        } catch {}
        XCTAssertTrue(workspace.store === store)
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["Note.md"])
    }

    // MARK: HUNT-027

    func testAChangeToAHiddenFileListsNothing() async throws {
        let (workspace, vault, store) = try await opened(files: ["Note.md": "text", ".obsidian/workspace.json": "{}", "Folder/Inside.md": "text"])
        workspace.expandedFolders.insert(try VaultPath("Folder"))
        let listingsBefore = store.directoryListingCount, directoryVersionBefore = workspace.directoryVersion, drawingVersionBefore = workspace.drawingVersion
        let refresh = ExternalChangeRefresh(changedLocations: [vault.appendingPathComponent(".obsidian/workspace.json")], root: vault, maximumFileCount: 200)
        XCTAssertEqual(refresh, .nothingShown)

        await workspace.applyExternalChanges(refresh)

        XCTAssertEqual(store.directoryListingCount, listingsBefore)
        XCTAssertEqual(workspace.directoryVersion, directoryVersionBefore)
        XCTAssertEqual(workspace.drawingVersion, drawingVersionBefore)
        XCTAssertTrue(workspace.folderListingVersions.isEmpty)
    }

    func testAChangedFileInTheRootIsPlacedInItsListingWithoutListing() async throws {
        let (workspace, vault, store) = try await opened(files: ["B.md": "text", "D.md": "text", "Folder/Inside.md": "text"])
        let listingsBefore = store.directoryListingCount, directoryVersionBefore = workspace.directoryVersion
        try Data("new".utf8).write(to: vault.appendingPathComponent("C.md"))
        try FileManager.default.removeItem(at: vault.appendingPathComponent("D.md"))
        try Data("longer text".utf8).write(to: vault.appendingPathComponent("B.md"))
        let changes = ["C.md", "D.md", "B.md"].map { name in vault.appendingPathComponent(name) }

        await workspace.applyExternalChanges(ExternalChangeRefresh(changedLocations: Set(changes), root: vault, maximumFileCount: 200))

        XCTAssertEqual(store.directoryListingCount, listingsBefore, "No file of the root's 24,712 is read but those that changed.")
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["Folder", "B.md", "C.md"])
        XCTAssertEqual(workspace.rootEntries.first { entry in entry.path.name == "B.md" }?.size, 11)
        XCTAssertEqual(workspace.directoryVersion, directoryVersionBefore, "Expanded folders are not told to list themselves.")
        XCTAssertEqual(workspace.folderListingVersions, [.root: 1])
    }

    func testAChangeInAFolderNamesThatFolderAndNoOther() async throws {
        let (workspace, vault, store) = try await opened(files: ["Top.md": "text", "Folder/Inside.md": "text", "Other/Elsewhere.md": "text"])
        let listingsBefore = store.directoryListingCount, directoryVersionBefore = workspace.directoryVersion
        let entriesBefore = workspace.rootEntries
        try Data("changed".utf8).write(to: vault.appendingPathComponent("Folder/Inside.md"))

        await workspace.applyExternalChanges(ExternalChangeRefresh(changedLocations: [vault.appendingPathComponent("Folder/Inside.md")], root: vault, maximumFileCount: 200))

        XCTAssertEqual(store.directoryListingCount, listingsBefore)
        XCTAssertEqual(workspace.folderListingVersions, [try VaultPath("Folder"): 1])
        XCTAssertEqual(workspace.directoryVersion, directoryVersionBefore)
        XCTAssertEqual(workspace.rootEntries.map(\.path), entriesBefore.map(\.path))
    }

    func testAFolderReportedIsListedAndScannedOnItsOwn() async throws {
        let (workspace, vault, store) = try await opened(files: ["Top.md": "text", "Synced/Old.md": "text", "Other/Elsewhere.md": "text"])
        let index = try XCTUnwrap(workspace.index)
        let listingsBefore = store.directoryListingCount
        try Data("new needle".utf8).write(to: vault.appendingPathComponent("Synced/New.md"))
        // Outside the folder, so the folder's scan does not see it.
        try Data("unrelated needle".utf8).write(to: vault.appendingPathComponent("Other/Unreported.md"))

        await workspace.applyExternalChanges(ExternalChangeRefresh(changedLocations: [vault.appendingPathComponent("Synced")], root: vault, maximumFileCount: 200))

        try await waitUntil {
            let found = (try? await index.search("needle").results.map(\.path.rawValue)) ?? []
            return found == ["Synced/New.md"]
        }
        XCTAssertEqual(store.directoryListingCount, listingsBefore)
        XCTAssertEqual(workspace.folderListingVersions[try VaultPath("Synced")], 1)
        XCTAssertEqual(workspace.folderListingVersions[.root], 1, "Its entry in the folder above may be new.")
    }

    private func reportOnlyTheVaultFolder(_ workspace: WorkspaceModel, vault: URL) async {
        await workspace.applyExternalChanges(ExternalChangeRefresh(changedLocations: [vault], root: vault, maximumFileCount: 200))
    }

    func testTheVaultFolderReportedAloneListsAndRedrawsNothingWhileNothingChanged() async throws {
        let (workspace, vault, store) = try await opened(files: ["Top.md": "text", "Folder/Inside.md": "text"])
        let listingsBefore = store.directoryListingCount, drawingVersionBefore = workspace.drawingVersion

        for _ in 0..<3 { await reportOnlyTheVaultFolder(workspace, vault: vault) }
        // Follows the scans those reports asked for.
        workspace.startIndexing()
        try await waitUntil { !workspace.isIndexing }

        XCTAssertEqual(store.directoryListingCount, listingsBefore, "Was three listings: with 30,000 files at the root, 90,000 metadata reads.")
        XCTAssertEqual(workspace.drawingVersion, drawingVersionBefore, "Was three rebuilds of the open documents.")
    }

    func testAFileEditedAtTheRootWithOnlyTheVaultFolderReportedShowsWhenTheScanFindsIt() async throws {
        let (workspace, vault, store) = try await opened(files: ["Top.md": "text"])
        let listingsBefore = store.directoryListingCount, drawingVersionBefore = workspace.drawingVersion
        // Written in place: the root's date does not move.
        try Data("longer text".utf8).write(to: vault.appendingPathComponent("Top.md"))

        await reportOnlyTheVaultFolder(workspace, vault: vault)

        try await waitUntil { workspace.rootEntries.first?.size == 11 }
        XCTAssertEqual(store.directoryListingCount, listingsBefore + 1)
        try await waitUntil { workspace.drawingVersion == drawingVersionBefore + 1 }
    }

    func testANameAddedAtTheRootWithOnlyTheVaultFolderReportedShowsAtOnce() async throws {
        let (workspace, vault, store) = try await opened(files: ["Top.md": "text"])
        let listingsBefore = store.directoryListingCount
        try Data("new".utf8).write(to: vault.appendingPathComponent("New.md"))
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: vault.path)

        await reportOnlyTheVaultFolder(workspace, vault: vault)

        XCTAssertEqual(store.directoryListingCount, listingsBefore + 1)
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["New.md", "Top.md"])
    }

    // MARK: HUNT-028

    func testANewNoteOpensAndIsShownWithoutListing() async throws {
        let (workspace, _, store) = try await opened(files: ["Top.md": "text"])
        let listingsBefore = store.directoryListingCount

        await workspace.createNote(named: "New")

        XCTAssertEqual(workspace.selection, try VaultPath("New.md"))
        XCTAssertEqual(store.directoryListingCount, listingsBefore, "The root is not listed to show one new file.")
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["New.md", "Top.md"])
    }

    func testANewNoteInANewFolderShowsTheFolderAtTheRoot() async throws {
        let (workspace, _, store) = try await opened(files: ["Top.md": "text"])
        let listingsBefore = store.directoryListingCount

        await workspace.createNote(named: "Inside", in: try VaultPath("Made/Deep"))

        XCTAssertEqual(store.directoryListingCount, listingsBefore)
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["Made", "Top.md"])
        XCTAssertEqual(workspace.folderListingVersions[try VaultPath("Made/Deep")], 1)
        XCTAssertEqual(workspace.folderListingVersions[try VaultPath("Made")], 1)
    }

    // MARK: HUNT-039

    func testAScanThatFindsNothingChangedRedrawsNothing() async throws {
        let (workspace, _, _) = try await opened(files: ["Top.md": "text"])
        let versionBefore = workspace.indexVersion

        workspace.startIndexing()
        try await waitUntil { !workspace.isIndexing }

        XCTAssertEqual(workspace.indexVersion, versionBefore)
    }

    func testAScanThatFindsAChangeRedrawsWhatDependsOnTheIndex() async throws {
        let (workspace, vault, _) = try await opened(files: ["Top.md": "text"])
        let versionBefore = workspace.indexVersion
        try Data("new".utf8).write(to: vault.appendingPathComponent("New.md"))

        workspace.startIndexing()
        try await waitUntil { !workspace.isIndexing && workspace.indexVersion > versionBefore }
    }

    // MARK: HUNT-040

    func testANoteNotShownSyncingLeavesOpenDocumentsAlone() async throws {
        let (workspace, vault, _) = try await opened(files: ["Open.md": "plain text", "Elsewhere.md": "text"])
        await workspace.open(try VaultPath("Open.md"))
        let versionBefore = workspace.drawingVersion
        try Data("changed".utf8).write(to: vault.appendingPathComponent("Elsewhere.md"))

        await workspace.applyExternalChanges(ExternalChangeRefresh(changedLocations: [vault.appendingPathComponent("Elsewhere.md")], root: vault, maximumFileCount: 200))

        XCTAssertEqual(workspace.drawingVersion, versionBefore)
    }

    func testANotePictureOrPDFThatCanShowRebuildsOpenDocuments() async throws {
        let files = ["Open.md": "![[Embedded]]", "Embedded.md": "text", "Picture.png": "not really a picture", "Top.md": "![[Middle]]", "Middle.md": "![[Bottom]]", "Bottom.md": "text"]
        let (workspace, vault, _) = try await opened(files: files)
        await workspace.open(try VaultPath("Open.md"))
        var version = workspace.drawingVersion
        func report(_ name: String) async {
            await workspace.applyExternalChanges(ExternalChangeRefresh(changedLocations: [vault.appendingPathComponent(name)], root: vault, maximumFileCount: 200))
        }

        await report("Embedded.md")
        XCTAssertEqual(workspace.drawingVersion, version + 1, "An embedded note shows in the open note.")
        version = workspace.drawingVersion

        await report("Picture.png")
        XCTAssertEqual(workspace.drawingVersion, version + 1, "Pictures may show in any open note.")
        version = workspace.drawingVersion

        await report("Bottom.md")
        XCTAssertEqual(workspace.drawingVersion, version, "Not embedded by the open note.")

        await workspace.open(try VaultPath("Top.md"))
        await report("Bottom.md")
        XCTAssertEqual(workspace.drawingVersion, version + 1, "Embedded through another note, which the index knows.")
    }

    // MARK: HUNT-041

    func testComingBackListsNothingWhenNothingMoved() async throws {
        let clock = ManualClock()
        let (workspace, vault, store) = try await opened(files: ["Top.md": "text", ".obsidian/app.json": "{}"], clock: clock)
        let listingsBefore = store.directoryListingCount, directoryVersionBefore = workspace.directoryVersion

        workspace.noteLeftFront()
        clock.advance(by: .seconds(30))
        await workspace.refreshAfterComingToFront()

        XCTAssertEqual(store.directoryListingCount, listingsBefore)
        XCTAssertEqual(workspace.directoryVersion, directoryVersionBefore)

        // A name added at the root moves the folder's date.
        try Data("new".utf8).write(to: vault.appendingPathComponent("New.md"))
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: vault.path)
        workspace.noteLeftFront()
        clock.advance(by: .seconds(30))
        await workspace.refreshAfterComingToFront()
        XCTAssertEqual(store.directoryListingCount, listingsBefore + 1)
        XCTAssertEqual(workspace.rootEntries.map(\.path.rawValue), ["New.md", "Top.md"])
    }

    func testBeingAwayLongListsAgainWhateverTheFoldersDateSays() async throws {
        let clock = ManualClock()
        let (workspace, _, store) = try await opened(files: ["Top.md": "text"], clock: clock)
        let listingsBefore = store.directoryListingCount

        workspace.noteLeftFront()
        clock.advance(by: WorkspaceModel.awayTimeBeforeListingAgain)
        await workspace.refreshAfterComingToFront()

        XCTAssertEqual(store.directoryListingCount, listingsBefore + 1)
    }

    func testComingBackReadsSettingsAgainOnlyWhenAFileMoved() async throws {
        let (workspace, vault, _) = try await opened(files: ["Top.md": "text", ".obsidian/app.json": "{}"])
        XCTAssertEqual(workspace.vaultSettings.fileSortOrder, .alphabetical)
        let revisionBefore = workspace.settingsFilesRevisionAtLastReading
        await workspace.refreshAfterComingToFront()
        XCTAssertEqual(workspace.settingsFilesRevisionAtLastReading, revisionBefore)

        try Data("{\"fileSortOrder\":\"byModifiedTime\"}".utf8).write(to: vault.appendingPathComponent(".obsidian/app.json"))
        await workspace.refreshAfterComingToFront()
        XCTAssertEqual(workspace.vaultSettings.fileSortOrder, .byModifiedTime)
    }

    // MARK: HUNT-043

    func testAnIndexFinishedOnAnEarlierLaunchCountsWhileTheNextScanRuns() async throws {
        let vault = try testBed.makeVault(files: ["Top.md": "text"])
        let device = try testBed.isolatedDevice()
        let firstLaunch = device.makeWorkspace()
        try await firstLaunch.openFolderAsVault(vault)
        XCTAssertFalse(firstLaunch.indexFinishedAnEarlierScan, "A first build says it is one.")
        try await waitUntil { firstLaunch.hasCompletedIndexScan && !firstLaunch.isIndexing }
        firstLaunch.windowDidClose()
        let vaultToReopen = try XCTUnwrap(firstLaunch.vaultLibrary.list.mostRecentlyOpened)
        // The registry closes the index when its last lease ends.
        let secondLaunch = device.makeWorkspace()
        await secondLaunch.openVaultOfWindow(vaultToReopen.id, tabs: .vaultsLast, showing: nil)
        XCTAssertTrue(secondLaunch.indexFinishedAnEarlierScan)
        XCTAssertTrue(secondLaunch.isIndexUsable)
    }

    // MARK: HUNT-038

    func testAFolderListedAgainAsksAboutOnlyItsNewFiles() async throws {
        let (workspace, _, _) = try await opened(files: ["Top.md": "text"])
        try await waitUntil { workspace.conflictCheckTask == nil && workspace.pendingConflictChecks.isEmpty }
        let conflictStore = try FakeConflictVersionStore()
        workspace.conflictVersionStore = conflictStore
        let listed = try ["A.md", "B.md"].map { name in try VaultPath("Folder/" + name) }

        workspace.checkConflictVersions(ofListedFiles: listed)
        try await waitUntil { workspace.conflictCheckTask == nil && workspace.pendingConflictChecks.isEmpty }
        XCTAssertEqual(conflictStore.pathsAskedAbout.count, 2)

        workspace.checkConflictVersions(ofListedFiles: listed + [try VaultPath("Folder/C.md")])
        try await waitUntil { workspace.conflictCheckTask == nil && workspace.pendingConflictChecks.isEmpty }
        XCTAssertEqual(conflictStore.pathsAskedAbout.count, 3)

        // A version gained or lost is reported as a change to the file, which asks again.
        workspace.checkConflictVersions(of: [listed[0]])
        try await waitUntil { workspace.conflictCheckTask == nil && workspace.pendingConflictChecks.isEmpty }
        XCTAssertEqual(conflictStore.pathsAskedAbout.count, 4)
    }

    func testAListingBeyondTheLimitKeepsItsFirstFilesAndARowOnScreenIsAskedAboutFirst() async throws {
        let (workspace, _, _) = try await opened(files: ["Top.md": "text"])
        try await waitUntil { workspace.conflictCheckTask == nil && workspace.pendingConflictChecks.isEmpty }
        workspace.conflictCheckTask = Task {} // Holds the queue still for this test.
        let manyPaths = try (0..<(WorkspaceModel.maximumPendingConflictChecks + 100)).map { number in try VaultPath("Note \(number).md") }

        workspace.checkConflictVersions(ofListedFiles: manyPaths)

        XCTAssertEqual(workspace.pendingConflictChecks.count, WorkspaceModel.maximumPendingConflictChecks)
        XCTAssertEqual(workspace.pendingConflictChecks.first, manyPaths[0], "The first rows of a list are kept; the last 5,000 used to be.")
        let lastPath = try XCTUnwrap(manyPaths.last)
        XCTAssertFalse(workspace.pendingConflictChecks.contains(lastPath))

        workspace.checkConflictVersionsOfRowShown(lastPath)
        XCTAssertEqual(workspace.pendingConflictChecks.first, lastPath)
        workspace.resetConflictVersions()
    }
}

/// HUNT-030: the file list's rows are kept up to date row by row.
@MainActor
final class FlattenedFileTreeTests: XCTestCase {
    private func entry(_ path: String, isDirectory: Bool = false) throws -> VaultEntry {
        VaultEntry(path: try VaultPath(path), isDirectory: isDirectory, size: 0, modified: .distantPast)
    }

    private func root(fileCount: Int) throws -> [VaultEntry] {
        try [entry("Folder", isDirectory: true), entry("Empty", isDirectory: true)] + (0..<fileCount).map { number in try entry("Note \(number).md") }
    }

    func testOpeningAndClosingAFolderBuildsOnlyItsOwnRows() throws {
        var tree = FlattenedFileTree()
        tree.setRootEntries(try root(fileCount: 24_712))
        let builtForTheRoot = tree.rowsBuiltCount
        XCTAssertEqual(builtForTheRoot, 24_714)
        let folder = try VaultPath("Folder")

        tree.setExpandedFolders([folder])
        XCTAssertEqual(tree.rowsBuiltCount, builtForTheRoot, "A folder not listed yet changes no row.")
        tree.setChildren(try [entry("Folder/A.md"), entry("Folder/B.md")], of: folder)
        XCTAssertEqual(tree.rowsBuiltCount, builtForTheRoot + 2, "Tapping a folder used to rebuild all 24,714 rows, twice.")
        XCTAssertEqual(tree.rows.prefix(4).map(\.id), ["Folder", "Folder/A.md", "Folder/B.md", "Empty"])
        XCTAssertEqual(tree.rows[1].depth, 1)

        tree.setChildren(try [entry("Folder/A.md"), entry("Folder/B.md")], of: folder)
        XCTAssertEqual(tree.rowsBuiltCount, builtForTheRoot + 2, "An unchanged listing touches nothing.")

        tree.setExpandedFolders([])
        XCTAssertEqual(tree.rowsBuiltCount, builtForTheRoot + 2)
        XCTAssertEqual(tree.rows.count, 24_714)
        XCTAssertEqual(tree.rows.prefix(2).map(\.id), ["Folder", "Empty"])

        tree.setExpandedFolders([folder])
        XCTAssertEqual(tree.rows.prefix(3).map(\.id), ["Folder", "Folder/A.md", "Folder/B.md"], "A folder opened again draws at once.")
    }

    /// The vault as generated names: 300 folders and 29,700 files at the root, with one folder
    /// of 500 files opened and closed.
    func testATapInAVaultOf30000FilesBuildsTheRowsOfTheFolderTapped() throws {
        var entries = try (0..<300).map { number in try entry("Folder \(number)", isDirectory: true) }
        for number in 0..<29_700 { entries.append(try entry("Note \(number).md")) }
        let folder = try VaultPath("Folder 7")
        let children = try (0..<500).map { number in try entry("Folder 7/Inside \(number).md") }
        var tree = FlattenedFileTree()
        tree.setRootEntries(entries)
        // What each tap and each listing arriving cost when the rows were built in the body.
        let wholeTreeRows = tree.rowsBuiltCount
        XCTAssertEqual(wholeTreeRows, 30_000)

        tree.setExpandedFolders([folder])
        XCTAssertEqual(tree.rowsBuiltCount - wholeTreeRows, 0, "Tapping a folder not listed yet: was 30,000.")
        tree.setChildren(children, of: folder)
        XCTAssertEqual(tree.rowsBuiltCount - wholeTreeRows, 500, "Its listing arriving: was 30,500.")
        tree.setChildren(children, of: folder)
        XCTAssertEqual(tree.rowsBuiltCount - wholeTreeRows, 500, "Listed again, the same: was 30,500.")
        tree.setExpandedFolders([])
        XCTAssertEqual(tree.rowsBuiltCount - wholeTreeRows, 500, "Folded: was 30,000.")
        XCTAssertEqual(tree.rows.count, 30_000)
        tree.setExpandedFolders([folder])
        XCTAssertEqual(tree.rowsBuiltCount - wholeTreeRows, 1_000, "Opened again: its own rows, was 30,500.")
        XCTAssertEqual(tree.rows.count, 30_500)
        XCTAssertEqual(tree.rows[8].id, "Folder 7/Inside 0.md")
    }

    func testFoldersInsideFoldersKeepTheirPlaces() throws {
        var tree = FlattenedFileTree()
        let outer = try VaultPath("Outer"), inner = try VaultPath("Outer/Inner")
        tree.setRootEntries(try [entry("Outer", isDirectory: true), entry("Top.md")])
        tree.setChildren(try [entry("Outer/Inner", isDirectory: true), entry("Outer/File.md")], of: outer)
        tree.setChildren(try [entry("Outer/Inner/Deep.md")], of: inner)

        tree.setExpandedFolders([outer, inner])
        XCTAssertEqual(tree.rows.map(\.id), ["Outer", "Outer/Inner", "Outer/Inner/Deep.md", "Outer/File.md", "Top.md"])
        XCTAssertEqual(tree.rows.map(\.depth), [0, 1, 2, 1, 0])

        tree.setExpandedFolders([inner])
        XCTAssertEqual(tree.rows.map(\.id), ["Outer", "Top.md"], "A folded folder hides what is open inside it.")

        tree.setExpandedFolders([outer, inner])
        tree.setChildren(try [entry("Outer/Inner/Deep.md"), entry("Outer/Inner/Deeper.md")], of: inner)
        XCTAssertEqual(tree.rows.map(\.id), ["Outer", "Outer/Inner", "Outer/Inner/Deep.md", "Outer/Inner/Deeper.md", "Outer/File.md", "Top.md"])

        tree.setRootEntries(try [entry("Before.md"), entry("Outer", isDirectory: true), entry("Top.md")])
        XCTAssertEqual(tree.rows.first?.id, "Before.md")
        XCTAssertEqual(tree.rows.count, 7)
    }

    func testTheContentsChangeTheirRowsOnlyWhenARowChanges() async throws {
        let contents = FileTreeContents()
        let rootEntries = try root(fileCount: 3)
        contents.apply(rootEntries: rootEntries, expandedFolders: [])
        @MainActor final class RowChanges { var count = 0 }
        let rowChanges = RowChanges()
        withObservationTracking { _ = contents.rows } onChange: { MainActor.assumeIsolated { rowChanges.count += 1 } }

        contents.apply(rootEntries: rootEntries, expandedFolders: [try VaultPath("Folder")])
        XCTAssertEqual(rowChanges.count, 0, "Tapping a folder not listed yet redraws nothing.")
        contents.setChildren([], of: try VaultPath("Folder"))
        XCTAssertEqual(rowChanges.count, 0, "An empty folder's listing redraws nothing.")

        contents.setChildren(try [entry("Folder/A.md")], of: try VaultPath("Folder"))
        XCTAssertEqual(rowChanges.count, 1)
        XCTAssertEqual(contents.rows.count, rootEntries.count + 1)
    }

    func testTheContentsFollowTheWorkspace() async throws {
        let workspace = WorkspaceModel()
        let contents = FileTreeContents()
        let following = Task { await contents.follow(rootEntries: { workspace.rootEntries }, expandedFolders: { workspace.expandedFolders }) }
        defer { following.cancel() }
        workspace.rootEntries = try [entry("Folder", isDirectory: true), entry("Top.md")]
        try await waitUntil { contents.rows.count == 2 }
        contents.setChildren(try [entry("Folder/A.md")], of: try VaultPath("Folder"))
        XCTAssertEqual(contents.rows.count, 2)
        workspace.expandedFolders.insert(try VaultPath("Folder"))
        try await waitUntil { contents.rows.count == 3 }
    }
}

/// HUNT-035: bases off screen are bounded by what they hold, and go on a memory warning.
@MainActor
final class EmbeddedBaseModelCacheBudgetTests: XCTestCase {
    private func makeModel(vault: URL) throws -> BaseDocumentModel {
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        return BaseDocumentModel(source: .inline("views:\n  - type: table\n    name: Table\n"), contextPath: try VaultPath("Note.md"), store: VaultStore(root: vault), index: index)
    }

    func testAMemoryWarningEmptiesTheCache() throws {
        let vault = try TemporaryVault.make(prefix: "BaseCacheVault", for: self).root
        let cache = EmbeddedBaseModelCache()
        let identity = EmbeddedBaseView.EmbedIdentity(source: .inline("views: []"), embeddingNote: try VaultPath("Note.md"), viewName: nil)
        _ = cache.model(for: identity) { (try? makeModel(vault: vault))! }
        XCTAssertEqual(cache.modelCount, 1)

        cache.removeAllModels()

        XCTAssertEqual(cache.modelCount, 0)
    }

    func testABaseOffScreenLetsGoOfItsLoadedRecords() async throws {
        let vault = try TemporaryVault.make(prefix: "BaseCacheVault", files: ["One.md": "text", "Two.md": "text"], for: self).root
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let model = BaseDocumentModel(source: .inline("views:\n  - type: table\n    name: Table\n"), contextPath: try VaultPath("Note.md"), store: VaultStore(root: vault), index: index)
        await model.reload()
        let heldWithRecords = model.estimatedHeldBytes
        XCTAssertGreaterThan(heldWithRecords, 0)

        model.releaseLoadedRecords()
        XCTAssertLessThan(model.estimatedHeldBytes, heldWithRecords)
        let resultRows = model.result?.groups.flatMap(\.rows).count
        XCTAssertEqual(resultRows, 2, "Its result stays, so it shows at once when it comes back.")

        await model.reload()
        XCTAssertLessThan(model.estimatedHeldBytes, heldWithRecords, "A run while off screen keeps no records.")
        model.startKeepingLoadedRecords()
        await model.reload()
        XCTAssertEqual(model.estimatedHeldBytes, heldWithRecords)
    }
}

/// HUNT-044: a note's links are looked up together.
final class ReadingViewLinkLookupTests: XCTestCase {
    func testALongNoteWithAThemeReadsTheIndexOnceForItsLinks() async throws {
        let vault = try TemporaryVault.make(prefix: "ReadingLinksVault", files: ["Folder/Target.md": "text"], for: self).root
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let source = (0..<150).map { number in "Paragraph with [[Target]] and [[Missing \(number % 40)]].\n" }.joined(separator: "\n")
        var configuration = ReadingConfiguration()
        configuration.marksUnresolvedLinks = true
        let builder = ReadingViewBuilder()

        let build = try await builder.build(source: source, note: try VaultPath("Note.md"), root: vault, index: index, configuration: configuration)
        XCTAssertFalse(build.blocks.isEmpty)

        let reads = await builder.indexReadCount
        XCTAssertEqual(reads, 1, "One read for 41 distinct links written 300 times.")
    }
}

/// HUNT-046: the list of a long PDF's pages asks PDFKit only for the rows it shows.
@MainActor
final class PDFThumbnailListWorkTests: XCTestCase {
    private final class CountingPDFDocument: PDFDocument {
        var pageRequests = 0
        override func page(at index: Int) -> PDFPage? {
            pageRequests += 1
            return super.page(at: index)
        }
    }

    func testTheRowsOfAListAreKnownWithoutAskingForAnyPage() {
        let document = CountingPDFDocument()
        for pageIndex in 0..<20 { document.insert(PDFPage(), at: pageIndex) }
        document.pageRequests = 0

        let rows = PDFThumbnailListPage.rowIndices(of: document)

        XCTAssertEqual(rows, 0..<20)
        XCTAssertEqual(document.pageRequests, 0, "The list asked for every page each time its body ran.")
    }

    #if os(macOS)
    @MainActor @Observable final class ListState {
        var scrollTarget: Int?
        var pageListVersion = 0
        var indicesShown: Set<Int> = []
        var pagesShownAtFirstRow: [PDFPage] = []
    }

    /// A list of the page rows both thumbnail lists use, as they use it.
    private struct RowList: View {
        let document: PDFDocument
        let state: ListState

        var body: some View {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(PDFThumbnailListPage.rowIndices(of: document), id: \.self) { pageIndex in
                            PDFThumbnailListRow(document: document, pageIndex: pageIndex, pageListVersion: state.pageListVersion) { page in
                                Color.clear.frame(height: 200).onAppear {
                                    state.indicesShown.insert(pageIndex)
                                    if pageIndex == 0 { state.pagesShownAtFirstRow.append(page) }
                                }
                            } placeholder: {
                                Color.clear.frame(height: 200)
                            }
                        }
                    }
                }
                // In the middle, as the app's page list scrolls to the page in view.
                .onChange(of: state.scrollTarget) { if let target = state.scrollTarget { scrollProxy.scrollTo(target, anchor: .center) } }
            }
        }
    }

    private func show(_ list: RowList) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: list)
        window.showInvisibly()
        return window
    }

    /// `waitUntil`, with the window laid out and drawn before each check, as AppKit does between
    /// run-loop turns for a window on screen. The rows a scroll brings in appear in that pass, which
    /// AppKit need not run for an invisible test window: on GitHub's loaded runners a jump's row
    /// now and then did not appear in 20 seconds (3 of about 40 runs), where it takes 25 ms here.
    private func waitUntilLaidOut(_ window: NSWindow, _ description: String, file: StaticString = #filePath, line: UInt = #line,
                                  _ condition: () -> Bool) async throws {
        try await waitUntil(description, file: file, line: line) {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return condition()
        }
    }

    func testJumpingInAListOf1000PagesAsksOnlyForThePagesItShows() async throws {
        let document = CountingPDFDocument()
        for pageIndex in 0..<1_000 { document.insert(PDFPage(), at: pageIndex) }
        document.pageRequests = 0
        let state = ListState()
        let window = show(RowList(document: document, state: state))
        defer { window.close() }

        try await waitUntilLaidOut(window, "the first row is shown") { state.indicesShown.contains(0) }
        XCTAssertLessThan(document.pageRequests, 12, "Opening the list asked for all 1,000, each time its body ran.")

        for target in [900, 950, 3] {
            document.pageRequests = 0
            // Rows shown before do not count: row 3 is on screen when the list opens.
            state.indicesShown = []
            state.scrollTarget = target
            try await waitUntilLaidOut(window, "row \(target) is shown") { state.indicesShown.contains(target) }
            XCTAssertLessThan(document.pageRequests, 12, "A jump to \(target) asked for 900 or more pages when each row asked as it was laid out.")
        }
    }

    func testThePageListOfALongPDFOpensAtThePageInViewDrawingOnlyWhatItShows() async throws {
        let location = try TemporaryVault.make(prefix: "LongPDF", for: self).root.appendingPathComponent("Textbook.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<1_000 {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        let session = try await PDFSession.open(location)
        XCTAssertEqual(session.pageCount, 1_000)
        session.currentPageIndex = 900
        let renderer = PDFThumbnailRenderer()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 210, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PDFPagesSidebar(session: session, commands: PDFPageCommands(session: session), renderer: renderer))
        window.showInvisibly()
        defer { window.close(); renderer.removeThumbnails() }

        let pageInView = try XCTUnwrap(session.document.page(at: 900))
        try await waitUntilLaidOut(window, "the page in view is drawn") { renderer.hasDrawn(pageInView) }
        XCTAssertLessThan(renderer.drawnPageCount, 12, "The rows on the way to the page are laid out, not drawn.")
    }

    func testARowFollowsThePageAtItsIndexWhenTheListChanges() async throws {
        let document = CountingPDFDocument()
        let pages = (0..<3).map { _ in PDFPage() }
        for (pageIndex, page) in pages.enumerated() { document.insert(page, at: pageIndex) }
        let state = ListState()
        let window = show(RowList(document: document, state: state))
        defer { window.close() }
        try await waitUntilLaidOut(window, "the first page is shown") { state.pagesShownAtFirstRow.last === pages[0] }

        document.removePage(at: 0)
        state.pageListVersion += 1

        try await waitUntilLaidOut(window, "the second page is shown at the first row") { state.pagesShownAtFirstRow.last === pages[1] }
    }
    #endif
}
