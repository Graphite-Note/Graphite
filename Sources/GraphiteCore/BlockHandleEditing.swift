/**
 * File: BlockHandleEditing.swift
 * ------------------------------
 * Layer: Core
 * Description: The blocks a block handle acts on (a heading with its section, a list item with its nested items, a
 *              paragraph, a quote or callout, a table, code, math or a rule), and the edits that move, duplicate,
 *              delete or turn one into another kind, as Markdown only.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

import Foundation

/// A block of a note that a handle shows beside, drags and turns into another kind.
public struct HandleBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph, listItem, heading(level: Int), quote, callout, table, code, math, rule

        /// Paragraphs and list items turn into headings, quotes, callouts and tasks; a heading
        /// changes its level or becomes body text; the others keep their kind.
        public var turnsIntoOtherKinds: Bool {
            switch self {
            case .paragraph, .listItem, .heading: true
            case .quote, .callout, .table, .code, .math, .rule: false
            }
        }
    }

    public let kind: Kind
    /// From the start of the block's first line to the end of its last line's text, without
    /// the line break: a heading's covers its section, as folding knows it, without the blank
    /// lines before the next heading, and a list item's its nested items.
    public let range: NSRange

    public init(kind: Kind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// The rules of block handles (Docs/Slash-menu-and-block-handles-todo.md, sections 2 and 3),
/// the same on the Mac and the iPad.
public enum BlockHandleEditing {
    /// Every block a handle can act on, in the order of their first lines; a heading's section
    /// holds the blocks under it, which are listed too.
    public static func blocks(in text: String) -> [HandleBlock] {
        let source = text as NSString
        var blocks: [HandleBlock] = []
        for noteBlock in NoteBlocks.blocks(in: text) {
            switch noteBlock.kind {
            case .list: continue
            case .listItem: blocks.append(HandleBlock(kind: .listItem, range: withNestedLines(noteBlock.range, in: source)))
            case .paragraph: blocks.append(HandleBlock(kind: .paragraph, range: noteBlock.range))
            case .table: blocks.append(HandleBlock(kind: .table, range: noteBlock.range))
            case .code: blocks.append(HandleBlock(kind: .code, range: noteBlock.range))
            case .math: blocks.append(HandleBlock(kind: .math, range: noteBlock.range))
            case .quote:
                blocks.append(HandleBlock(kind: isCallout(noteBlock.text) ? .callout : .quote, range: noteBlock.range))
            }
        }
        blocks += headingsAndRules(in: source)
        return blocks.sorted { leftBlock, rightBlock in
            leftBlock.range.location != rightBlock.range.location
                ? leftBlock.range.location < rightBlock.range.location : leftBlock.range.length > rightBlock.range.length
        }
    }

    /// The innermost block holding `location`: a paragraph under a heading rather than the
    /// heading's section, a nested list item rather than the item it is nested in.
    public static func block(at location: Int, in blocks: [HandleBlock]) -> HandleBlock? {
        blocks.filter { block in block.range.location <= location && location <= NSMaxRange(block.range) }
            .min { leftBlock, rightBlock in leftBlock.range.length < rightBlock.range.length }
    }

    /// Where a dragged block can go: before any block that is not inside it, or at the end of
    /// the note. Dropping at its own place, or just after itself, changes nothing.
    public static func destinations(for block: HandleBlock, in blocks: [HandleBlock], textLength: Int) -> [Int] {
        let starts = Set(blocks.map(\.range.location)).union([textLength])
        return starts.filter { start in start < block.range.location || start > NSMaxRange(block.range) }.sorted()
    }

    // MARK: Moving

    /// Moves `block` so it starts at `destination` (the start of another block, or the end of
    /// the note), with the blank lines that set it apart, as one edit whose selection is the
    /// moved block's start. Nil when the move changes nothing.
    public static func moving(_ block: HandleBlock, to destination: Int, in text: NSString) -> MarkdownTextEdit? {
        guard destination >= 0, destination <= text.length, NSMaxRange(block.range) <= text.length,
              destination < block.range.location || destination > NSMaxRange(block.range) else { return nil }
        let unit = movingUnit(of: block, in: text)
        let remaining = text.replacingCharacters(in: unit.range, with: "") as NSString
        let shiftedDestination = destination > unit.range.location ? destination - unit.range.length : destination
        let lineBreak = lineBreak(of: text)
        let movedText: String
        if shiftedDestination >= remaining.length {
            // At the end: the note's text up to its last block, the separation, the block, then
            // the line breaks and blank lines the note ended with.
            let core = trimmed(NSRange(location: 0, length: remaining.length), in: remaining)
            let lead = core.length == 0 ? "" : lineBreak + unit.separator
            let ending = text.substring(from: NSMaxRange(trimmed(NSRange(location: 0, length: text.length), in: text)))
            let result = remaining.substring(to: core.length) + lead + unit.blockText + ending
            return smallestEdit(from: text, to: result as NSString, selectionAfter: NSRange(location: core.length + lead.utf16.count, length: 0))
        } else {
            movedText = unit.blockText + lineBreak + unit.separator
        }
        let result = remaining.replacingCharacters(in: NSRange(location: min(shiftedDestination, remaining.length), length: 0), with: movedText) as NSString
        return smallestEdit(from: text, to: result, selectionAfter: NSRange(location: shiftedDestination, length: 0))
    }

    /// What a move takes out of the note and puts back: the block's lines and the blank lines
    /// after it, or before it when none follow (the note's last block, or one before a list).
    private static func movingUnit(of block: HandleBlock, in text: NSString) -> (range: NSRange, blockText: String, separator: String) {
        let blockText = text.substring(with: block.range)
        let blockLines = text.lineRange(for: block.range)
        let blockEnd = NSMaxRange(blockLines)
        let followingBlanksEnd = endOfBlankLines(from: blockEnd, in: text)
        if followingBlanksEnd > blockEnd {
            return (NSRange(location: block.range.location, length: followingBlanksEnd - block.range.location), blockText,
                    text.substring(with: NSRange(location: blockEnd, length: followingBlanksEnd - blockEnd)))
        }
        let precedingBlanksStart = startOfBlankLines(before: block.range.location, in: text)
        let hasLineBreak = blockEnd > NSMaxRange(block.range)
        if precedingBlanksStart < block.range.location {
            let separator = text.substring(with: NSRange(location: precedingBlanksStart, length: block.range.location - precedingBlanksStart))
            // The note's last line without a line break: the break before the blank lines goes
            // too, so the note still ends without one.
            let lineBeforeBlanks = text.lineRange(for: NSRange(location: precedingBlanksStart - 1, length: 0))
            let start = hasLineBreak ? precedingBlanksStart : contentEnd(of: lineBeforeBlanks, in: text)
            return (NSRange(location: start, length: blockEnd - start), blockText, separator)
        }
        guard !hasLineBreak, block.range.location > 0 else {
            return (NSRange(location: block.range.location, length: blockEnd - block.range.location), blockText, "")
        }
        // The note's last line without a line break: the break before it goes with it.
        let previousLine = text.lineRange(for: NSRange(location: block.range.location - 1, length: 0))
        let previousContentEnd = contentEnd(of: previousLine, in: text)
        return (NSRange(location: previousContentEnd, length: blockEnd - previousContentEnd), blockText, "")
    }

    // MARK: Duplicating, deleting, callouts

    /// A copy of the block right after it, with the same separation, the cursor at the copy.
    public static func duplicating(_ block: HandleBlock, in text: NSString) -> MarkdownTextEdit {
        let lineBreak = lineBreak(of: text)
        let separation = isSeparatedByBlankLines(block, in: text) ? lineBreak + lineBreak : lineBreak
        let copy = separation + text.substring(with: block.range)
        let end = NSMaxRange(block.range)
        return MarkdownTextEdit(range: NSRange(location: end, length: 0), replacement: copy,
                                selectionAfter: NSRange(location: end + separation.utf16.count, length: 0))
    }

    /// Takes the block out with the blank lines that set it apart, the cursor where it was.
    public static func deleting(_ block: HandleBlock, in text: NSString) -> MarkdownTextEdit {
        let unit = movingUnit(of: block, in: text)
        let cursor = min(unit.range.location, text.length - unit.range.length)
        return MarkdownTextEdit(range: unit.range, replacement: "", selectionAfter: NSRange(location: cursor, length: 0))
    }

    /// Makes the block's lines a note callout, as Obsidian writes one: `> [!note]` above them,
    /// each line quoted.
    public static func turningIntoCallout(_ block: HandleBlock, in text: NSString) -> MarkdownTextEdit {
        let lineBreak = lineBreak(of: text)
        let lines = text.substring(with: block.range).components(separatedBy: lineBreak)
        let callout = (["> [!note]"] + lines.map { line in line.isEmpty ? ">" : "> " + line }).joined(separator: lineBreak)
        return MarkdownTextEdit(range: block.range, replacement: callout,
                                selectionAfter: NSRange(location: block.range.location + callout.utf16.count, length: 0))
    }

    // MARK: Lines

    /// Whether a quote's first line opens a callout, `> [!type]`.
    private static func isCallout(_ quoteText: String) -> Bool {
        let firstLine = quoteText.prefix { character in !character.isNewline }
        return firstLine.drop { character in character == ">" || character == " " || character == "\t" }.hasPrefix("[!")
    }

    /// Headings with their sections, as folding finds them, and thematic breaks, outside code.
    private static func headingsAndRules(in source: NSString) -> [HandleBlock] {
        var blocks: [HandleBlock] = []
        var fences = CodeFenceTracker()
        var headingStarts: [(location: Int, level: Int)] = []
        var location = FrontmatterLocator.length(in: source)
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let content = source.substring(with: NSRange(location: location, length: contentEnd(of: lineRange, in: source) - location))
            if !fences.isCodeLine(untrimmedLine: content) {
                if let level = MarkdownHeadingSyntax.level(of: content) {
                    headingStarts.append((location, level))
                } else if MarkdownListSyntax.isThematicBreak(content), !content.hasPrefix(" ") {
                    blocks.append(HandleBlock(kind: .rule, range: NSRange(location: location, length: content.utf16.count)))
                }
            }
            location = NSMaxRange(lineRange)
        }
        for (position, heading) in headingStarts.enumerated() {
            // The section ends before the next heading of the same or a higher level.
            let sectionEnd = headingStarts[(position + 1)...].first { next in next.level <= heading.level }?.location ?? source.length
            let section = trimmed(NSRange(location: heading.location, length: sectionEnd - heading.location), in: source)
            blocks.append(HandleBlock(kind: .heading(level: heading.level), range: section))
        }
        return blocks
    }

    /// A list item's lines with the lines nested under it: those indented deeper than its
    /// marker, blank lines between them included.
    private static func withNestedLines(_ itemRange: NSRange, in text: NSString) -> NSRange {
        let itemColumns = ListItemContainers.leadingColumns(of: text.substring(with: text.lineRange(for: NSRange(location: itemRange.location, length: 0))))
        var end = NSMaxRange(itemRange)
        var location = NSMaxRange(text.lineRange(for: NSRange(location: max(NSMaxRange(itemRange) - 1, itemRange.location), length: 0)))
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let line = text.substring(with: lineRange)
            if !isBlank(lineRange, in: text) {
                guard ListItemContainers.leadingColumns(of: line) > itemColumns else { break }
                end = contentEnd(of: lineRange, in: text)
            }
            location = NSMaxRange(lineRange)
        }
        return NSRange(location: itemRange.location, length: end - itemRange.location)
    }

    /// `range` without the line breaks and blank lines at its end.
    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(range)
        while end > range.location, let scalar = Unicode.Scalar(text.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            end -= 1
        }
        return NSRange(location: range.location, length: end - range.location)
    }

    private static func isSeparatedByBlankLines(_ block: HandleBlock, in text: NSString) -> Bool {
        let blockEnd = NSMaxRange(text.lineRange(for: block.range))
        return endOfBlankLines(from: blockEnd, in: text) > blockEnd || startOfBlankLines(before: block.range.location, in: text) < block.range.location
    }

    /// Where the blank lines starting at `location` (a line start) end.
    private static func endOfBlankLines(from location: Int, in text: NSString) -> Int {
        var end = location
        while end < text.length {
            let lineRange = text.lineRange(for: NSRange(location: end, length: 0))
            guard isBlank(lineRange, in: text) else { break }
            end = NSMaxRange(lineRange)
        }
        return end
    }

    /// Where the blank lines right before the line starting at `location` start.
    private static func startOfBlankLines(before location: Int, in text: NSString) -> Int {
        var start = location
        while start > 0 {
            let previousLine = text.lineRange(for: NSRange(location: start - 1, length: 0))
            guard isBlank(previousLine, in: text), previousLine.location > 0 else { break }
            // A blank line counts only when a line with text comes before it.
            start = previousLine.location
        }
        return start
    }

    private static func isBlank(_ lineRange: NSRange, in text: NSString) -> Bool {
        text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func contentEnd(of lineRange: NSRange, in text: NSString) -> Int {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location, [0x0A, 0x0D].contains(text.character(at: end - 1)) { end -= 1 }
        return end
    }

    private static func lineBreak(of text: NSString) -> String {
        text.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
    }

    /// The one edit that turns `text` into `result`: the part between what they share at the
    /// start and at the end.
    static func smallestEdit(from text: NSString, to result: NSString, selectionAfter: NSRange) -> MarkdownTextEdit? {
        guard text != result else { return nil }
        let shortestLength = min(text.length, result.length)
        var prefix = 0
        while prefix < shortestLength, text.character(at: prefix) == result.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shortestLength - prefix, text.character(at: text.length - 1 - suffix) == result.character(at: result.length - 1 - suffix) { suffix += 1 }
        let range = NSRange(location: prefix, length: text.length - suffix - prefix)
        let replacement = result.substring(with: NSRange(location: prefix, length: result.length - suffix - prefix))
        return MarkdownTextEdit(range: range, replacement: replacement, selectionAfter: selectionAfter)
    }
}
