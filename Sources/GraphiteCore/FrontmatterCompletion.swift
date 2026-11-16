/**
 * File: FrontmatterCompletion.swift
 * ---------------------------------
 * Layer: Core
 * Description: What is being typed in a note's frontmatter, for suggestions: a property's name at the start of a line,
 *              or a value after `name:`, in an inline list or as a `- ` item under it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

/// A property's name or value being typed in a note's YAML frontmatter, as Obsidian suggests them in its Properties view
/// and in the frontmatter written as text (`Docs/Property-and-tag-completion-todo.md`, section 2).
public enum FrontmatterCompletion {
    /// The frontmatter is looked for only this many lines into the note: a block longer than that gets no suggestions.
    static let maximumFrontmatterLineCount = 400
    /// Suggestions stop after this many characters, as for links and tags.
    static let maximumQueryLength = 200

    /// Whether `cursor` is inside a frontmatter block that opens on the note's first line and is closed by a `---` or `...`
    /// line after the cursor's line: on its lines, between the two fences.
    public static func isInsideFrontmatter(_ text: NSString, cursor: Int) -> Bool {
        frontmatterLines(in: text, around: cursor) != nil
    }

    /// The suggestion context at `cursor`, or nil outside a frontmatter block or where nothing is suggested. A `[[` link
    /// in a value is the body's link context (`LinkCompletion`), looked for first.
    public static func context(in text: NSString, cursor: Int) -> CompletionContext? {
        guard let lines = frontmatterLines(in: text, around: cursor) else { return nil }
        let line = lines.cursorLine
        let beforeCursor = text.substring(with: NSRange(location: line.location, length: cursor - line.location))
        let lineText = text.substring(with: line)
        // A comment, or a line inside a quoted multi-line value, is not looked into.
        if beforeCursor.contains("#") { return nil }
        if let nameContext = nameContext(beforeCursor: beforeCursor, lineText: lineText, lineStart: line.location, cursor: cursor,
                                         names: lines.names) {
            return nameContext
        }
        if let inlineValue = inlineValueContext(beforeCursor: beforeCursor, lineText: lineText, lineStart: line.location, cursor: cursor,
                                                text: text, lines: lines) {
            return inlineValue
        }
        return listItemContext(beforeCursor: beforeCursor, lineText: lineText, lineStart: line.location, cursor: cursor, text: text, lines: lines)
    }

    // MARK: The block

    /// The lines of a frontmatter block around the cursor, the cursor's own line, and the property names it writes.
    struct BlockLines {
        /// Each line's range without its line ending, from the line after the opening `---` to the one before the closing.
        let lineRanges: [NSRange]
        let cursorLineIndex: Int
        var cursorLine: NSRange { lineRanges[cursorLineIndex] }
        /// The names written at the start of the block's lines, other than on the cursor's line.
        let names: [String]
    }

    static func frontmatterLines(in text: NSString, around cursor: Int) -> BlockLines? {
        guard text.length >= 4, text.hasPrefix("---"), cursor > 3, cursor <= text.length else { return nil }
        let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
        guard text.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        var lineRanges: [NSRange] = []
        var cursorLineIndex: Int?
        var location = NSMaxRange(firstLine)
        while location < text.length || (location == text.length && cursorLineIndex == nil && location == cursor) {
            guard lineRanges.count < maximumFrontmatterLineCount else { return nil }
            let lineRange = location < text.length ? text.lineRange(for: NSRange(location: location, length: 0)) : NSRange(location: location, length: 0)
            let content = contentRange(of: lineRange, in: text)
            let trimmed = text.substring(with: content).trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                guard let cursorLineIndex else { return nil }
                let names = lineRanges.enumerated().compactMap { index, range in
                    index == cursorLineIndex ? nil : propertyName(onLine: text.substring(with: range))
                }
                return BlockLines(lineRanges: lineRanges, cursorLineIndex: cursorLineIndex, names: names)
            }
            if cursorLineIndex == nil, cursor >= content.location, cursor <= NSMaxRange(content) { cursorLineIndex = lineRanges.count }
            lineRanges.append(content)
            guard NSMaxRange(lineRange) > location else { break }
            location = NSMaxRange(lineRange)
        }
        return nil
    }

    private static func contentRange(of lineRange: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location {
            let character = text.character(at: end - 1)
            guard character == 0x0A || character == 0x0D else { break }
            end -= 1
        }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }

    /// The property a line names at its start (`course: VLSI 3` names `course`), nil for list items and other lines.
    static func propertyName(onLine line: String) -> String? {
        guard let first = line.first, !first.isWhitespace, first != "-", first != "#", let colon = line.firstIndex(of: ":") else { return nil }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : unquoted(name)
    }

    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }

    // MARK: A property's name

    /// A name typed at the start of a line, before any `:`.
    private static func nameContext(beforeCursor: String, lineText: String, lineStart: Int, cursor: Int, names: [String]) -> CompletionContext? {
        guard let first = beforeCursor.first, !first.isWhitespace, first != "-", first != "\"", first != "'",
              !beforeCursor.contains(":"), beforeCursor.utf16.count <= maximumQueryLength else { return nil }
        // The rest of the name after the cursor is replaced too, up to a `:` if the line has one.
        let afterCursor = String(lineText.dropFirst(beforeCursor.count))
        let followingName = afterCursor.prefix { character in character != ":" }
        let replacesColon = afterCursor.dropFirst(followingName.count).hasPrefix(":")
        let length = beforeCursor.utf16.count + followingName.utf16.count + (replacesColon ? 1 : 0)
        let followingSpace = replacesColon && afterCursor.dropFirst(followingName.count + 1).hasPrefix(" ") ? 1 : 0
        return .propertyName(query: beforeCursor, replacementRange: NSRange(location: lineStart, length: length + followingSpace), writtenNames: names)
    }

    // MARK: A property's value

    /// A value typed after `name:` on the same line: the whole value, or the item of an inline list `[a, b` being typed.
    private static func inlineValueContext(beforeCursor: String, lineText: String, lineStart: Int, cursor: Int,
                                           text: NSString, lines: BlockLines) -> CompletionContext? {
        guard let name = propertyName(onLine: lineText), let colon = beforeCursor.firstIndex(of: ":") else { return nil }
        let valueBeforeCursor = beforeCursor[beforeCursor.index(after: colon)...]
        guard valueBeforeCursor.first == " " || valueBeforeCursor.first == "\t" else { return nil }
        let trimmedValue = valueBeforeCursor.drop { character in character == " " || character == "\t" }
        let valueStart = cursor - trimmedValue.utf16.count
        if trimmedValue.hasPrefix("[") {
            // An inline list: the item after the last `[` or `,`, without its spaces or an opening quote.
            guard !trimmedValue.contains("]") else { return nil }
            let lastSeparator = trimmedValue.lastIndex { character in character == "[" || character == "," }
            let itemStartIndex = lastSeparator.map(trimmedValue.index(after:)) ?? trimmedValue.startIndex
            var item = trimmedValue[itemStartIndex...].drop { character in character == " " }
            if item.first == "\"" || item.first == "'" { item = item.dropFirst() }
            let written = inlineListItems(String(trimmedValue.dropFirst()))
            return valueContext(name: name, query: String(item), cursor: cursor, lineText: lineText, lineStart: lineStart,
                                endingAt: [",", "]"], writtenValues: written.filter { written in written != String(item) })
        }
        var query = String(trimmedValue)
        var start = valueStart
        if query.first == "\"" || query.first == "'" {
            query.removeFirst()
            start += 1
        }
        return valueContext(name: name, query: query, cursor: cursor, lineText: lineText, lineStart: lineStart, endingAt: [], writtenValues: [],
                            replacementStart: start)
    }

    /// A `- ` item under a `name:` line with no value of its own.
    private static func listItemContext(beforeCursor: String, lineText: String, lineStart: Int, cursor: Int,
                                        text: NSString, lines: BlockLines) -> CompletionContext? {
        let indentation = beforeCursor.prefix { character in character == " " || character == "\t" }
        let rest = beforeCursor.dropFirst(indentation.count)
        guard rest.hasPrefix("- ") else { return nil }
        var item = rest.dropFirst(2).drop { character in character == " " }
        if item.first == "\"" || item.first == "'" { item = item.dropFirst() }
        // The property is the nearest line above that is not an item of the same list.
        var name: String?
        var written: [String] = []
        var lineIndex = lines.cursorLineIndex - 1
        while lineIndex >= 0 {
            let line = text.substring(with: lines.lineRanges[lineIndex])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                written.append(listItemValue(trimmed))
                lineIndex -= 1
                continue
            }
            guard let owner = propertyName(onLine: line), let colon = line.firstIndex(of: ":"),
                  line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            name = owner
            break
        }
        guard let name else { return nil }
        var following = lines.cursorLineIndex + 1
        while following < lines.lineRanges.count {
            let trimmed = text.substring(with: lines.lineRanges[following]).trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { break }
            written.append(listItemValue(trimmed))
            following += 1
        }
        return valueContext(name: name, query: String(item), cursor: cursor, lineText: lineText, lineStart: lineStart, endingAt: [],
                            writtenValues: written.filter { value in !value.isEmpty })
    }

    private static func listItemValue(_ trimmedLine: String) -> String {
        unquoted(String(trimmedLine.dropFirst(trimmedLine.hasPrefix("- ") ? 2 : 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func inlineListItems(_ inside: String) -> [String] {
        inside.split(separator: ",").map { item in unquoted(item.trimmingCharacters(in: .whitespaces)) }.filter { item in !item.isEmpty }
    }

    /// The value being typed, replaced up to the end of the line or the next of `endingAt`, without a closing quote.
    private static func valueContext(name: String, query: String, cursor: Int, lineText: String, lineStart: Int,
                                     endingAt terminators: Set<Character>, writtenValues: [String], replacementStart: Int? = nil) -> CompletionContext? {
        guard query.utf16.count <= maximumQueryLength, !query.contains("[["), !name.isEmpty else { return nil }
        let start = replacementStart ?? (cursor - query.utf16.count)
        let cursorInLine = cursor - lineStart
        let afterCursor = String((lineText as NSString).substring(from: min(cursorInLine, lineText.utf16.count)))
        let following = afterCursor.prefix { character in !terminators.contains(character) && character != "\"" && character != "'" }
        let followingLength = terminators.isEmpty && afterCursor.contains(where: { character in character == "\"" || character == "'" })
            ? following.utf16.count : (terminators.isEmpty ? afterCursor.utf16.count : following.utf16.count)
        let trailingSpaces = terminators.isEmpty ? 0 : following.reversed().prefix { character in character == " " }.count
        return .propertyValue(name: name, query: query, replacementRange: NSRange(location: start, length: cursor - start + followingLength - trailingSpaces),
                              writtenValues: writtenValues)
    }
}
