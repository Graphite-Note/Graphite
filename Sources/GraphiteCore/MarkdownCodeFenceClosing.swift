/**
 * File: MarkdownCodeFenceClosing.swift
 * ------------------------------------
 * Layer: Core
 * Description: The closing fence a code block gets when its opening fence is typed, so the block is whole from the start.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

extension MarkdownEditing {
    /// What typing the third backtick of a fence at the start of a line does: the fence is
    /// completed and a closing fence goes on the line below, with the cursor after the opening
    /// fence, where the block's language is typed; Return then opens the line between. A fence
    /// in a quote or callout, or indented, gets a closing line with the same `>` markers and
    /// indentation.
    ///
    /// Obsidian, with "Auto pair Markdown syntax" on, puts the closing fence on the same line
    /// (```` ```|``` ````); the owner asked for it below, where it is already where it belongs.
    /// Nil, so the backtick is typed alone, when the fence would close an open block or when
    /// a fence further down has no partner (its opening fence was just deleted), when
    /// text follows the cursor, inside the note's properties, and for `~~~`, which Obsidian
    /// does not complete either.
    public static func closingCodeFence(typed: String, in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        guard typed == "`", selection.length == 0, selection.location >= 2, selection.location <= text.length else { return nil }
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        let beforeCursor = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        guard beforeCursor.hasSuffix("``") else { return nil }
        let prefix = String(beforeCursor.dropLast(2))
        guard prefix.allSatisfy({ character in character == " " || character == "\t" || character == ">" }) else { return nil }
        let afterCursor = text.substring(with: NSRange(location: selection.location, length: contentsEnd - selection.location))
        guard afterCursor.allSatisfy({ character in character == " " || character == "\t" }) else { return nil }
        // Inside code or the properties, the fence being typed closes a block instead of opening one.
        guard codeQuoteDepth(lineStart: lineStart, in: text) == nil, !leavesAFenceOpen(text, from: lineEnd) else { return nil }
        let lineBreak = lineBreakForNewLine(lineStart: lineStart, lineEnd: lineEnd, contentsEnd: contentsEnd, in: text)
        return MarkdownTextEdit(range: NSRange(location: selection.location, length: contentsEnd - selection.location),
                                replacement: typed + lineBreak + prefix + "```",
                                selectionAfter: NSRange(location: selection.location + 1, length: 0))
    }

    /// Whether the lines from `start` on, read by themselves, leave a fence open: then one of
    /// the fences below has no partner, and it is taken as the typed fence's closing one.
    /// Whole blocks below, such as a ```` ```js ```` block, pair among themselves.
    private static func leavesAFenceOpen(_ text: NSString, from start: Int) -> Bool {
        var tracker = CodeFenceTracker()
        var location = start
        while location < text.length {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            _ = tracker.isCodeLine(quotedLine: text.substring(with: NSRange(location: location, length: contentsEnd - location)))
            location = lineEnd
        }
        return tracker.isInsideFence
    }
}
