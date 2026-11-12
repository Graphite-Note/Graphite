/**
 * File: MarkdownTableEmptyRows.swift
 * ----------------------------------
 * Layer: Core
 * Description: Keeps a table row whose cells are all empty when Markdown is drawn: one of its spaces becomes a
 *              no-break space, so the parser gives the row a run and the row is drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// Foundation's Markdown parser gives a table cell with nothing in it no run of text, so a
/// row of empty cells has none either; drawn from the runs, such a row after the last one with
/// text vanished. Obsidian draws it as a row of empty cells, and Live Preview's "+" strip adds
/// exactly such a row (`|  |  |`), which was not drawn until something was typed (HUNT-329).
///
/// The row keeps its length: one space of its first cell becomes U+00A0, which the parser does
/// not trim, so every offset after it stays where the source has it.
public enum MarkdownTableEmptyRows {
    static let noBreakSpace: unichar = 0x00A0
    private static let space: unichar = 0x20
    private static let pipe: unichar = 0x7C

    /// `markdown` with every all-empty row of its tables given a no-break space; the text
    /// itself when it has none, which is most notes.
    public static func keepingEmptyRows(in markdown: String) -> String {
        guard markdown.contains("|") else { return markdown }
        let text = NSMutableString(string: markdown)
        var lineRanges: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            lineRanges.append(lineRange)
        }
        var lineIndex = 0
        var changed = false
        while lineIndex + 1 < lineRanges.count {
            let header = rowContent(text.substring(with: lineRanges[lineIndex]))
            guard MarkdownTableSyntax.startsTable(header: header.trimmingCharacters(in: .whitespaces),
                                                  delimiter: rowContent(text.substring(with: lineRanges[lineIndex + 1]))) else {
                lineIndex += 1
                continue
            }
            let hasOuterPipes = header.trimmingCharacters(in: .whitespaces).hasPrefix("|")
            var rowIndex = lineIndex + 2
            while rowIndex < lineRanges.count {
                let line = text.substring(with: lineRanges[rowIndex])
                let row = rowContent(line).trimmingCharacters(in: .whitespaces)
                guard row.hasPrefix("|") || (!hasOuterPipes && !row.isEmpty && row.contains("|")) else { break }
                if let spaceOffset = spaceToKeep(inRow: line) {
                    text.replaceCharacters(in: NSRange(location: lineRanges[rowIndex].location + spaceOffset, length: 1),
                                           with: String(utf16CodeUnits: [noBreakSpace], count: 1))
                    changed = true
                }
                rowIndex += 1
            }
            lineIndex = rowIndex
        }
        return changed ? text as String : markdown
    }

    /// The row as its table reads it: without the `>` of the quotes or callouts it is in.
    private static func rowContent(_ line: String) -> String {
        var content = Substring(line)
        while let first = content.first(where: { character in character != " " && character != "\t" }), first == ">" {
            content = content.drop { character in character == " " || character == "\t" }.dropFirst()
        }
        return String(content)
    }

    /// Where, in `line`, the space that becomes a no-break space is: the first space of the
    /// first cell of a row whose cells hold nothing but spaces. Nil for a row with text, and
    /// for one with no space to give (`|||`).
    private static func spaceToKeep(inRow line: String) -> Int? {
        let units = Array(line.utf16)
        let contentStart = units.count - rowContent(line).utf16.count
        var position = contentStart
        while position < units.count, units[position] == space || units[position] == 0x09 { position += 1 }
        let cellsStart = position < units.count && units[position] == pipe ? position + 1 : contentStart
        var firstSpace: Int?
        for offset in contentStart..<units.count {
            let unit = units[offset]
            if unit == pipe || unit == 0x09 || unit == 0x0A || unit == 0x0D { continue }
            guard unit == space else { return nil }
            if firstSpace == nil, offset >= cellsStart { firstSpace = offset }
        }
        return firstSpace
    }
}
