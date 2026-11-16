/**
 * File: MarkdownTableCopyingAndSorting.swift
 * ------------------------------------------
 * Layer: Core
 * Description: The table edits of Obsidian's cell menu that copy a row or a column and sort the rows by a column.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation

/// The order Sort by column puts the body rows in.
public enum MarkdownTableSortOrder: Sendable {
    /// A to Z, 1 to 10.
    case ascending
    /// Z to A, 10 to 1.
    case descending
}

extension MarkdownTableEditing {
    /// Inserts a copy of row `row` below it (row 0 is the header, whose copy becomes the first body
    /// row). The copy is the row's line as written, its indentation, padding and comments included,
    /// ended as the line above it is; no other line changes.
    public static func duplicatingRow(_ row: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), row >= 0, row <= layout.bodyRowCount else { return nil }
        let copiedUnits = Array(layout.units[layout.rowLine(row).contentRange])
        // The header's copy goes below the delimiter row, which is not a row of its own.
        let lineAbove = layout.lines[row == 0 ? 1 : row + 1]
        guard !lineAbove.endingRange.isEmpty else {
            // The table's last line has no line break: the break goes before the copy, so the
            // source still ends without one.
            let sourceEnd = lineAbove.contentRange.upperBound
            return layout.applying([MarkdownTableReplacement(range: sourceEnd..<sourceEnd, units: layout.lineEnding + copiedUnits)])
        }
        let insertionPoint = lineAbove.endingRange.upperBound
        let copiedLine = copiedUnits + Array(layout.units[lineAbove.endingRange])
        return layout.applying([MarkdownTableReplacement(range: insertionPoint..<insertionPoint, units: copiedLine)])
    }

    /// Inserts a copy of column `columnIndex` to its right: the header's text, the delimiter cell
    /// as written (so the alignment comes along) and each body row's text, each written with
    /// single spaces as an inserted column is. A row too short to reach the column stays as it is,
    /// since its missing cells already read as empty.
    public static func duplicatingColumn(at columnIndex: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), columnIndex >= 0, columnIndex < layout.columnCount else { return nil }
        var replacements: [MarkdownTableReplacement] = []
        for (lineIndex, line) in layout.lines.enumerated() where columnIndex < line.cells.count {
            let isHeaderOrDelimiter = lineIndex <= 1
            let cellText = layout.text(in: line.cells[columnIndex].textRange)
            // A body row's empty last cell needs nothing written: a missing cell reads as empty.
            if let replacement = insertionReplacement(cellText: cellText, atColumn: columnIndex + 1, in: line,
                                                      isRequired: isHeaderOrDelimiter || !cellText.isEmpty) {
                replacements.append(replacement)
            }
        }
        return layout.applying(replacements)
    }

    /// Orders the body rows by the text of their cell in column `columnIndex`, the header kept
    /// first. The comparison is the one Finder sorts names with: by the locale's rules, numbers
    /// by value ("row 2" before "row 10"), case, accents and width ignored. Rows read alike keep
    /// their order, and rows whose cell is empty, or missing, go last in both orders.
    ///
    /// Cells are compared by what the reader sees (`visibleSortText(ofCellSource:)`), not their
    /// Markdown. Each row's text moves with its own indentation and padding while every line
    /// break stays where it is, as `movingRow` moves rows; a source already in order comes back
    /// unchanged.
    public static func sortingRows(byColumn columnIndex: Int, _ order: MarkdownTableSortOrder, in source: String,
                                   locale: Locale = .current) -> String? {
        guard let layout = MarkdownTableLayout(source: source), columnIndex >= 0, columnIndex < layout.columnCount else { return nil }
        let sortTexts = (0..<layout.bodyRowCount).map { bodyRowIndex -> String in
            let line = layout.lines[bodyRowIndex + 2]
            guard columnIndex < line.cells.count else { return "" }
            return visibleSortText(ofCellSource: layout.text(in: line.cells[columnIndex].textRange))
        }
        let sortedRowIndices = sortTexts.indices.sorted { leftIndex, rightIndex in
            rowComesFirst(leftIndex, before: rightIndex, sortTexts: sortTexts, order: order, locale: locale)
        }
        var replacements: [MarkdownTableReplacement] = []
        for (position, sourceRowIndex) in sortedRowIndices.enumerated() where sourceRowIndex != position {
            let destinationLine = layout.lines[position + 2]
            let sourceLine = layout.lines[sourceRowIndex + 2]
            replacements.append(MarkdownTableReplacement(range: destinationLine.contentRange, units: Array(layout.units[sourceLine.contentRange])))
        }
        return replacements.isEmpty ? source : layout.applying(replacements)
    }

    /// Whether the row at `leftIndex` sorts before the one at `rightIndex`: a strict order over
    /// the rows, ties broken by their place, so the sort is stable whatever algorithm runs it.
    private static func rowComesFirst(_ leftIndex: Int, before rightIndex: Int, sortTexts: [String], order: MarkdownTableSortOrder,
                                      locale: Locale) -> Bool {
        let leftText = sortTexts[leftIndex]
        let rightText = sortTexts[rightIndex]
        switch (leftText.isEmpty, rightText.isEmpty) {
        case (true, true): return leftIndex < rightIndex
        case (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        let comparison = leftText.compare(rightText, options: naturalComparisonOptions, range: nil, locale: locale)
        switch (comparison, order) {
        case (.orderedSame, _): return leftIndex < rightIndex
        case (.orderedAscending, .ascending), (.orderedDescending, .descending): return true
        case (.orderedAscending, .descending), (.orderedDescending, .ascending): return false
        }
    }

    private static let naturalComparisonOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .numeric, .widthInsensitive]

    /// The text a cell shows, as far as sorting needs it: `%%` comments left out, a link read as
    /// what it shows (`[[note|alias]]` as `alias`, `[[note]]` as `note`, `[text](url)` as `text`),
    /// tags such as `<br>` read as a space, and the characters of emphasis, highlight, code and
    /// math (`*`, `_`, `~`, `==`, `` ` ``, `$`, `\`, `{`, `}`, `^`) dropped, so `**b**` sorts as
    /// `b` and `$C_{GD}$` as `CGD`. Spaces are trimmed and runs of them read as one.
    public static func visibleSortText(ofCellSource cellSource: String) -> String {
        let withoutComments = NSMutableString(string: cellSource)
        for commentRange in ObsidianComments.commentRanges(in: cellSource).reversed() {
            withoutComments.replaceCharacters(in: commentRange, with: " ")
        }
        var text = replacingLinks(in: withoutComments as String)
        text = htmlTagPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        text = text.replacingOccurrences(of: "==", with: "")
        text.removeAll { character in markupCharacters.contains(character) }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let markupCharacters: Set<Character> = ["*", "_", "~", "`", "$", "\\", "{", "}", "^"]
    private static let wikilinkPattern = MarkdownTableSortPattern.wikilink.compiled()
    private static let markdownLinkPattern = MarkdownTableSortPattern.markdownLink.compiled()
    private static let htmlTagPattern = MarkdownTableSortPattern.htmlTag.compiled()

    /// Each wikilink, embed and Markdown link replaced by the text it shows.
    private static func replacingLinks(in text: String) -> String {
        let shown = NSMutableString(string: text)
        for match in wikilinkPattern.matches(in: text, range: NSRange(location: 0, length: shown.length)).reversed() {
            let aliasRange = match.range(at: 2)
            let shownRange = aliasRange.location != NSNotFound ? aliasRange : match.range(at: 1)
            shown.replaceCharacters(in: match.range, with: (text as NSString).substring(with: shownRange))
        }
        let withoutWikilinks = shown as String
        return markdownLinkPattern.stringByReplacingMatches(in: withoutWikilinks, range: NSRange(location: 0, length: shown.length), withTemplate: "$1")
    }
}

/// The constant patterns of sorting by a column; `StaticPatternTests` compiles every case.
enum MarkdownTableSortPattern: String, StaticPatternSet {
    /// `[[target]]`, `[[target|alias]]` and their `![[…]]` embeds: group 1 the target, group 2 the alias.
    case wikilink = #"!?\[\[([^\]|]*)(?:\|([^\]]*))?\]\]"#
    /// `[text](destination)` and `![text](destination)`: group 1 the text.
    case markdownLink = #"!?\[([^\]]*)\]\([^)]*\)"#
    case htmlTag = #"<[^>]+>"#
}
