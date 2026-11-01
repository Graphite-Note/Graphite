/**
 * File: VaultStoreListingWorkTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Placing changed items in a sorted listing, and counting listings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// Placing changed items in a sorted listing, instead of listing and sorting the folder again.
final class VaultStoreListingWorkTests: XCTestCase {
    private func entry(_ path: String, isDirectory: Bool = false, modified: TimeInterval = 0, created: TimeInterval? = nil) throws -> VaultEntry {
        VaultEntry(path: try VaultPath(path), isDirectory: isDirectory, size: 1, modified: Date(timeIntervalSince1970: modified),
                   created: created.map { seconds in Date(timeIntervalSince1970: seconds) })
    }

    func testPlacingChangesGivesWhatSortingEverythingGivesInEveryOrder() throws {
        let entries = try [entry("Folder B", isDirectory: true), entry("Folder A", isDirectory: true), entry("Note 10.md", modified: 5, created: 1),
                           entry("Note 2.md", modified: 9, created: 4), entry("Another.pdf", modified: 1, created: 8), entry("Zed.md", modified: 3, created: 2)]
        for sortOrder in FileSortOrder.allCases {
            let sortedEntries = sortOrder.sorted(entries)
            let changedNote = try entry("Note 2.md", modified: 2, created: 4)
            let newFile = try entry("Note 3.md", modified: 4, created: 3)
            let newFolder = try entry("Folder AA", isDirectory: true)
            let changes: [VaultPath: VaultEntry?] = [changedNote.path: changedNote, newFile.path: newFile, newFolder.path: newFolder,
                                                     try VaultPath("Zed.md"): nil, try VaultPath("Folder B"): nil]

            let placedEntries = sortOrder.applying(changes, to: sortedEntries)

            let expectedEntries = sortOrder.sorted(try [entry("Folder A", isDirectory: true), newFolder, entry("Note 10.md", modified: 5, created: 1),
                                                        changedNote, newFile, entry("Another.pdf", modified: 1, created: 8)])
            XCTAssertEqual(placedEntries, expectedEntries, sortOrder.rawValue)
        }
    }

    func testAnItemAlreadyListedAsItIsLeavesTheListingEqual() throws {
        let sortedEntries = FileSortOrder.alphabetical.sorted(try (0..<50).map { number in try entry("Note \(number).md") })
        let unchanged = sortedEntries[17]
        XCTAssertEqual(FileSortOrder.alphabetical.applying([unchanged.path: unchanged], to: sortedEntries), sortedEntries)
    }

    func testListingsAreCountedAndAnItemIsReadWithoutOne() async throws {
        let vault = try TemporaryVault.make(prefix: "ListingWorkVault", files: ["Note.md": "text", ".hidden/Secret.md": "text", "Folder/Inside.md": "text"], for: self).root
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Link.md"), withDestinationURL: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)

        let entries = await store.entries(at: [try VaultPath("Note.md"), try VaultPath("Folder"), try VaultPath("Gone.md"), try VaultPath(".hidden/Secret.md"), try VaultPath("Link.md")])

        XCTAssertEqual(store.directoryListingCount, 0)
        XCTAssertEqual(entries[try VaultPath("Note.md")]??.size, 4)
        XCTAssertEqual(entries[try VaultPath("Folder")]??.isDirectory, true)
        for path in ["Gone.md", ".hidden/Secret.md", "Link.md"] {
            XCTAssertEqual(entries[try VaultPath(path)].map { entry in entry == nil }, true, "\(path) is not what a listing shows")
        }

        let listed = try await store.children(of: .root)
        XCTAssertEqual(listed.map(\.path.rawValue), ["Folder", "Note.md"])
        XCTAssertEqual(store.directoryListingCount, 1)
    }

    func testSettingsRevisionMovesWithTheSettingsFilesAndNotWithObsidiansWorkspace() async throws {
        let vault = try TemporaryVault.make(prefix: "ListingWorkVault", files: [".obsidian/app.json": "{}", ".obsidian/workspace.json": "{}"], for: self).root
        let store = VaultStore(root: vault)
        let before = await store.settingsFilesRevision()
        try Data("{\"active\":1}".utf8).write(to: vault.appendingPathComponent(".obsidian/workspace.json"))
        let afterWorkspace = await store.settingsFilesRevision()
        XCTAssertEqual(before, afterWorkspace)
        try Data("{\"a\":1}".utf8).write(to: vault.appendingPathComponent(".obsidian/app.json"))
        let afterSettings = await store.settingsFilesRevision()
        XCTAssertNotEqual(before, afterSettings)
    }
}
