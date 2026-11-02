/**
 * File: ReadingInlineHTML.swift
 * -----------------------------
 * Layer: Core
 * Description: The HTML Obsidian draws in a note: comments hidden, line breaks, highlights, underline, raised and lowered text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// The HTML Obsidian draws in a note: comments are hidden, `<br>` breaks the line (the form
/// Graphite's own table editor writes in a cell), `<mark>` highlights, `<u>` underlines, `<sub>`
/// and `<sup>` lower and raise their text, `<kbd>` is code and `<b>`, `<i>` and `<s>` are the
/// styles their Markdown marks give. Code, fenced or in a span, is left as written. The
/// reading view and Live Preview's rendered blocks both read the result through `ReadingMarkers`.
enum ReadingInlineHTML {
    private static let tagPattern = ReadingInlineHTMLPattern.tagPattern.compiled()

    static func prepared(_ markdown: String) -> String {
        guard markdown.contains("<") else { return markdown }
        let source = markdown as NSString
        let matches = tagPattern.matches(in: markdown, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return markdown }
        let codeRanges = MarkdownCodeRanges.rangeSet(in: source)
        let output = NSMutableString(string: markdown)
        for match in matches.reversed() where !codeRanges.intersects(match.range) {
            output.replaceCharacters(in: match.range, with: replacement(for: match, in: source))
        }
        return output as String
    }

    private static func replacement(for match: NSTextCheckingResult, in source: NSString) -> String {
        let tag = source.substring(with: match.range).lowercased()
        if tag.hasPrefix("<!--") { return "" }
        if match.range(at: 1).location != NSNotFound {
            // `<sub>…</sub>` and `<sup>…</sup>`: the text in lowered or raised characters when it has them all.
            let isSubscript = source.substring(with: match.range(at: 1)).lowercased() == "sub"
            let text = source.substring(with: match.range(at: 2))
            return shifted(text, subscripted: isSubscript) ?? text
        }
        if match.range(at: 3).location != NSNotFound { return String(ReadingMarkers.lineBreakMarker) }
        let isClosing = tag.hasPrefix("</")
        switch source.substring(with: match.range(at: 4)).lowercased() {
        case "mark": return String(isClosing ? ReadingMarkers.highlightEndMarker : ReadingMarkers.highlightStartMarker)
        case "u": return String(isClosing ? ReadingMarkers.underlineEndMarker : ReadingMarkers.underlineStartMarker)
        case "kbd": return "`"
        case "b", "strong": return "**"
        case "i", "em": return "*"
        default: return "~~"
        }
    }

    private static let superscripts: [Character: Character] = [
        "0": "\u{2070}", "1": "\u{00B9}", "2": "\u{00B2}", "3": "\u{00B3}", "4": "\u{2074}", "5": "\u{2075}", "6": "\u{2076}", "7": "\u{2077}",
        "8": "\u{2078}", "9": "\u{2079}", "+": "\u{207A}", "-": "\u{207B}", "=": "\u{207C}", "(": "\u{207D}", ")": "\u{207E}", "n": "\u{207F}", "i": "\u{2071}",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "\u{2080}", "1": "\u{2081}", "2": "\u{2082}", "3": "\u{2083}", "4": "\u{2084}", "5": "\u{2085}", "6": "\u{2086}", "7": "\u{2087}",
        "8": "\u{2088}", "9": "\u{2089}", "+": "\u{208A}", "-": "\u{208B}", "=": "\u{208C}", "(": "\u{208D}", ")": "\u{208E}", "a": "\u{2090}", "e": "\u{2091}",
        "o": "\u{2092}", "x": "\u{2093}", "h": "\u{2095}", "k": "\u{2096}", "l": "\u{2097}", "m": "\u{2098}", "n": "\u{2099}", "p": "\u{209A}", "s": "\u{209B}", "t": "\u{209C}",
    ]

    /// `text` in subscript or superscript characters; nil when one of its characters has none.
    private static func shifted(_ text: String, subscripted: Bool) -> String? {
        guard !text.isEmpty else { return nil }
        let table = subscripted ? subscripts : superscripts
        var shiftedCharacters = ""
        for character in text {
            guard let shiftedCharacter = table[character] else { return nil }
            shiftedCharacters.append(shiftedCharacter)
        }
        return shiftedCharacters
    }
}

/// The constant patterns of `ReadingInlineHTML`; `StaticPatternTests` compiles every case.
enum ReadingInlineHTMLPattern: String, StaticPatternSet {
    /// A comment, a `<sub>` or `<sup>` pair (groups 1 and 2), `<br>` (group 3), or one tag of the others (group 4).
    case tagPattern = #"<!--[\s\S]*?-->|<(sub|sup)>([^<\n]*)</\1>|(<br[ \t]*/?>)|</?(mark|u|kbd|b|strong|i|em|s|del)>"#

    var options: NSRegularExpression.Options { [.caseInsensitive] }
}
