/**
 * File: EmbedLocator.swift
 * ------------------------
 * Layer: Core
 * Description: Finds the embeds in note source, and the one that is all of a line or of a list item.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 01/11/2026
 */

import Foundation

public enum EmbedLocator {
    private static let wikiEmbedPattern = EmbedLocatorPattern.wikiEmbedPattern.compiled()
    /// The parentheses hold a `<…>` destination and an optional title, or text with at
    /// most one balanced `(…)` in it, which is how a `(title)` is written.
    private static let markdownEmbedPattern = EmbedLocatorPattern.markdownEmbedPattern.compiled()
    private static let standaloneEmbedPattern = EmbedLocatorPattern.standaloneEmbedPattern.compiled()
    private static let listItemEmbedPattern = EmbedLocatorPattern.listItemEmbedPattern.compiled()

    /// The embed that is alone on `line`, indentation and trailing spaces aside, which the
    /// reading view and Live Preview draw as a block of its own. Its destination may hold
    /// one balanced `(…)`, as `embed(at:in:)` reads it, so `![](photo (1).png)` is an image
    /// block too.
    ///
    /// An embed alone in a list item (`- ![[Other note]]`) is a block too, unless it is an
    /// image, which sits in the item beside its bullet. The block stands for the whole item,
    /// so the bullet is not drawn.
    static func standaloneEmbed(onLine line: String) -> EmbedReference? {
        let source = line as NSString
        let wholeLine = NSRange(location: 0, length: source.length)
        if standaloneEmbedPattern.firstMatch(in: line, range: wholeLine) != nil {
            return embed(at: source.range(of: "!").location + 1, in: source)
        }
        guard listItemEmbedPattern.firstMatch(in: line, range: wholeLine) != nil,
              let embedInItem = embed(at: source.range(of: "!").location + 1, in: source) else { return nil }
        let path = embedInItem.target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? embedInItem.target
        return DocumentKind(fileExtension: (path as NSString).pathExtension) == .image ? nil : embedInItem
    }

    /// The embed whose source text contains `location` (or ends exactly there).
    public static func embed(at location: Int, in text: NSString) -> EmbedReference? {
        guard location >= 0, location <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let line = text.substring(with: lineRange)
        let localLocation = location - lineRange.location
        func contains(_ range: NSRange) -> Bool { localLocation >= range.location && localLocation <= NSMaxRange(range) }
        let lineLength = (line as NSString).length
        if let match = wikiEmbedPattern.matches(in: line, range: NSRange(location: 0, length: lineLength)).first(where: { match in contains(match.range) }) {
            let content = (line as NSString).substring(with: match.range(at: 1))
            let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            // Only the `\` of a table's escaped `\|` goes: other backslashes are the name's.
            var target = parts[0]
            if parts.count > 1, target.hasSuffix("\\") { target.removeLast() }
            return EmbedReference(target: target, isWiki: true, displaySize: parts.count > 1 ? EmbedDisplaySize.parse(label: parts[1]) : nil,
                                  range: NSRange(location: lineRange.location + match.range.location, length: match.range.length))
        }
        if let match = markdownEmbedPattern.matches(in: line, range: NSRange(location: 0, length: lineLength)).first(where: { match in contains(match.range) }) {
            let label = (line as NSString).substring(with: match.range(at: 1))
            let destination = linkDestination(in: (line as NSString).substring(with: match.range(at: 2)))
            guard !destination.isEmpty else { return nil }
            return EmbedReference(target: destination, isWiki: false, displaySize: EmbedDisplaySize.parse(label: label),
                                  range: NSRange(location: lineRange.location + match.range.location, length: match.range.length))
        }
        return nil
    }

    /// The destination of a Markdown image, by CommonMark's rules: the text inside `<…>`,
    /// or else the text up to the first whitespace. A `"title"`, `'title'` or `(title)`
    /// after it is not part of the destination, so `![a](a.png "Title")` embeds `a.png`.
    static func linkDestination(in parenthesizedText: String) -> String {
        let trimmedText = parenthesizedText.trimmingCharacters(in: .whitespaces)
        if trimmedText.hasPrefix("<"), let closingIndex = trimmedText.firstIndex(of: ">") {
            return String(trimmedText[trimmedText.index(after: trimmedText.startIndex)..<closingIndex])
        }
        return trimmedText.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}

/// The constant patterns of `EmbedLocator`; `StaticPatternTests` compiles every case.
enum EmbedLocatorPattern: String, StaticPatternSet {
    case wikiEmbedPattern = #"!\[\[([^\]\n]+)\]\]"#
    case markdownEmbedPattern = #"!\[([^\]\n]*)\]\((<[^<>\n]*>[^)\n]*|[^()\n]*(?:\([^()\n]*\)[^()\n]*)?)\)"#
    /// A list item's marker (and a task's checkbox) before an embed that is all its text.
    case listItemEmbedPattern = #"^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])[ \t]+(?:\[.\][ \t]+)?(!\[\[[^\]\n]+\]\]|!\[[^\]\n]*\]\((?:<[^<>\n]*>[^)\n]*|[^()\n]+(?:\([^()\n]*\)[^()\n]*)?)\))[ \t]*$"#
    case standaloneEmbedPattern = #"^[ \t]*(!\[\[[^\]\n]+\]\]|!\[[^\]\n]*\]\((?:<[^<>\n]*>[^)\n]*|[^()\n]+(?:\([^()\n]*\)[^()\n]*)?)\))[ \t]*$"#
}
