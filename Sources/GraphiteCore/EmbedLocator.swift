/**
 * File: EmbedLocator.swift
 * ------------------------
 * Layer: Core
 * Description: Finds the embeds in note source, the one that is all of a line or of a list item, and
 *              the pictures of a line or list item that shows images among its text.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 12/11/2026
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

    /// The pieces of `line` when it embeds at least one image or PDF of the vault and is not
    /// that embed alone: its text between the embeds, trimmed, and the embeds in order, as in
    /// `![[a.jpg|200]] ![[b.jpg|200]]` or `See ![alt|120](a.png) here`. Obsidian draws such
    /// a line as its text with the pictures side by side at their sizes, and a PDF as its
    /// viewer: two PDFs on one line were left as link text (HUNT-351). A web image, a note or
    /// any other file embedded in the line stays text, and so does an embed in code. Nil when
    /// the line embeds no image or PDF.
    static func imageLinePieces(onLine line: String) -> [ImageLinePiece]? {
        guard line.contains("![") else { return nil }
        let source = line as NSString
        let wholeLine = NSRange(location: 0, length: source.length)
        let codeRanges = MarkdownCodeRanges.rangeSet(in: source)
        let embedRanges = (wikiEmbedPattern.matches(in: line, range: wholeLine) + markdownEmbedPattern.matches(in: line, range: wholeLine))
            .map(\.range).filter { range in !codeRanges.intersects(range) }.sorted { leftRange, rightRange in leftRange.location < rightRange.location }
        var pieces: [ImageLinePiece] = []
        var textStart = 0
        func appendText(upTo end: Int) {
            let text = source.substring(with: NSRange(location: textStart, length: end - textStart)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { pieces.append(.text(text)) }
        }
        for embedRange in embedRanges where embedRange.location >= textStart {
            guard let embed = embed(at: embedRange.location + 1, in: source), embed.range == embedRange, !embed.isRemoteImage,
                  [.image, .pdf].contains(DocumentKind(fileExtension: (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension)) else { continue }
            appendText(upTo: embedRange.location)
            pieces.append(.image(embed))
            textStart = NSMaxRange(embedRange)
        }
        guard textStart > 0 else { return nil }
        appendText(upTo: source.length)
        return pieces
    }

    /// The Markdown embeds of vault files in `text` (`![alt|200](Photos/a.png)`), outside code,
    /// in order, their ranges counted in `text`; a web image is no vault file and is left out.
    /// A table or callout drawn by the reading view's renderer finds its images with this and
    /// the Wikilink embeds, as the reading view does.
    public static func markdownEmbeds(in text: String) -> [EmbedReference] {
        guard text.contains("![") else { return [] }
        let source = text as NSString
        let codeRanges = MarkdownCodeRanges.rangeSet(in: source)
        return markdownEmbedPattern.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard !codeRanges.intersects(match.range) else { return nil }
            let destination = linkDestination(in: source.substring(with: match.range(at: 2)))
            guard !destination.isEmpty else { return nil }
            let embed = EmbedReference(target: destination, isWiki: false, displaySize: EmbedDisplaySize.parse(label: source.substring(with: match.range(at: 1))),
                                       range: match.range)
            return embed.isRemoteImage ? nil : embed
        }
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

/// A piece of a line that shows images among its text (`EmbedLocator.imageLinePieces(onLine:)`).
public enum ImageLinePiece: Equatable, Sendable {
    /// The bullet or number of a list item whose text shows images; when there is one, it is
    /// the first piece.
    case listMarker(ImageLineListMarker)
    /// Text between pictures, drawn as Markdown.
    case text(String)
    /// An image of the vault, or a PDF, which is shown as its viewer; its range counted in the line.
    case image(EmbedReference)
}

/// The marker of a list item whose text shows images, with the whitespace around it as the
/// line has it, so the item is drawn as indented as the editor draws its other items.
public struct ImageLineListMarker: Equatable, Sendable {
    /// The spaces and tabs before the marker.
    public let indentation: String
    /// `-`, `*`, `+`, or a number with `.` or `)`.
    public let marker: String
    /// The whitespace between the marker and the item's text.
    public let spacing: String

    public init(indentation: String, marker: String, spacing: String) {
        self.indentation = indentation
        self.marker = marker
        self.spacing = spacing
    }

    /// Whether the item is a bullet, drawn as a dot, rather than a number, drawn as written.
    public var isBullet: Bool { marker == "-" || marker == "*" || marker == "+" }
}

/// The constant patterns of `EmbedLocator`; `StaticPatternTests` compiles every case.
enum EmbedLocatorPattern: String, StaticPatternSet {
    case wikiEmbedPattern = #"!\[\[([^\]\n]+)\]\]"#
    case markdownEmbedPattern = #"!\[([^\]\n]*)\]\((<[^<>\n]*>[^)\n]*|[^()\n]*(?:\([^()\n]*\)[^()\n]*)?)\)"#
    /// A list item's marker (and a task's checkbox) before an embed that is all its text.
    case listItemEmbedPattern = #"^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])[ \t]+(?:\[.\][ \t]+)?(!\[\[[^\]\n]+\]\]|!\[[^\]\n]*\]\((?:<[^<>\n]*>[^)\n]*|[^()\n]+(?:\([^()\n]*\)[^()\n]*)?)\))[ \t]*$"#
    case standaloneEmbedPattern = #"^[ \t]*(!\[\[[^\]\n]+\]\]|!\[[^\]\n]*\]\((?:<[^<>\n]*>[^)\n]*|[^()\n]+(?:\([^()\n]*\)[^()\n]*)?)\))[ \t]*$"#
}
