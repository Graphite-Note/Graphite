/**
 * File: MarkdownNewLineIndentation.swift
 * --------------------------------------
 * Layer: Core
 * Description: Return keeps the line's indentation, Shift-Return breaks an item's line without a new item, Backspace removes a level, as in Obsidian.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

extension MarkdownEditing {
    /// Return on a line that starts with spaces or tabs: the new line starts with the same
    /// indentation, as Obsidian's editor gives it in code blocks and in indented text. In a
    /// code block inside a quote or callout, the new line also keeps the quote markers that
    /// hold the code, so the block stays in its callout; a `>` written in the code itself, as
    /// in `>>> print(1)`, is code and is not repeated.
    ///
    /// Meant for when `continuingList` gave no edit: lists and quotes outside code continue
    /// there. Nil when the line has no indentation to keep, or when the cursor is inside it.
    public static func newLineKeepingIndentation(in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        guard NSMaxRange(selection) <= text.length else { return nil }
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        guard NSMaxRange(selection) <= contentsEnd else { return nil }
        let line = text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        let quoteDepth = codeQuoteDepth(lineStart: lineStart, in: text) ?? 0
        let afterQuote = MarkdownQuoteSyntax.markersRemoved(from: line, maximumDepth: quoteDepth).content
        let quotePrefix = String(line.utf16.prefix(line.utf16.count - afterQuote.utf16.count)) ?? ""
        let indentation = String(afterQuote.prefix { character in character == " " || character == "\t" })
        let prefix = quotePrefix + indentation
        guard !prefix.isEmpty, selection.location - lineStart >= prefix.utf16.count else { return nil }
        let replacement = lineBreakForNewLine(lineStart: lineStart, lineEnd: lineEnd, contentsEnd: contentsEnd, in: text) + prefix
        return MarkdownTextEdit(range: selection, replacement: replacement,
                                selectionAfter: NSRange(location: selection.location + replacement.utf16.count, length: 0))
    }

    /// Shift-Return, as Obsidian's Shift-Enter: a line break that starts no new list item.
    /// In a list item the new line is indented to the item's text, so it is the item's next
    /// line; in a quote or callout it keeps the `>` markers; in code it keeps the indentation.
    /// Elsewhere it is an ordinary line break, never a Unicode line separator, which the Mac
    /// writes for Control-Return and no Markdown reader takes as a new line.
    public static func breakingLineWithinItem(in text: NSString, selection: NSRange) -> MarkdownTextEdit {
        let location = min(max(selection.location, 0), text.length)
        let range = NSRange(location: location, length: min(max(selection.length, 0), text.length - location))
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let lineBreak = lineBreakForNewLine(lineStart: lineStart, lineEnd: lineEnd, contentsEnd: contentsEnd, in: text)
        var prefix = ""
        if codeQuoteDepth(lineStart: lineStart, in: text) != nil {
            if let kept = newLineKeepingIndentation(in: text, selection: range) { return kept }
        } else if let listLine = MarkdownListSyntax.listLine(text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))),
                  location - lineStart >= listLine.prefixLength {
            // The item's text starts after its marker and spacing; a tab stays a tab.
            let markerWidth = (listLine.marker + listLine.spacing).map { character in character == "\t" ? "\t" : " " }.joined()
            prefix = listLine.quotePrefix + (listLine.isListItem ? listLine.indentation + markerWidth : "")
        }
        let replacement = lineBreak + prefix
        return MarkdownTextEdit(range: range, replacement: replacement, selectionAfter: NSRange(location: location + replacement.utf16.count, length: 0))
    }

    /// Backspace in a line's leading spaces, in a vault that indents with spaces: it deletes
    /// back to the previous indentation level, as Obsidian's editor (CodeMirror) does, instead
    /// of one space of the four. Nil elsewhere: after text, after a tab, with a selection, or
    /// when the vault indents with tabs.
    public static func deletingIndentation(in text: NSString, selection: NSRange, indentUnit: String) -> MarkdownTextEdit? {
        guard selection.length == 0, selection.location > 0, selection.location <= text.length,
              !indentUnit.isEmpty, indentUnit.allSatisfy({ character in character == " " }) else { return nil }
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let beforeCursor = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        guard !beforeCursor.isEmpty, beforeCursor.allSatisfy({ character in character == " " }) else { return nil }
        let levelWidth = indentUnit.count
        let remainder = beforeCursor.count % levelWidth
        let deletedCount = remainder == 0 ? levelWidth : remainder
        let deletedRange = NSRange(location: selection.location - deletedCount, length: deletedCount)
        return MarkdownTextEdit(range: deletedRange, replacement: "", selectionAfter: NSRange(location: deletedRange.location, length: 0))
    }
}
