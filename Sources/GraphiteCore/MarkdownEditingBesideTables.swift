/**
 * File: MarkdownEditingBesideTables.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Typing on the line right after a table, as Obsidian's Live Preview does: text never joins the table, and Backspace selects it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation

extension MarkdownEditing {
    /// The edit Obsidian makes for a key typed at the start of an empty line right after a
    /// table: a character goes on a new line, after an empty one, since a line right after a
    /// table's last row would be read as a row of it; Backspace, which would join the line to
    /// the table's last row, selects the table instead (a second Backspace deletes it). Nil
    /// anywhere else, and for Return.
    public static func editBesideTable(typed replacement: String, replacing range: NSRange, in text: NSString) -> MarkdownTextEdit? {
        let caret = replacement.isEmpty ? NSMaxRange(range) : range.location
        guard replacement.isEmpty ? range.length == 1 : range.length == 0, !replacement.contains(where: \.isNewline),
              caret > 0, caret <= text.length else { return nil }
        // The caret starts an empty line.
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        guard line.location == caret, text.substring(with: line).trimmingCharacters(in: .newlines).isEmpty,
              let tableRange = tableEnding(atLineBreakBefore: caret, in: text) else { return nil }
        if replacement.isEmpty {
            return MarkdownTextEdit(range: NSRange(location: caret, length: 0), replacement: "", selectionAfter: tableRange)
        }
        let inserted = "\n" + replacement
        return MarkdownTextEdit(range: range, replacement: inserted, selectionAfter: NSRange(location: caret + (inserted as NSString).length, length: 0))
    }

    /// The table whose last row ends right before the line break before `location`, without that
    /// line break; nil when the line before is not a table's last row.
    static func tableEnding(atLineBreakBefore location: Int, in text: NSString) -> NSRange? {
        var lineStart = text.lineRange(for: NSRange(location: location - 1, length: 0)).location
        let tableEnd = location - (location >= 2 && text.substring(with: NSRange(location: location - 2, length: 2)) == "\r\n" ? 2 : 1)
        guard tableEnd > lineStart else { return nil }
        // Up through the lines without a blank one, as far as a table could reach.
        var tableStart = lineStart
        while lineStart > 0 {
            let previousLine = text.lineRange(for: NSRange(location: lineStart - 1, length: 0))
            guard !text.substring(with: previousLine).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            tableStart = previousLine.location
            lineStart = previousLine.location
        }
        // The table starts at the first of those lines that begins one reaching the end.
        var candidate = tableStart
        while candidate < tableEnd {
            let candidateRange = NSRange(location: candidate, length: tableEnd - candidate)
            if let table = MarkdownTable.parse(text.substring(with: candidateRange)),
               table.rows.count + 1 == text.substring(with: candidateRange).components(separatedBy: .newlines).filter({ !$0.isEmpty }).count {
                return candidateRange
            }
            candidate = NSMaxRange(text.lineRange(for: NSRange(location: candidate, length: 0)))
        }
        return nil
    }
}
