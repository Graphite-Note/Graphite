/**
 * File: EditorCompletionRecentFilesTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The notes offered after typing [[ with nothing after it exist.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

/// HUNT-188: the list offered recently opened notes without asking the file system, so a note
/// deleted or renamed in another app was offered and chosen as a link to nothing.
@MainActor
final class EditorCompletionRecentFilesTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    func testTypingTwoBracketsOffersOnlyRecentNotesThatStillExist() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Editing.md": "[[", "Present.md": "Present.", "Gone.md": "Gone."])
        try await testBed.open("Present.md", in: workspace)
        try await testBed.open("Gone.md", in: workspace, placement: .newTab)
        try await testBed.open("Editing.md", in: workspace, placement: .newTab)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Gone.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let context = LinkCompletion.context(in: "[[" as NSString, cursor: 2)

        let items = await CompletionProvider(workspace: workspace, session: session).items(for: try XCTUnwrap(context))

        XCTAssertEqual(items.map(\.title), ["Present"], "The open note itself and the deleted one are left out.")
    }
}
