/**
 * File: FileTreeRowNamingTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The iPad's and the iPhone's file list name items in its rows: where a new item's field goes, what a
 *              rename starts with, and that Return on a name the folder has keeps the field.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class FileTreeRowNamingTests: XCTestCase {
    private func row(_ path: String, depth: Int, isFolder: Bool = false) throws -> FileTreeRow {
        FileTreeRow(entry: VaultEntry(path: try VaultPath(path), isDirectory: isFolder, size: 0, modified: Date(timeIntervalSince1970: 0)), depth: depth)
    }

    /// A new folder's field is the folder's first row; a new file's is where the folder's files begin, after its
    /// folders and what they show, at the depth of the folder's contents.
    func testANewItemsFieldGoesFirstForAFolderAndWhereTheFilesBeginForAFile() throws {
        let rows = [try row("Courses", depth: 0, isFolder: true), try row("Courses/Labs", depth: 1, isFolder: true),
                    try row("Courses/Labs/Lab 1.md", depth: 2), try row("Courses/Week 1.md", depth: 1), try row("Root.md", depth: 0)]
        let courses = try VaultPath("Courses")
        XCTAssertEqual(FileTreeRowNaming.newItemPlace(in: rows, folder: courses, isFolder: true).map { [$0.index, $0.depth] }, [1, 1])
        XCTAssertEqual(FileTreeRowNaming.newItemPlace(in: rows, folder: courses, isFolder: false).map { [$0.index, $0.depth] }, [3, 1])
        XCTAssertEqual(FileTreeRowNaming.newItemPlace(in: rows, folder: .root, isFolder: false).map { [$0.index, $0.depth] }, [4, 0])
        XCTAssertEqual(FileTreeRowNaming.newItemPlace(in: rows, folder: .root, isFolder: true).map { [$0.index, $0.depth] }, [0, 0])
        // A folder with no files yet, or not listed yet: the field goes at the end of what it shows.
        XCTAssertEqual(FileTreeRowNaming.newItemPlace(in: rows, folder: try VaultPath("Courses/Labs"), isFolder: false).map { [$0.index, $0.depth] }, [2, 2])
        XCTAssertNil(FileTreeRowNaming.newItemPlace(in: rows, folder: try VaultPath("Elsewhere"), isFolder: false))
    }

    func testNothingIsNamedInARowWhileTheTreeIsNotOnScreen() throws {
        let (workspace, naming) = try makeNaming(rows: [try row("Root.md", depth: 0)])
        naming.isTreeOnScreen = { false }
        XCTAssertFalse(naming.beginNaming(.rename(try VaultPath("Root.md"))))
        XCTAssertNil(naming.field)
        workspace.requestRename(try VaultPath("Root.md"))
        guard case .rename = workspace.fileSheet else { return XCTFail("The Rename sheet stands in.") }
    }

    /// A rename starts with the name the row shows, without a note's extension; Return on a name the folder already
    /// has keeps the field and asks for the keyboard again, and the keyboard's loss of focus that follows is not a
    /// click elsewhere.
    func testReturnOnATakenNameKeepsTheFieldThroughTheFocusItsReturnTakes() throws {
        // The naming holds its workspace weakly, as the list's host does.
        let (workspace, naming) = try makeNaming(rows: [try row("Root.md", depth: 0), try row("Other.md", depth: 0)])
        defer { withExtendedLifetime(workspace) {} }
        XCTAssertTrue(naming.beginNaming(.rename(try VaultPath("Root.md"))))
        XCTAssertEqual(naming.field?.text, "Root")
        naming.setText("other")
        XCTAssertNotNil(naming.problem)
        naming.end(.returnKey)
        XCTAssertNotNil(naming.field)
        XCTAssertEqual(naming.refocusRequest, 1)
        naming.end(.focusLeft)
        XCTAssertNotNil(naming.field, "The focus Return took away is not a click elsewhere.")
        naming.end(.escapeKey)
        XCTAssertNil(naming.field)
    }

    /// A new item in a folded folder opens the folder and the folders above it.
    func testANewItemOpensItsFolderAndTheFoldersAboveIt() throws {
        let (workspace, naming) = try makeNaming(rows: [try row("Signals", depth: 0, isFolder: true)])
        let labs = try VaultPath("Signals/Labs")
        try FileManager.default.createDirectory(at: try labs.url(in: try XCTUnwrap(workspace.folderAccess?.root)), withIntermediateDirectories: true)
        XCTAssertTrue(naming.beginNaming(.create(.note, in: labs)))
        XCTAssertEqual(workspace.expandedFolders, [try VaultPath("Signals"), labs])
        XCTAssertEqual(naming.field?.text, "")
        XCTAssertFalse(naming.beginNaming(.create(.note, in: try VaultPath("Signals/Missing"))), "A folder not there yet has no row.")
    }

    private func makeNaming(rows: [FileTreeRow]) throws -> (WorkspaceModel, FileTreeRowNaming) {
        let vault = try TemporaryVault.make(prefix: "TreeRowNaming", for: self).root
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        var children: [VaultPath: [VaultEntry]] = [:]
        for row in rows { children[row.entry.path.parent, default: []].append(row.entry) }
        workspace.fileTreeContents.apply(rootEntries: children[.root] ?? [], expandedFolders: [])
        let naming = workspace.fileTreeContents.rowNaming
        naming.attach(to: workspace.fileTreeRowNamingVault)
        naming.isTreeOnScreen = { true }
        workspace.registerFileTreeNaming(naming)
        return (workspace, naming)
    }
}
