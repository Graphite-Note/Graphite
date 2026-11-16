/**
 * File: NoteEditorWorkCountTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: How much a key costs in the note editor: on common lines no key restyles the whole note or scans it for blocks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class NoteEditorWorkCountTests: XCTestCase {
    private func blockEntries(in source: NSString) -> [LivePreviewBlockEntry] {
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        return zip(blocks, LivePreviewBlockKey.keys(for: blocks)).map { block, key in LivePreviewBlockEntry(block: block, range: block.range, key: key) }
    }

    /// One character typed in `line`, at its end, with note text around it.
    private func typing(on line: String) -> (edit: CharacterEdit, before: NSString, after: NSString) {
        let before = "Above\n\n\(line)\n\nBelow\n" as NSString
        let location = 7 + (line as NSString).length
        let after = before.replacingCharacters(in: NSRange(location: location, length: 0), with: "x") as NSString
        return (CharacterEdit(editedRange: NSRange(location: location, length: 1), changeInLength: 1), before, after)
    }

    private func restylePlan(typingOn line: String, typed: String = "x") -> LivePreviewRestylePlan {
        let (edit, before, after) = typing(on: line)
        let unstyled = UnstyledEdit(edit: edit, sourceBeforeEdit: before, revealedRange: nil, blockRanges: [])
        return unstyled.restylePlan(source: after, revealedRange: nil, blockRanges: [])
    }

    // MARK: HUNT-053

    /// Before: every key on a line holding `$$` restyled the whole note (one whole-note pass
    /// per key). Now: the edited line only (no whole-note pass).
    func testTypingInABalancedFormulaRestylesItsLineOnly() {
        for line in ["$$E=mc^2$$", "text $$E=mc^2$$ text", "> $$x$$"] {
            guard case .ranges = restylePlan(typingOn: line) else { return XCTFail("\(line) restyled the whole note.") }
        }
    }

    func testAKeyThatOpensOrClosesMathRestylesTheWholeNote() {
        // Deleting the closing `$` leaves `$$E=mc^2$` open: later lines become math.
        let before = "Above\n\n$$E=mc^2$$\n\nBelow\n" as NSString
        let location = before.range(of: "$$\n").location + 1
        let after = before.replacingCharacters(in: NSRange(location: location, length: 1), with: "") as NSString
        let unstyled = UnstyledEdit(edit: CharacterEdit(editedRange: NSRange(location: location, length: 0), changeInLength: -1), sourceBeforeEdit: before, revealedRange: nil, blockRanges: [])
        guard case .everything = unstyled.restylePlan(source: after, revealedRange: nil, blockRanges: []) else { return XCTFail("A formula left open changes every line below.") }
    }

    func testDeletingAClosingDelimiterInAMathBlockRestylesTheWholeNote() {
        let before = "$$\nx\ny $$\nBelow\n" as NSString
        let location = before.range(of: "y $$").location + 3
        let after = before.replacingCharacters(in: NSRange(location: location, length: 1), with: "") as NSString
        let unstyled = UnstyledEdit(edit: CharacterEdit(editedRange: NSRange(location: location, length: 0), changeInLength: -1), sourceBeforeEdit: before, revealedRange: nil, blockRanges: [])
        guard case .everything = unstyled.restylePlan(source: after, revealedRange: nil, blockRanges: []) else { return XCTFail("The line no longer closes the block.") }
    }

    func testTypingInAFormulaFindsOnlyThatBlockAgain() throws {
        let before = "Above\n\n$$E=mc^2$$\n\n$$\nx\n$$\n\nBelow\n" as NSString
        let entries = blockEntries(in: before)
        XCTAssertEqual(entries.filter { entry in entry.block.kind == .mathBlock }.count, 2)
        for location in [before.range(of: "mc^2").location, before.range(of: "\nx\n").location + 2] {
            let after = before.replacingCharacters(in: NSRange(location: location, length: 0), with: "q") as NSString
            let edit = CharacterEdit(editedRange: NSRange(location: location, length: 1), changeInLength: 1)
            XCTAssertNil(LivePreviewBlockShifting.entries(entries, across: edit, sourceBeforeEdit: before, source: after))
            let moved = try XCTUnwrap(LivePreviewBlockShifting.entriesFindingEditedCalloutAgain(entries, across: edit, sourceBeforeEdit: before, source: after, isRendered: { _ in true }),
                                      "Each key would scan the whole note for blocks.")
            XCTAssertEqual(moved.map(\.range), blockEntries(in: after).map(\.range))
            XCTAssertEqual(moved.map(\.key), blockEntries(in: after).map(\.key))
        }
    }

    // MARK: HUNT-054

    /// Before: each of these lines scanned the whole note for blocks on every key (one pass over
    /// every line per key). Now: none does; the entries only move.
    func testTypingOnALineThatOnlyLooksLikeABlockScansNothing() throws {
        for line in ["**Definition.** text", "$x$ is a number", "> a quote", "`code` first", "_note_ here", ".5 of it", "-5 degrees", "*word* first", "!important", "~tilde", ":smile:"] {
            let (edit, before, after) = typing(on: line)
            let entries = blockEntries(in: before)
            let moved = LivePreviewBlockShifting.entries(entries, across: edit, sourceBeforeEdit: before, source: after)
            XCTAssertNotNil(moved, "\(line) scanned the note.")
            XCTAssertEqual(moved?.map(\.range), blockEntries(in: after).map(\.range), line)
        }
    }

    func testTypingOnALineThatCanJoinABlockScansTheNote() {
        for line in ["```", "~~~", "$$", "| a | b |", "![[embed", "---", "***", "___", "...", "> [!note", "> ```", "=== "] {
            let (edit, before, after) = typing(on: line)
            let moved = LivePreviewBlockShifting.entries([], across: edit, sourceBeforeEdit: before, source: after)
            XCTAssertNil(moved, line)
        }
    }

    /// A quote that becomes a callout with the key that closes its `[!type]` is found.
    func testAQuoteBecomingACalloutIsFound() {
        let before = "Above\n\n> [!note\n\nBelow\n" as NSString
        let location = before.range(of: "[!note").location + 6
        let after = before.replacingCharacters(in: NSRange(location: location, length: 0), with: "]") as NSString
        let edit = CharacterEdit(editedRange: NSRange(location: location, length: 1), changeInLength: 1)
        XCTAssertNil(LivePreviewBlockShifting.entries([], across: edit, sourceBeforeEdit: before, source: after))
    }

    // MARK: Table cell drafts: HUNT-055, HUNT-073

    private static let table = "| A | B |\n| --- | --- |\n| one | two |\n"

    private func makeTableEditor(source: inout String) -> (LivePreviewTableEditor, RenderedBlockSourceEditing, UnsafeMutablePointer<String>) {
        let box = UnsafeMutablePointer<String>.allocate(capacity: 1)
        box.initialize(to: source)
        addTeardownBlock { box.deinitialize(count: 1); box.deallocate() }
        let editing = RenderedBlockSourceEditing(replaceSource: { _, transform in
            if let replacement = transform(box.pointee) { box.pointee = replacement }
        }, setIsEditingInView: { _, _ in })
        let editor = LivePreviewTableEditor()
        editor.update(source: box.pointee, textSize: 16, sourceEditing: editing)
        return (editor, editing, box)
    }

    /// The top bar's Undo reverts the cell under an open editor: the field shows it, and the
    /// next key does not write the old text back.
    func testUndoUnderAnOpenCellReloadsTheCell() async throws {
        var source = Self.table
        let (editor, editing, box) = makeTableEditor(source: &source)
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        XCTAssertEqual(editor.draftText, "one")
        editor.draftText = "one more"
        editor.commitDraft()
        XCTAssertTrue(box.pointee.contains("one more"))
        editor.update(source: box.pointee, textSize: 16, sourceEditing: editing)
        XCTAssertEqual(editor.draftText, "one more", "Its own write changes nothing.")

        box.pointee = Self.table // Undo.
        editor.update(source: box.pointee, textSize: 16, sourceEditing: editing)
        await Task.yield()
        XCTAssertEqual(editor.draftText, "one")
        editor.commitDraft()
        XCTAssertEqual(box.pointee, Self.table, "Nothing is written back.")
    }

    func testSpacesAtTheEndOfADraftAreNotTakenForAChangeElsewhere() async throws {
        var source = Self.table
        let (editor, editing, box) = makeTableEditor(source: &source)
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        editor.draftText = "one "
        editor.commitDraft()
        editor.update(source: box.pointee, textSize: 16, sourceEditing: editing)
        await Task.yield()
        XCTAssertEqual(editor.draftText, "one ", "The person is still typing.")
    }

    /// The draft a save would miss reaches the session's text first.
    func testASaveWritesTheOpenCellsDraft() async throws {
        let vault = try TemporaryVault.make(prefix: "Drafts", for: self).root
        let noteURL = vault.appendingPathComponent("Note.md")
        try Data(Self.table.utf8).write(to: noteURL)
        let store = VaultStore(root: vault)
        let path = try VaultPath("Note.md")
        let session = try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
        let editing = RenderedBlockSourceEditing(replaceSource: { _, transform in
            if let replacement = transform(session.text) { session.text = replacement }
        }, setIsEditingInView: { _, _ in }, setDraftCommit: { editor, commit in session.blockViews.draftCommits[editor] = commit })
        let editor = LivePreviewTableEditor()
        editor.update(source: session.text, textSize: 16, sourceEditing: editing)
        editor.beginEditing(TableCellPosition(row: 1, column: 1))
        editor.draftText = "typed just now"
        try await session.save()
        XCTAssertTrue(try String(contentsOf: noteURL, encoding: .utf8).contains("typed just now"), "The last words typed were lost.")
        editor.endEditing()
        XCTAssertTrue(session.blockViews.draftCommits.isEmpty)
    }

    // MARK: Menu blocks: HUNT-056, HUNT-057

    private func makeSession(text: String) async throws -> MarkdownSession {
        let vault = try TemporaryVault.make(prefix: "Blocks", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let path = try VaultPath("Note.md")
        return try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
    }

    func testABlockFromAMenuKeepsTheSelectedText() async throws {
        let session = try await makeSession(text: "A paragraph\n")
        session.selection = NSRange(location: 2, length: 9)
        session.insertBlockFromMenu(EditorContextMenuContent.calloutBlock)
        XCTAssertTrue(session.text.hasPrefix("A paragraph"), session.text)
        XCTAssertTrue(session.text.contains("> [!note]\n> "), session.text)
    }

    func testTheCursorGoesInsideABlockFromAMenu() async throws {
        for (block, expectedBefore, expectedLength) in [(EditorContextMenuContent.mathBlock, "$$\n", 0), (EditorContextMenuContent.codeBlock, "```\n", 0),
                                                        (EditorContextMenuContent.calloutBlock, "> [!note]\n> ", 0), (EditorContextMenuContent.tableBlock, "| ", 6)] {
            let session = try await makeSession(text: "")
            session.selection = NSRange(location: 0, length: 0)
            session.insertBlockFromMenu(block)
            XCTAssertEqual(session.selection, NSRange(location: expectedBefore.utf16.count, length: expectedLength), block)
            XCTAssertTrue(session.startsEditingWhenShown, "The note takes the keyboard.")
        }
    }

    func testTheCursorFindsItsPlaceBelowTextAndInACRLFNote() async throws {
        let session = try await makeSession(text: "Line\r\nNext\r\n")
        session.selection = NSRange(location: 4, length: 0)
        session.insertBlockFromMenu(EditorContextMenuContent.mathBlock)
        let text = session.text as NSString
        XCTAssertTrue(session.text.contains("$$\r\n\r\n$$"), session.text)
        XCTAssertEqual(session.selection.location, text.range(of: "$$\r\n").location + 4)
    }

    func testARuleFromAMenuLeavesTheCursorAfterIt() async throws {
        let session = try await makeSession(text: "")
        session.insertBlockFromMenu(EditorContextMenuContent.horizontalRule)
        XCTAssertEqual(session.selection.location, (session.text as NSString).length)
    }
}
