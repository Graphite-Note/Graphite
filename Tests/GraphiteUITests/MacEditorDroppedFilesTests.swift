/**
 * File: MacEditorDroppedFilesTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Several files dropped at one point of a note in the Mac editor, each saved as an attachment by the
 *              workspace: every embed is whole, on a line of its own, in the order the files were dropped.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Three files dragged from the Finder onto the end of a note in the Mac app came out as
/// `![[Made-up handout 1.pdf]]`, `!![[Made-up picture 1.png]]` and `[[Made-up schedule 1.csv]]`
/// (2026-11-19): one embed took the next one's `!`, and the saves, each in a task of its own,
/// embedded the files in the order they happened to end.
@MainActor
final class MacEditorDroppedFilesTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var fixture: MacMarkdownEditorFixture?

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
    }

    private func editorOfANote(text: String) async throws -> (WorkspaceModel, MacMarkdownEditorFixture) {
        let vault = try TemporaryVault.make(prefix: "DroppedFilesVault", for: self).root.resolvingSymlinksInPath()
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let fixture = try MacMarkdownEditorFixture(showing: session)
        self.fixture = fixture
        session.isEditorAttached = true
        // As the pane connects the editor.
        fixture.coordinator.actions.insertAttachment = { [workspace, session] data, stem, fileExtension, range in
            workspace.saveAttachmentInOrder(data, stem: stem, fileExtension: fileExtension, into: session, at: range)
        }
        return (workspace, fixture)
    }

    /// Applies each embed as the editor's view update does once a save has inserted it.
    private func applyInsertions(count: Int, in fixture: MacMarkdownEditorFixture) async throws {
        for _ in 0..<count {
            try await waitUntil { fixture.session.pendingInsertion != nil }
            fixture.coordinator.apply(try XCTUnwrap(fixture.session.pendingInsertion), to: fixture.textView)
        }
    }

    func testFilesDroppedAtTheEndOfANoteAreWholeEmbedsInTheirOrder() async throws {
        let text = "# Note\n\nSome text.\n![[Earlier.png]]\n"
        let (_, fixture) = try await editorOfANote(text: text)
        let dropPoint = NSRange(location: (text as NSString).length, length: 0)
        // As `insertAttachments` hands each file of one drop the same place.
        for (stem, fileExtension) in [("Handout", "pdf"), ("Picture", "png"), ("Schedule", "csv")] {
            fixture.textView.insertAttachment?(Data("\(stem)".utf8), stem, fileExtension, dropPoint)
        }
        try await applyInsertions(count: 3, in: fixture)
        let lines = fixture.textView.string.components(separatedBy: "\n").filter { line in line.contains("[[") }
        XCTAssertEqual(lines, ["![[Earlier.png]]", "![[Handout.pdf]]", "![[Picture.png]]", "![[Schedule.csv]]"], fixture.textView.string)
    }

    func testFilesDroppedInTheMiddleOfALineAreWholeEmbedsInTheirOrder() async throws {
        let text = "# Note\n\nBefore after.\n"
        let (_, fixture) = try await editorOfANote(text: text)
        let dropPoint = NSRange(location: (text as NSString).range(of: " after").location, length: 0)
        for (stem, fileExtension) in [("Handout", "pdf"), ("Picture", "png"), ("Schedule", "csv")] {
            fixture.textView.insertAttachment?(Data("\(stem)".utf8), stem, fileExtension, dropPoint)
        }
        try await applyInsertions(count: 3, in: fixture)
        let embeds = fixture.textView.string.components(separatedBy: "\n").filter { line in line.contains("[[") }
        XCTAssertEqual(embeds, ["![[Handout.pdf]]", "![[Picture.png]]", "![[Schedule.csv]]"], fixture.textView.string)
        XCTAssertTrue(fixture.textView.string.contains("Before"), fixture.textView.string)
        XCTAssertTrue(fixture.textView.string.contains("after."), fixture.textView.string)
    }

    /// On a busy Mac every save can end before the editor shows the first embed: the later
    /// embeds are then placed in a text that already holds the ones still waiting.
    func testFilesWhoseSavesAllEndBeforeTheEditorShowsTheFirstAreInTheirOrder() async throws {
        for text in ["# Note\n\nSome text.\n", "# Note\n\nBefore after.\n"] {
            let (_, fixture) = try await editorOfANote(text: text)
            let dropPoint = NSRange(location: text.hasSuffix("after.\n") ? (text as NSString).range(of: " after").location : (text as NSString).length, length: 0)
            for (stem, fileExtension) in [("Handout", "pdf"), ("Picture", "png"), ("Schedule", "csv")] {
                fixture.textView.insertAttachment?(Data("\(stem)".utf8), stem, fileExtension, dropPoint)
            }
            await fixture.session.lastAttachmentSave?.value
            try await applyInsertions(count: 3, in: fixture)
            let embeds = fixture.textView.string.components(separatedBy: "\n").filter { line in line.contains("[[") }
            XCTAssertEqual(embeds, ["![[Handout.pdf]]", "![[Picture.png]]", "![[Schedule.csv]]"], fixture.textView.string)
            fixture.tearDown()
            self.fixture = nil
        }
    }
}
#endif
