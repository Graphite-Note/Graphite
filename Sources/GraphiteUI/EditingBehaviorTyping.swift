/**
 * File: EditingBehaviorTyping.swift
 * ---------------------------------
 * Layer: UI
 * Description: What a key typed in a note does beyond inserting itself, the same in the iPad's and the Mac's editors.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
 */

import Foundation
import GraphiteCore

extension EditingBehavior {
    /// Obsidian's typing helpers: lists that continue on Return, indentation kept on Return,
    /// Tab to indent list items, bracket pairs, a code fence's closing line, and Backspace
    /// removing an empty pair or a level of spaces. The edit to make in place of replacing `range` with
    /// `replacement`, or nil to let the text view make that change.
    func typingEdit(replacing range: NSRange, with replacement: String, in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        switch replacement {
        case "\n":
            if continuesLists, let edit = MarkdownEditing.continuingList(in: text, selection: range, indentUnit: indentUnit, tabSize: tabSize) { return edit }
            // As in Obsidian, the indentation is kept with or without smart lists.
            return MarkdownEditing.newLineKeepingIndentation(in: text, selection: range)
        case "\t":
            let line = text.substring(with: text.lineRange(for: NSRange(location: range.location, length: 0)))
            let isListItem = MarkdownListSyntax.listLine(line.trimmingCharacters(in: .newlines))?.isListItem == true
            guard continuesLists, isListItem || selection.length > 0 else { return nil }
            return MarkdownEditing.indenting(in: text, selection: selection, indentUnit: indentUnit, tabSize: tabSize)
        case "":
            guard range.length == 1, selection.length == 0, NSMaxRange(range) == selection.location else { return nil }
            if let edit = MarkdownEditing.deletingIndentation(in: text, selection: selection, indentUnit: indentUnit) { return edit }
            guard pairsBrackets || pairsMarkdown else { return nil }
            return MarkdownEditing.deletingPair(in: text, selection: selection, pairsBrackets: pairsBrackets, pairsMarkdown: pairsMarkdown)
        default:
            // A fence's closing line, like Obsidian's backtick pairs, comes with "Auto pair Markdown syntax".
            if pairsMarkdown, let fence = MarkdownEditing.closingCodeFence(typed: replacement, in: text, selection: range) { return fence }
            return MarkdownEditing.pairing(typed: replacement, in: text, selection: range, pairsBrackets: pairsBrackets, pairsMarkdown: pairsMarkdown)
        }
    }
}
