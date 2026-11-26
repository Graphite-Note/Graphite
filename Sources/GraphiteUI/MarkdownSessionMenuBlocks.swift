/**
 * File: MarkdownSessionMenuBlocks.swift
 * -------------------------------------
 * Layer: UI
 * Description: Inserting a block chosen from a menu into a note, with the cursor where it is filled in.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

extension MarkdownSession {
    /// Inserts a block chosen from a menu: below the selected text, which it must not
    /// replace, with the cursor where the block is filled in (the empty line of a formula or
    /// code block, a table's first cell) and the note taking the keyboard. Left after the
    /// block, typing went below it, and an empty formula drew as nothing.
    func insertBlockFromMenu(_ block: String) {
        let target = insertionTarget(for: NSRange(location: NSMaxRange(selection), length: 0))
        let edit = Self.menuBlockEdit(block, in: target.text, after: target.range.location)
        // Without a place to fill in, the editor leaves the cursor after the block, as it leaves it after any insertion.
        let fillsInPlace = EditorContextMenuContent.typingPlace(inBlock: block) != nil
        request(EditorInsertion(text: edit.replacement, range: edit.range, selectionAfter: fillsInPlace ? edit.selectionAfter : nil))
        startsEditingWhenShown = true
    }

    /// The edit that puts a menu's block on lines of its own at `location` of `source`, after
    /// the frontmatter, with the cursor where the block is filled in, else after it. The slash
    /// commands make it on the note as it is once their `/query` is taken out (`SlashCommandEditRecorder`).
    static func menuBlockEdit(_ block: String, in source: NSString, after location: Int) -> MarkdownTextEdit {
        let blockLocation = max(min(location, source.length), FrontmatterLocator.length(in: source))
        let range = NSRange(location: blockLocation, length: 0)
        let insertion = MarkdownBlockInsertion.text(inserting: block, into: source, replacing: range)
        let placeInInsertion = EditorContextMenuContent.typingPlace(inBlock: block).flatMap { place in
            MarkdownBlockInsertion.place(place, inBlock: block, inInsertion: insertion)
        }
        let selectionAfter = placeInInsertion?.shifted(by: blockLocation) ?? NSRange(location: blockLocation + insertion.utf16.count, length: 0)
        return MarkdownTextEdit(range: range, replacement: insertion, selectionAfter: selectionAfter)
    }
}
