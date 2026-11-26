/**
 * File: MarkdownSessionOutdatedSiblingTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: A note opened again while an older session of it is still alive shows the file as it is
 *              now, not the older session's text, unless that session holds edits not saved yet.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Found 2026-11-27 with Meta Bind's "Start lecture" in the iPad simulator, pressed by finger: Templater
/// wrote the course page's count of lectures, then opened the new lecture in the course page's tab. The
/// course page's session, no longer shown, stayed alive a few seconds (closed sessions are released
/// about 2.8 s later) without taking the write in. Back on the course page, its new session took that
/// older session's text and saved state (one note in several windows is one text), so the editor showed
/// the old count while the file had the new one, and a save would have written the old count back.
@MainActor
final class MarkdownSessionOutdatedSiblingTests: XCTestCase {
    private func makeVault(_ text: String) throws -> (VaultStore, VaultPath) {
        let vault = try TemporaryVault.make(prefix: "OutdatedSibling", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Course.md"))
        return (VaultStore(root: vault), try VaultPath("Course.md"))
    }

    private func open(_ path: VaultPath, in store: VaultStore, openNotes: OpenNoteFiles) async throws -> MarkdownSession {
        try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, openNotes: openNotes) { _ in }
    }

    func testANoteOpenedAgainAfterAnotherAppChangedItShowsTheFileNotTheOlderSessionsText() async throws {
        let (store, path) = try makeVault("---\nlectures_held: 1\n---\n")
        let openNotes = OpenNoteFiles()
        let olderSession = try await open(path, in: store, openNotes: openNotes)
        // Another app (a plugin through the vault) writes the note while the older session holds no edit.
        try Data("---\nlectures_held: 2\n---\n".utf8).write(to: store.root.appendingPathComponent("Course.md"))

        let session = try await open(path, in: store, openNotes: openNotes)
        XCTAssertEqual(session.text, "---\nlectures_held: 2\n---\n", "the note opened again shows the file")
        XCTAssertEqual(session.savedText, session.text)
        XCTAssertFalse(session.hasUnsavedChanges, "nothing is left to save, so the old count is never written back")
        XCTAssertEqual(olderSession.text, session.text, "the older session, still open, takes the file as it is now too")
        XCTAssertFalse(olderSession.hasUnsavedChanges)
    }

    func testANoteOpenedAgainWhileAnOlderSessionHoldsUnsavedEditsShowsThoseEdits() async throws {
        let (store, path) = try makeVault("Draft\n")
        let openNotes = OpenNoteFiles()
        let olderSession = try await open(path, in: store, openNotes: openNotes)
        olderSession.text = "Draft with an edit\n"

        let session = try await open(path, in: store, openNotes: openNotes)
        XCTAssertEqual(session.text, "Draft with an edit\n", "a note open in two windows is one text, unsaved edits included")
        XCTAssertTrue(session.hasUnsavedChanges)
    }
}
