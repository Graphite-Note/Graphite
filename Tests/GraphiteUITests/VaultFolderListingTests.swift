/**
 * File: VaultFolderListingTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The folder walk of the Move sheet lists visible folders and stops when its task is cancelled (HUNT-114).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

final class VaultFolderListingTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "VaultFolderListing", for: self).root
        for folder in ["Courses/Physics", "Courses/Mathematics", "Archive", ".obsidian/plugins", "Empty"] {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data("# Note\n".utf8).write(to: vault.appendingPathComponent("Courses/Note.md"))
    }

    func testFoldersAreListedInNameOrderWithoutHiddenOnesOrFiles() throws {
        let folders = try VaultFolderListing.folders(in: vault)

        XCTAssertEqual(folders.map(\.rawValue), ["Archive", "Courses", "Courses/Mathematics", "Courses/Physics", "Empty"])
    }

    /// A walk nobody waits for any longer used to go on to its end, once for every time the sheet was opened.
    func testAWalkInACancelledTaskStops() async throws {
        let root = vault!
        let walk = Task<[VaultPath], Error> {
            while !Task.isCancelled { await Task.yield() }
            return try VaultFolderListing.folders(in: root)
        }
        walk.cancel()

        do {
            _ = try await walk.value
            XCTFail("The walk should have stopped.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
