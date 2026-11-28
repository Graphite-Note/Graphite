/**
 * File: NoteLinksInspectorPartsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The right sidebar reads a note's outline, links, tags and footnotes away from the main thread, as it
 *              does at every switch to another note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import Foundation
import Synchronization
@testable import GraphiteUI

/// The sidebar's outline of a long note took 25 to 38 ms of the main thread at every switch to it, also while the sidebar
/// was hidden (`Docs/View-switching-speed-todo.md` section 1); it is read in a detached task since 2026-11-09.
final class NoteLinksInspectorPartsTests: XCTestCase {
    private let note = """
        # Lecture
        A [[Link]] and a #course/vlsi tag.[^1]
        ## Lecture
        Text.

        [^1]: A footnote.
        """

    /// Asked from the main actor, as the sidebar's task asks, the parts are never read on the main thread.
    @MainActor
    func testTheNotesPartsAreReadOffTheMainThreadWhenTheMainActorAsks() async throws {
        let ranOnTheMainThread = Mutex<[Bool]>([])
        let parts = try await NoteLinksInspector.readParts(of: note) { text in
            ranOnTheMainThread.withLock { observations in observations.append(pthread_main_np() != 0) }
            return try NoteLinksInspector.parts(of: text)
        }
        XCTAssertEqual(ranOnTheMainThread.withLock { observations in observations }, [false])
        XCTAssertEqual(parts.outline.map(\.text), ["Lecture", "Lecture"])
        XCTAssertEqual(parts.outline.map(\.occurrence), [0, 1], "The second heading that reads the same is numbered after the first.")
    }

    func testThePartsAreTheNotesLinksTagsFootnotesAndOutline() throws {
        let parts = try NoteLinksInspector.parts(of: note)
        XCTAssertEqual(parts.outgoing, [NoteLinksInspector.OutgoingLink(target: "Link", isWiki: true)])
        XCTAssertEqual(parts.tags, ["course/vlsi"])
        XCTAssertEqual(parts.footnotes.count, 1)
        XCTAssertEqual(parts.outline.map(\.level), [1, 2])
    }
}
