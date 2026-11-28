/**
 * File: HTMLColorSpans.swift
 * --------------------------
 * Layer: Core
 * Description: Inline HTML spans that colour their text or its background (`<span style="color:#e03e3e">…</span>`), as the
 *              Notion importer writes Notion's colours and Obsidian draws them: found, recoloured and removed.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import Foundation

/// A span of the note whose style gives its text a colour, its background a colour, or both.
public struct HTMLColorSpan: Equatable, Sendable {
    public let openingTagRange: NSRange
    public let closingTagRange: NSRange
    public let contentRange: NSRange
    /// Canonical lowercase `#rrggbb` or `#rrggbbaa`.
    public let textHex: String?
    public let backgroundHex: String?
    /// Nesting depth among the note's spans; deeper spans win where they overlap.
    public let depth: Int
}

public enum HTMLColorSpans {
    private static let tagPattern = HTMLColorSpansPattern.tag.compiled()
    private static let stylePattern = HTMLColorSpansPattern.style.compiled()
    /// Spans are looked for in at most this many characters of a block: a note's coloured words, not a whole book.
    static let maximumScannedLength = 200_000

    /// The colour and background spans of `text`, in the order they open. A span in code stays text, and a span
    /// that is never closed colours nothing, as in Obsidian.
    public static func spans(in text: NSString) -> [HTMLColorSpan] {
        guard text.length <= maximumScannedLength, text.range(of: "<span", options: .caseInsensitive).location != NSNotFound else { return [] }
        let codeRanges = MarkdownCodeRanges.rangeSet(in: text)
        var openTags: [(range: NSRange, textHex: String?, backgroundHex: String?)] = []
        var found: [HTMLColorSpan] = []
        for match in tagPattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)) where !codeRanges.intersects(match.range) {
            if match.range(at: 1).location != NSNotFound {
                guard let opening = openTags.popLast() else { continue }
                guard opening.textHex != nil || opening.backgroundHex != nil else { continue }
                let contentStart = NSMaxRange(opening.range)
                found.append(HTMLColorSpan(openingTagRange: opening.range, closingTagRange: match.range,
                                           contentRange: NSRange(location: contentStart, length: match.range.location - contentStart),
                                           textHex: opening.textHex, backgroundHex: opening.backgroundHex, depth: openTags.count))
            } else {
                let attributes = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
                let colors = self.colors(inAttributes: attributes)
                openTags.append((match.range, colors.text, colors.background))
            }
        }
        return found.sorted { firstSpan, secondSpan in firstSpan.openingTagRange.location < secondSpan.openingTagRange.location }
    }

    /// `text` with the tags of its colour and background spans taken out and their text kept: a coloured heading as the
    /// outline lists it.
    public static func textWithoutTags(_ text: String) -> String {
        let tagRanges = spans(in: text as NSString).flatMap { span in [span.openingTagRange, span.closingTagRange] }
        guard !tagRanges.isEmpty else { return text }
        let shown = NSMutableString(string: text)
        for tagRange in tagRanges.sorted(by: { firstTag, secondTag in firstTag.location > secondTag.location }) { shown.deleteCharacters(in: tagRange) }
        return shown as String
    }

    /// The text and background colours a span's attributes give in their `style`.
    static func colors(inAttributes attributes: String) -> (text: String?, background: String?) {
        let source = attributes as NSString
        guard let match = stylePattern.firstMatch(in: attributes, range: NSRange(location: 0, length: source.length)) else { return (nil, nil) }
        let valueRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        var textHex: String?, backgroundHex: String?
        for declaration in source.substring(with: valueRange).split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { part in part.trimmingCharacters(in: .whitespaces).lowercased() }
            guard parts.count == 2, let hex = hex(ofCSSColor: parts[1]) else { continue }
            switch parts[0] {
            case "color": textHex = hex
            case "background-color", "background": backgroundHex = hex
            default: continue
            }
        }
        return (textHex, backgroundHex)
    }

    /// The canonical hex of a CSS colour written as `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(r, g, b)` or `rgba(r, g, b, a)`;
    /// nil for any other form.
    public static func hex(ofCSSColor value: String) -> String? {
        let trimmed = value.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            let digits = trimmed.dropFirst()
            if digits.count == 3 { return TextColorMarkup.canonicalHex("#" + digits.map { digit in "\(digit)\(digit)" }.joined()) }
            return TextColorMarkup.canonicalHex(trimmed)
        }
        guard trimmed.hasPrefix("rgb"), let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else { return nil }
        let numbers = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            .split(whereSeparator: { character in character == "," || character == " " || character == "/" })
            .compactMap { part in Double(part.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 3 || numbers.count == 4, numbers.prefix(3).allSatisfy({ number in (0...255).contains(number) }) else { return nil }
        var hex = "#" + numbers.prefix(3).map { number in String(format: "%02x", Int(number.rounded())) }.joined()
        if numbers.count == 4, numbers[3] < 1 { hex += String(format: "%02x", Int((min(max(numbers[3], 0), 1) * 255).rounded())) }
        return TextColorMarkup.canonicalHex(hex)
    }

    /// The span the selection is in: the innermost one whose text holds the cursor, or that holds the whole selection.
    static func span(around selection: NSRange, in spans: [HTMLColorSpan]) -> HTMLColorSpan? {
        spans.filter { span in
            let extent = NSRange(location: span.openingTagRange.location, length: NSMaxRange(span.closingTagRange) - span.openingTagRange.location)
            return selection.location >= span.contentRange.location && NSMaxRange(selection) <= NSMaxRange(span.contentRange)
                && NSLocationInRange(selection.location, extent)
        }.max { firstSpan, secondSpan in firstSpan.depth < secondSpan.depth }
    }

    /// The edit that gives the span the selection is in the text colour `hex`, its other style kept; nil when the
    /// selection is in no colour or background span.
    public static func recoloring(in text: NSString, selection: NSRange, hex: String) -> MarkdownTextEdit? {
        guard let span = span(around: selection, in: spans(in: text)), let canonical = TextColorMarkup.canonicalHex(hex) else { return nil }
        let openingTag = rewrittenOpeningTag(text.substring(with: span.openingTagRange)) { declarations in
            declarations.filter { declaration in property(of: declaration) != "color" } + ["color:\(canonical)"]
        }
        return edit(replacing: span.openingTagRange, with: openingTag, in: text, selection: selection)
    }

    /// The edit that takes the colours out of the span the selection is in: its tags go when colour was all its style,
    /// else only the colour declarations do. Nil when the selection is in no such span.
    public static func removingColor(in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        guard let span = span(around: selection, in: spans(in: text)) else { return nil }
        var keptDeclarations: [String] = []
        let openingTag = rewrittenOpeningTag(text.substring(with: span.openingTagRange)) { declarations in
            keptDeclarations = declarations.filter { declaration in !["color", "background-color", "background"].contains(property(of: declaration)) }
            return keptDeclarations
        }
        guard keptDeclarations.isEmpty, !openingTag.lowercased().contains("class="), !openingTag.lowercased().contains("id=") else {
            return edit(replacing: span.openingTagRange, with: openingTag, in: text, selection: selection)
        }
        // The whole span goes: its tags, and its text stays.
        let extent = NSRange(location: span.openingTagRange.location, length: NSMaxRange(span.closingTagRange) - span.openingTagRange.location)
        let content = text.substring(with: span.contentRange)
        let shift = span.openingTagRange.length
        let selectionAfter = NSRange(location: max(selection.location - shift, span.openingTagRange.location), length: selection.length)
        return MarkdownTextEdit(range: extent, replacement: content, selectionAfter: selectionAfter)
    }

    private static func property(of declaration: String) -> String {
        declaration.split(separator: ":", maxSplits: 1).first.map { name in name.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
    }

    /// The opening tag with its `style` declarations changed by `change`; the attribute goes when none is left.
    private static func rewrittenOpeningTag(_ tag: String, change: ([String]) -> [String]) -> String {
        let source = tag as NSString
        guard let match = stylePattern.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)) else {
            let declarations = change([])
            return declarations.isEmpty ? tag : source.replacingCharacters(in: NSRange(location: source.length - 1, length: 0),
                                                                             with: " style=\"\(declarations.joined(separator: ";"))\"")
        }
        let valueRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        let declarations = change(source.substring(with: valueRange).split(separator: ";")
            .map { declaration in declaration.trimmingCharacters(in: .whitespaces) }.filter { declaration in !declaration.isEmpty })
        guard !declarations.isEmpty else {
            // The attribute and the space before it go.
            var attributeRange = match.range
            if attributeRange.location > 0, source.substring(with: NSRange(location: attributeRange.location - 1, length: 1)) == " " {
                attributeRange = NSRange(location: attributeRange.location - 1, length: attributeRange.length + 1)
            }
            return source.replacingCharacters(in: attributeRange, with: "")
        }
        return source.replacingCharacters(in: valueRange, with: declarations.joined(separator: ";"))
    }

    private static func edit(replacing range: NSRange, with replacement: String, in text: NSString, selection: NSRange) -> MarkdownTextEdit {
        let shift = (replacement as NSString).length - range.length
        let selectionAfter = selection.location >= NSMaxRange(range) ? NSRange(location: selection.location + shift, length: selection.length) : selection
        return MarkdownTextEdit(range: range, replacement: replacement, selectionAfter: selectionAfter)
    }
}

/// The constant patterns of `HTMLColorSpans`; `StaticPatternTests` compiles every case.
enum HTMLColorSpansPattern: String, StaticPatternSet {
    /// A closing `</span>` (group 1), or an opening `<span …>` with its attributes (group 2).
    case tag = #"(</span\s*>)|<span(\s(?:[^<>"']|"[^"]*"|'[^']*')*)?>"#
    /// A `style` attribute, its value in double (group 1) or single (group 2) quotes.
    case style = #"style\s*=\s*(?:"([^"]*)"|'([^']*)')"#

    var options: NSRegularExpression.Options { [.caseInsensitive] }
}
