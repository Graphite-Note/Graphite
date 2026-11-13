/**
 * File: CalloutTables.swift
 * -------------------------
 * Layer: Core
 * Description: The tables of a callout's body, at any nesting depth, and their table edits made with the quote markers of
 *              their lines kept.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// A table in a callout's body, as Live Preview edits it in place.
public struct CalloutTable: Equatable, Sendable {
    /// Where each of the table's lines starts in the callout's source, past its quote markers:
    /// the offsets `NotePreviewDocument.LocatedBlock.lineStartOffsets` gives the body's lines.
    public let lineStartOffsets: [Int]
}

/// Finds a callout's tables in its reading-view blocks (`NotePreviewDocument.locatedBlocks`), so
/// the table drawn and the table edited are found by one walk, and runs `MarkdownTableEditing`'s
/// edits on a table's lines with their quote markers (`> `, `> > `, a callout in a list item's
/// indentation) taken off and put back on each line, new lines included.
public enum CalloutTables {
    /// A part of a Markdown run of a callout's body: a table, or the text between tables.
    public struct RunPiece: Equatable, Sendable {
        /// The run's lines the piece takes.
        public let lineRange: Range<Int>
        public let isTable: Bool
    }

    /// The lines of a run cut before and after each table. A table needs a header row and a
    /// delimiter row as `LivePreviewBlockScanner` finds tables in the note, and starts at the
    /// line's first column: a table indented in a list item is drawn in its item and stays text
    /// here. Fenced code holds no table.
    public static func pieces(ofRunLines lines: [String]) -> [RunPiece] {
        var pieces: [RunPiece] = []
        var fenceTracker = CodeFenceTracker()
        var textStart = 0
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if fenceTracker.isCodeLine(untrimmedLine: line) {
                lineIndex += 1
                continue
            }
            guard let lastIndex = lastLineOfTable(startingAt: lineIndex, in: lines) else {
                lineIndex += 1
                continue
            }
            if textStart < lineIndex { pieces.append(RunPiece(lineRange: textStart..<lineIndex, isTable: false)) }
            pieces.append(RunPiece(lineRange: lineIndex..<(lastIndex + 1), isTable: true))
            // The tracker follows list items too, so it reads every line.
            for rowIndex in (lineIndex + 1)...lastIndex { _ = fenceTracker.isCodeLine(untrimmedLine: lines[rowIndex]) }
            textStart = lastIndex + 1
            lineIndex = lastIndex + 1
        }
        if textStart < lines.count { pieces.append(RunPiece(lineRange: textStart..<lines.count, isTable: false)) }
        return pieces
    }

    /// The last line of the table whose header is `lines[headerIndex]`, or nil when no table starts there.
    private static func lastLineOfTable(startingAt headerIndex: Int, in lines: [String]) -> Int? {
        let header = lines[headerIndex]
        guard headerIndex + 1 < lines.count, let first = header.first, first != " ", first != "\t" else { return nil }
        let trimmedHeader = header.trimmingCharacters(in: .whitespaces)
        guard MarkdownTableSyntax.startsTable(header: trimmedHeader, delimiter: lines[headerIndex + 1]) else { return nil }
        let hasOuterPipes = trimmedHeader.hasPrefix("|")
        var lastIndex = headerIndex + 1
        while lastIndex + 1 < lines.count {
            let row = lines[lastIndex + 1].trimmingCharacters(in: .whitespaces)
            guard row.hasPrefix("|") || (!hasOuterPipes && !row.isEmpty && row.contains("|")) else { break }
            lastIndex += 1
        }
        return lastIndex
    }

    /// The tables of `callout`'s body in the order they are drawn, those of nested callouts included.
    public static func tables(in callout: NotePreviewDocument.LocatedBlock) -> [CalloutTable] {
        var tables: [CalloutTable] = []
        func collect(_ blocks: [NotePreviewDocument.LocatedBlock]) {
            for located in blocks {
                switch located.block {
                case .markdown(let markdown):
                    let lines = markdown.components(separatedBy: "\n")
                    guard lines.count == located.lineStartOffsets.count else { continue }
                    for piece in pieces(ofRunLines: lines) where piece.isTable {
                        tables.append(CalloutTable(lineStartOffsets: Array(located.lineStartOffsets[piece.lineRange])))
                    }
                case .callout:
                    collect(located.body)
                case .heading, .embed, .baseDefinition, .displayMath, .pluginCodeBlock, .mermaidDiagram, .webFrame:
                    continue
                }
            }
        }
        collect(callout.body)
        return tables
    }

    /// The callout that `source` (a callout's lines, as Live Preview cuts one out of its note) opens.
    public static func callout(in source: String) -> NotePreviewDocument.LocatedBlock? {
        guard let first = NotePreviewDocument.locatedBlocks(from: source,
            calloutContainerColumn: NotePreviewDocument.calloutContainerColumn(ofCutOutBlock: source)).first,
              case .callout = first.block else { return nil }
        return first
    }

    /// The table at `tableIndex` of the callout `source`, its lines without their quote markers
    /// and without the last line's break: what `MarkdownTableEditing` edits.
    public static func tableSource(at tableIndex: Int, inCallout source: String) -> String? {
        quotedTable(at: tableIndex, inCallout: source)?.unquotedSource
    }

    /// `source`, a callout's lines as the note has them, with its table at `tableIndex` changed
    /// by `edit`, which is given the table's lines without their quote markers (`tableSource`).
    /// Each line of the result keeps its own markers; a line the edit adds takes those of the
    /// table's line above it (a marked one, never a lazy continuation's nothing). Nil when there
    /// is no such table, its lines are not one after another, or `edit` changes nothing.
    public static func editingTable(at tableIndex: Int, inCallout source: String, using edit: (String) -> String?) -> String? {
        guard let table = quotedTable(at: tableIndex, inCallout: source), let edited = edit(table.unquotedSource) else { return nil }
        var editedLines = edited.components(separatedBy: "\n")
        // The table is given without its last line's break; an edit that ends with one adds no line.
        if editedLines.count > 1, editedLines.last == "" { editedLines.removeLast() }
        if table.lastLineEndsWithCarriageReturn, let last = editedLines.popLast() { editedLines.append(last + "\r") }
        let prefixes = linePrefixes(for: editedLines, editing: table.contentsAsWritten, prefixedWith: table.prefixes)
        var lines = table.sourceLines
        lines.replaceSubrange(table.lineIndices, with: zip(prefixes, editedLines).map { prefix, line in prefix + line })
        let result = lines.joined(separator: "\n")
        return result == source ? nil : result
    }

    /// The quote markers for each line of an edit's result. With as many lines as before, each
    /// keeps its place's markers (a cell, a column or a sort changes lines in place). Otherwise the
    /// lines equal at the start and at the end keep theirs, and those between take the markers of
    /// the line above them.
    static func linePrefixes(for editedLines: [String], editing originalLines: [String], prefixedWith prefixes: [String]) -> [String] {
        guard editedLines.count != originalLines.count else { return prefixes }
        let commonStart = zip(editedLines, originalLines).prefix { editedLine, originalLine in editedLine == originalLine }.count
        let longestEnd = min(editedLines.count, originalLines.count) - commonStart
        let commonEnd = zip(editedLines.reversed(), originalLines.reversed()).prefix(longestEnd).prefix { editedLine, originalLine in
            editedLine == originalLine
        }.count
        let insertedCount = editedLines.count - commonStart - commonEnd
        let markedAbove = prefixes[..<commonStart].last { prefix in prefix.contains(">") }
        let insertedPrefix = markedAbove ?? prefixes.first { prefix in prefix.contains(">") } ?? prefixes.first ?? ""
        return Array(prefixes[..<commonStart]) + Array(repeating: insertedPrefix, count: max(0, insertedCount))
            + Array(prefixes[(prefixes.count - commonEnd)...])
    }

    /// A table of a callout's source, split into its lines' quote markers and contents.
    private struct QuotedTable {
        /// The callout's source, split at its line feeds.
        let sourceLines: [String]
        /// The table's lines among `sourceLines`.
        let lineIndices: ClosedRange<Int>
        let prefixes: [String]
        /// What follows each line's markers, line endings as written but the last line's `\r`.
        let contents: [String]
        let lastLineEndsWithCarriageReturn: Bool

        var unquotedSource: String { contents.joined(separator: "\n") }
        /// `contents` with the last line's `\r` back.
        var contentsAsWritten: [String] {
            guard lastLineEndsWithCarriageReturn, let last = contents.last else { return contents }
            return contents.dropLast() + [last + "\r"]
        }
    }

    private static func quotedTable(at tableIndex: Int, inCallout source: String) -> QuotedTable? {
        guard let callout = callout(in: source) else { return nil }
        let tables = tables(in: callout)
        guard tables.indices.contains(tableIndex) else { return nil }
        let sourceLines = source.components(separatedBy: "\n")
        var lineStarts: [Int] = []
        var lineStart = 0
        for line in sourceLines {
            lineStarts.append(lineStart)
            lineStart += line.utf16.count + 1
        }
        var lineIndices: [Int] = []
        var prefixes: [String] = []
        var contents: [String] = []
        for offset in tables[tableIndex].lineStartOffsets {
            guard let lineIndex = lineStarts.lastIndex(where: { start in start <= offset }),
                  offset - lineStarts[lineIndex] <= sourceLines[lineIndex].utf16.count else { return nil }
            let line = sourceLines[lineIndex] as NSString
            let markerLength = offset - lineStarts[lineIndex]
            lineIndices.append(lineIndex)
            prefixes.append(line.substring(to: markerLength))
            contents.append(line.substring(from: markerLength))
        }
        // A `%%` comment that took a line break would join lines: such a table is not edited here.
        guard let firstIndex = lineIndices.first, let lastIndex = lineIndices.last,
              lineIndices == Array(firstIndex...lastIndex) else { return nil }
        let lastLineEndsWithCarriageReturn = contents[contents.count - 1].hasSuffix("\r")
        if lastLineEndsWithCarriageReturn { contents[contents.count - 1].removeLast() }
        return QuotedTable(sourceLines: sourceLines, lineIndices: firstIndex...lastIndex, prefixes: prefixes, contents: contents,
                           lastLineEndsWithCarriageReturn: lastLineEndsWithCarriageReturn)
    }
}
