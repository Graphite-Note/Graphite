/**
 * File: EditingBehaviorTyping.swift
 * ---------------------------------
 * Layer: UI
 * Description: What a key typed in a note does beyond inserting itself, the same in the iPad's and the Mac's editors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

extension EditingBehavior {
    /// Obsidian's typing helpers: lists that continue on Return, Tab to indent list items,
    /// bracket pairs, and Backspace removing an empty pair. The edit to make in place of
    /// replacing `range` with `replacement`, or nil to let the text view make that change.
    func typingEdit(replacing range: NSRange, with replacement: String, in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        switch replacement {
        case "\n":
            return continuesLists ? MarkdownEditing.continuingList(in: text, selection: range, indentUnit: indentUnit, tabSize: tabSize) : nil
        case "\t":
            let line = text.substring(with: text.lineRange(for: NSRange(location: range.location, length: 0)))
            guard continuesLists, MarkdownListSyntax.listLine(line.trimmingCharacters(in: .newlines))?.isListItem == true || selection.length > 0 else { return nil }
            return MarkdownEditing.indenting(in: text, selection: selection, indentUnit: indentUnit)
        case "":
            guard range.length == 1, selection.length == 0, NSMaxRange(range) == selection.location, pairsBrackets else { return nil }
            return MarkdownEditing.deletingPair(in: text, selection: selection)
        default:
            return MarkdownEditing.pairing(typed: replacement, in: text, selection: range, pairsBrackets: pairsBrackets, pairsMarkdown: pairsMarkdown)
        }
    }
}
