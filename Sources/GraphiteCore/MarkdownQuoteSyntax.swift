/**
 * File: MarkdownQuoteSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Block quote markers, callout headers and where a callout's body ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 01/11/2026
 */

import Foundation

/// Block quote markers and callout headers, read one line at a time.
public enum MarkdownQuoteSyntax {
    private static let calloutHeaderPattern = MarkdownQuoteSyntaxPattern.calloutHeader.compiled()

    /// The line after up to `maximumDepth` `>` quote markers, as CommonMark reads them: each
    /// with up to three spaces before it and one optional space or tab after it. Returns how
    /// many there were and the rest of the line as written.
    static func markersRemoved(from line: String, maximumDepth: Int = .max) -> (depth: Int, content: String) {
        let (depth, content) = markersRemoved(from: Substring(line), maximumDepth: maximumDepth)
        return (depth, String(content))
    }

    /// `markersRemoved(from:maximumDepth:)` without copying the line, for walks that read
    /// every line of a note.
    static func markersRemoved(from line: Substring, maximumDepth: Int = .max) -> (depth: Int, content: Substring) {
        // Most lines start with neither a space nor a marker.
        guard let firstByte = line.utf8.first, firstByte == UInt8(ascii: " ") || firstByte == UInt8(ascii: ">") else { return (0, line) }
        var remaining = line
        var depth = 0
        while depth < maximumDepth {
            let indentation = remaining.prefix { character in character == " " }
            guard indentation.count <= 3, remaining.dropFirst(indentation.count).first == ">" else { break }
            remaining = remaining.dropFirst(indentation.count + 1)
            if remaining.first == " " || remaining.first == "\t" { remaining = remaining.dropFirst() }
            depth += 1
        }
        return (depth, remaining)
    }

    /// Up to `maximumDepth` leading quote markers and the trimmed text after them, as the
    /// editor's block walk reads a line for fences and `$$`: the line is trimmed first, so
    /// a marker may follow any indentation, and every space after a marker is skipped.
    static func markersAndTrimmedContent(of line: String, maximumDepth: Int) -> (depth: Int, content: String) {
        var remainder = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))
        var depth = 0
        while depth < maximumDepth && remainder.hasPrefix(">") {
            remainder = remainder.dropFirst().drop { character in character == " " }
            depth += 1
        }
        return (depth, String(remainder))
    }

    /// The callout that `line` opens (`> [!type]` with an optional `-` or `+` and title): its
    /// type lowercased, its title (the type, capitalized, when none is written) and whether
    /// it starts folded. As any block, a callout may be indented up to three columns past
    /// the content of the list item that holds it (`containerColumn`, 0 outside lists).
    static func calloutHeader(in line: String, containerColumn: Int = 0) -> (type: String, title: String, folding: CalloutFolding)? {
        guard ListItemContainers.leadingColumns(of: line) <= containerColumn + 3,
              let match = calloutHeaderPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let source = line as NSString
        let type = source.substring(with: match.range(at: 1)).lowercased()
        let foldMarker = source.substring(with: match.range(at: 2))
        let writtenTitle = source.substring(with: match.range(at: 3))
        let title = writtenTitle.isEmpty ? type.prefix(1).uppercased() + type.dropFirst() : writtenTitle
        return (type, title, foldMarker == "-" ? .collapsed : foldMarker == "+" ? .expanded : .notFoldable)
    }

    /// Whether `line` opens a callout, without reading its type and title.
    static func isCalloutHeader(_ line: String, containerColumn: Int = 0) -> Bool {
        ListItemContainers.leadingColumns(of: line) <= containerColumn + 3
            && calloutHeaderPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// A line of a callout's body without its quote marker (and the one space after it), and
    /// how many UTF-16 units that took. A line without a marker is a lazy continuation of
    /// the paragraph above it, which is the callout's text as written.
    static func calloutBodyLine(_ line: String, containerColumn: Int = 0) -> (content: String, markerLength: Int) {
        guard ListItemContainers.leadingColumns(of: line) <= containerColumn + 3 else { return (line, 0) }
        var remaining = Substring(line)
        var markerLength = 0
        let indentation = remaining.prefix { character in character == " " || character == "\t" }
        remaining = remaining.dropFirst(indentation.count)
        guard remaining.first == ">" else { return (line, 0) }
        remaining = remaining.dropFirst()
        markerLength = indentation.utf16.count + 1
        if remaining.first == " " { remaining = remaining.dropFirst(); markerLength += 1 }
        return (String(remaining), markerLength)
    }

    /// How many lines under the callout header at `headerIndex` are its body: the lines
    /// that carry a quote marker, and a line without one that continues the paragraph above
    /// it, as Markdown continues a quote (`> text` over `more text`). Blank lines, fences,
    /// headings, lists and other blocks end the body. Reading view and Live Preview both
    /// find a callout's end here.
    static func calloutBodyLineCount(afterHeaderAt headerIndex: Int, lineCount: Int, containerColumn: Int = 0, line lineAt: (Int) -> String) -> Int {
        var fenceTracker = CodeFenceTracker()
        var isInsideDisplayMath = false
        var previousLineIsParagraphText = false
        var bodyLineCount = 0
        while headerIndex + 1 + bodyLineCount < lineCount {
            let line = lineAt(headerIndex + 1 + bodyLineCount)
            let body = calloutBodyLine(line, containerColumn: containerColumn)
            if body.markerLength == 0 {
                guard previousLineIsParagraphText, NoteBlocks.continuesTextLazily(line) else { break }
                bodyLineCount += 1
                continue
            }
            let isFencedCode = fenceTracker.isCodeLine(untrimmedLine: body.content)
            let trimmedContent = body.content.trimmingCharacters(in: .whitespaces)
            if trimmedContent.hasPrefix("$$") && !(trimmedContent.count > 2 && trimmedContent.hasSuffix("$$")) { isInsideDisplayMath.toggle() }
            previousLineIsParagraphText = !isFencedCode && !isInsideDisplayMath && !trimmedContent.isEmpty && !trimmedContent.hasPrefix("$$")
                && !trimmedContent.hasPrefix("|") && MarkdownHeadingSyntax.level(of: body.content) == nil && !MarkdownListSyntax.isThematicBreak(body.content)
            bodyLineCount += 1
        }
        return bodyLineCount
    }
}

/// The constant patterns of `MarkdownQuoteSyntax`; `StaticPatternTests` compiles every case.
enum MarkdownQuoteSyntaxPattern: String, StaticPatternSet {
    case calloutHeader = #"^[ \t]*>[ \t]?\[!([A-Za-z0-9_-]+)\]([+-]?)[ \t]*(.*)$"#
}
