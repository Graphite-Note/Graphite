/**
 * File: MarkdownListRenumbering.swift
 * -----------------------------------
 * Layer: Core
 * Description: Numbered list items counted again after Tab, Shift-Tab, a moved line, a deleted item or pasted lines, as Obsidian's smart lists count them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import Foundation

extension MarkdownEditing {
    /// `edit` with the numbered lists it touched counted again, as one edit, so Undo takes
    /// both back together: Tab on `2.` of `1. 2. 3.` gives a nested `1.` and turns `3.` into
    /// `2.`, Shift-Tab gives it back, and a line moved to the top of a list takes its first
    /// number. Each numbered item touched, and the one after them, takes the number after the
    /// item above it at its level; an item that starts a nested list counts from 1; the first
    /// item of a list takes the list's smallest number. The siblings after a renumbered item
    /// follow. A list numbered all alike, such as every item `1.`, is left as written.
    static func renumberingLists(after edit: MarkdownTextEdit, in text: NSString, tabSize: Int) -> MarkdownTextEdit {
        guard NSMaxRange(edit.range) <= text.length else { return edit }
        var renumbering = ListRenumbering(text: text, edit: edit, tabSize: tabSize)
        renumbering.run()
        return renumbering.combinedEdit(of: edit, in: text)
    }

    /// Replacing `range` with `replacement`, with the numbered lists it touched counted again,
    /// as Obsidian's smart lists count them after every change: a deleted item's followers
    /// move up a number, and pasted items take the numbers of their place. Only an edit that
    /// adds or removes a line break can change a list's numbers; nil for any other, and when
    /// the numbers stay as they are, so the text view makes the plain edit itself.
    public static func renumberingLists(replacing range: NSRange, with replacement: String, in text: NSString, tabSize: Int) -> MarkdownTextEdit? {
        guard NSMaxRange(range) <= text.length else { return nil }
        let changesLines = replacement.contains(where: \.isNewline) || text.substring(with: range).contains(where: \.isNewline)
        guard changesLines else { return nil }
        let plainEdit = MarkdownTextEdit(range: range, replacement: replacement,
                                         selectionAfter: NSRange(location: range.location + replacement.utf16.count, length: 0))
        let renumbered = renumberingLists(after: plainEdit, in: text, tabSize: tabSize)
        return renumbered == plainEdit ? nil : renumbered
    }
}

/// One pass of `MarkdownEditing.renumberingLists(after:in:tabSize:)` over the edited text.
private struct ListRenumbering {
    let working: NSMutableString
    let tabSize: Int
    /// The edited lines, in the working text, which move as numbers change length.
    var regionStart: Int
    var regionEnd: Int
    var selectionStart: Int
    var selectionEnd: Int
    var hasChanged = false

    init(text: NSString, edit: MarkdownTextEdit, tabSize: Int) {
        working = NSMutableString(string: text)
        working.replaceCharacters(in: edit.range, with: edit.replacement)
        self.tabSize = tabSize
        regionStart = working.lineRange(for: NSRange(location: min(edit.range.location, working.length), length: 0)).location
        regionEnd = edit.range.location + edit.replacement.utf16.count
        selectionStart = edit.selectionAfter.location
        selectionEnd = NSMaxRange(edit.selectionAfter)
    }

    /// Renumbers the items of the edited lines and the first item after them.
    mutating func run() {
        var location = regionStart
        var hasPassedRegion = false
        while location < working.length {
            let lineRange = working.lineRange(for: NSRange(location: location, length: 0))
            if location >= regionEnd {
                // The first line with text after the edit, which may have lost or gained an item above.
                if MarkdownEditing.lineContents(in: working, range: lineRange).first?.content.trimmingCharacters(in: .whitespaces).isEmpty == true {
                    location = NSMaxRange(lineRange)
                    continue
                }
                hasPassedRegion = true
            }
            renumberItem(atLineStart: location)
            location = NSMaxRange(working.lineRange(for: NSRange(location: location, length: 0)))
            if hasPassedRegion { break }
        }
    }

    /// The numbered item at `lineStart` takes its number, and its following siblings theirs.
    private mutating func renumberItem(atLineStart lineStart: Int) {
        guard let item = numberedItem(atLineStart: lineStart), let expected = expectedNumber(of: item, atLineStart: lineStart) else { return }
        setNumber(expected, of: item, atLineStart: lineStart)
        var previousNumber = expected
        var location = NSMaxRange(working.lineRange(for: NSRange(location: lineStart, length: 0)))
        let width = MarkdownEditing.indentationWidth(item.indentation, tabSize: tabSize)
        while location < working.length {
            let lineRange = working.lineRange(for: NSRange(location: location, length: 0))
            guard let line = MarkdownEditing.lineContents(in: working, range: lineRange).first?.content else { break }
            location = NSMaxRange(lineRange)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parsed = MarkdownListSyntax.listLine(line)
            guard (parsed?.quotePrefix ?? "") == item.quotePrefix else { break }
            guard let parsed, parsed.isListItem else {
                // A continuation line of an item stays in the list; a paragraph ends it.
                if leadingWidth(of: line, after: item.quotePrefix) > width { continue }
                break
            }
            let siblingWidth = MarkdownEditing.indentationWidth(parsed.indentation, tabSize: tabSize)
            if siblingWidth > width { continue }
            guard siblingWidth == width, parsed.orderedNumber != nil, parsed.marker.last == item.marker.last else { break }
            setNumber(previousNumber + 1, of: parsed, atLineStart: lineRange.location)
            previousNumber += 1
        }
    }

    /// The number the item should have; nil to leave the item and its list as written.
    private func expectedNumber(of item: MarkdownListSyntax.ListLine, atLineStart lineStart: Int) -> Int? {
        guard let current = item.orderedNumber else { return nil }
        let width = MarkdownEditing.indentationWidth(item.indentation, tabSize: tabSize)
        if let above = MarkdownEditing.orderedNumber(ofItemAbove: lineStart, quotePrefix: item.quotePrefix, indentationWidth: width,
                                                     in: working, tabSize: tabSize) {
            // `1. 1. 1.` is numbered alike on purpose; `1. 1. 2.`, after Shift-Tab, is not.
            let levelNumbers = precedingSiblingNumbers(before: lineStart, item: item, width: width) + [current]
                + followingSiblingNumbers(after: lineStart, item: item, width: width)
            let isNumberedAlike = levelNumbers.count >= 3 && Set(levelNumbers).count == 1
            return isNumberedAlike ? nil : above + 1
        }
        if hasParentItem(above: lineStart, item: item, width: width) { return 1 }
        let numbers = [current] + followingSiblingNumbers(after: lineStart, item: item, width: width)
        guard numbers.count > 1, Set(numbers).count > 1 else { return nil }
        return numbers.min()
    }

    /// Whether a list item less indented than `width` holds the item: it then starts a nested list.
    private func hasParentItem(above lineStart: Int, item: MarkdownListSyntax.ListLine, width: Int) -> Bool {
        var location = lineStart
        while location > 0 {
            let lineRange = working.lineRange(for: NSRange(location: location - 1, length: 0))
            location = lineRange.location
            guard let line = MarkdownEditing.lineContents(in: working, range: lineRange).first?.content else { return false }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let parsed = MarkdownListSyntax.listLine(line), parsed.quotePrefix == item.quotePrefix else { return false }
            guard parsed.isListItem else {
                if leadingWidth(of: line, after: item.quotePrefix) > width { continue }
                return false
            }
            let parentWidth = MarkdownEditing.indentationWidth(parsed.indentation, tabSize: tabSize)
            if parentWidth > width { continue }
            return parentWidth < width
        }
        return false
    }

    /// The numbers of the items before the one at `lineStart` at its level, up to the list's
    /// start or the item holding them.
    private func precedingSiblingNumbers(before lineStart: Int, item: MarkdownListSyntax.ListLine, width: Int) -> [Int] {
        var numbers: [Int] = []
        var location = lineStart
        while location > 0 {
            let lineRange = working.lineRange(for: NSRange(location: location - 1, length: 0))
            location = lineRange.location
            guard let line = MarkdownEditing.lineContents(in: working, range: lineRange).first?.content else { break }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let parsed = MarkdownListSyntax.listLine(line), parsed.quotePrefix == item.quotePrefix else { break }
            guard parsed.isListItem else {
                if leadingWidth(of: line, after: item.quotePrefix) > width { continue }
                break
            }
            let siblingWidth = MarkdownEditing.indentationWidth(parsed.indentation, tabSize: tabSize)
            if siblingWidth > width { continue }
            guard siblingWidth == width, let number = parsed.orderedNumber, parsed.marker.last == item.marker.last else { break }
            numbers.insert(number, at: 0)
        }
        return numbers
    }

    /// The numbers of the items after the one at `lineStart` at its level, up to the list's end.
    private func followingSiblingNumbers(after lineStart: Int, item: MarkdownListSyntax.ListLine, width: Int) -> [Int] {
        var numbers: [Int] = []
        var location = NSMaxRange(working.lineRange(for: NSRange(location: lineStart, length: 0)))
        while location < working.length {
            let lineRange = working.lineRange(for: NSRange(location: location, length: 0))
            guard let line = MarkdownEditing.lineContents(in: working, range: lineRange).first?.content else { break }
            location = NSMaxRange(lineRange)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let parsed = MarkdownListSyntax.listLine(line), parsed.quotePrefix == item.quotePrefix else { break }
            guard parsed.isListItem else {
                if leadingWidth(of: line, after: item.quotePrefix) > width { continue }
                break
            }
            let siblingWidth = MarkdownEditing.indentationWidth(parsed.indentation, tabSize: tabSize)
            if siblingWidth > width { continue }
            guard siblingWidth == width, let number = parsed.orderedNumber, parsed.marker.last == item.marker.last else { break }
            numbers.append(number)
        }
        return numbers
    }

    private func numberedItem(atLineStart lineStart: Int) -> MarkdownListSyntax.ListLine? {
        let lineRange = working.lineRange(for: NSRange(location: lineStart, length: 0))
        guard let line = MarkdownEditing.lineContents(in: working, range: lineRange).first?.content,
              let parsed = MarkdownListSyntax.listLine(line), parsed.isListItem, parsed.orderedNumber != nil else { return nil }
        return parsed
    }

    private func leadingWidth(of line: String, after quotePrefix: String) -> Int {
        let afterQuote = line.hasPrefix(quotePrefix) ? String(line.dropFirst(quotePrefix.count)) : line
        return MarkdownEditing.indentationWidth(String(afterQuote.prefix { character in character == " " || character == "\t" }), tabSize: tabSize)
    }

    /// Writes `number` into the item's marker, moving the selection and the edited lines'
    /// end with the text when the number's length changes.
    private mutating func setNumber(_ number: Int, of item: MarkdownListSyntax.ListLine, atLineStart lineStart: Int) {
        guard number != item.orderedNumber, let delimiter = item.marker.last else { return }
        let markerRange = NSRange(location: lineStart + (item.quotePrefix + item.indentation).utf16.count, length: item.marker.utf16.count)
        let marker = String(number) + String(delimiter)
        working.replaceCharacters(in: markerRange, with: marker)
        let lengthChange = marker.utf16.count - markerRange.length
        if markerRange.location < selectionStart { selectionStart += lengthChange }
        if markerRange.location < selectionEnd { selectionEnd += lengthChange }
        if markerRange.location < regionEnd { regionEnd += lengthChange }
        hasChanged = true
    }

    /// One edit from the original text to the renumbered one: the part between what they
    /// share at the start and at the end.
    func combinedEdit(of edit: MarkdownTextEdit, in text: NSString) -> MarkdownTextEdit {
        guard hasChanged else { return edit }
        let oldLength = text.length, newLength = working.length
        var prefix = 0
        let prefixLimit = min(oldLength, newLength, regionStart)
        while prefix < prefixLimit, text.character(at: prefix) == working.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < min(oldLength, newLength) - prefix,
              text.character(at: oldLength - 1 - suffix) == working.character(at: newLength - 1 - suffix) { suffix += 1 }
        let selection = NSRange(location: selectionStart, length: max(0, selectionEnd - selectionStart))
        return MarkdownTextEdit(range: NSRange(location: prefix, length: oldLength - prefix - suffix),
                                replacement: working.substring(with: NSRange(location: prefix, length: newLength - prefix - suffix)),
                                selectionAfter: selection)
    }
}
