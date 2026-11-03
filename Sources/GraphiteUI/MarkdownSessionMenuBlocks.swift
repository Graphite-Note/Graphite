/**
 * File: MarkdownSessionMenuBlocks.swift
 * -------------------------------------
 * Layer: UI
 * Description: Inserting a block chosen from a menu into a note, with the cursor where it is filled in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
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
        let source = target.text
        let location = max(min(target.range.location, source.length), FrontmatterLocator.length(in: source))
        let range = NSRange(location: location, length: 0)
        let insertion = MarkdownBlockInsertion.text(inserting: block, into: source, replacing: range)
        let placeInInsertion = EditorContextMenuContent.typingPlace(inBlock: block).flatMap { place in
            MarkdownBlockInsertion.place(place, inBlock: block, inInsertion: insertion)
        }
        request(EditorInsertion(text: insertion, range: range, selectionAfter: placeInInsertion?.shifted(by: location)))
        startsEditingWhenShown = true
    }
}
