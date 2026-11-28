/**
 * File: ReadingLinkIcons.swift
 * ----------------------------
 * Layer: UI
 * Description: The icon the reading view puts before a wikilink to a note that has one, as Notion shows a link to a page
 *              and Iconize an icon in Obsidian: an emoji as text, a picture or a symbol as a small picture inside the text.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 28/11/2026
 */

import Foundation
import GraphiteCore

extension ReadingConfiguration {
    /// Whether the build answers every wikilink of the note in one read of the index: a theme marks those no file
    /// answers, and links to notes with an icon show it. Neither costs a read in a vault without them.
    var resolvesEveryWikilink: Bool { marksUnresolvedLinks || !noteIconLinkPrefixes.iconsByPath.isEmpty }
}

/// The addresses of icons drawn inside the reading view's text that are not files of the vault: an SF Symbol, or a
/// picture of the web. `VaultImageLoader` draws them through the window's `NoteIconPictures`.
enum NoteIconInlineAddress {
    static let scheme = "graphite-note-icon"
    static let symbolHost = "symbol"
    static let webHost = "web"
    static let emojiHost = "emoji"
    static let vaultHost = "vault"
    static let addressKey = "address"
    /// Every icon before a link takes the same square, 1.25 em as Notion's 20-point icons beside its 16-pixel text, so
    /// the lines of a list of links are as tall as each other and their text starts at the same place.
    static let sizeInEms = 1.25
    /// How far below the baseline the square starts, as a share of its side: an emoji's own place on the line.
    static let shareBelowBaseline = 0.18

    /// The square is given at the default text size, as a picture's `|width` is: the text's attachment scale (the note's
    /// zoom, `NoteFontSize.zoomScale`) grows it with the text, which a note built once is not built again for.
    static func url(of icon: NoteIcon, root: URL) -> URL? {
        let size = EmbedDisplaySize(width: (Double(NoteFontSize.defaultSize) * sizeInEms).rounded(), height: nil)
        var components = URLComponents()
        components.scheme = scheme
        switch icon {
        case .emoji(let emoji):
            components.host = emojiHost; components.queryItems = [URLQueryItem(name: addressKey, value: emoji)]
        case .picture(.vaultFile(let linkTarget)):
            guard let path = try? VaultPath(linkTarget), let location = try? path.url(in: root) else { return nil } // Not a vault path: no icon.
            components.host = vaultHost; components.queryItems = [URLQueryItem(name: addressKey, value: location.path)]
        case .picture(.webAddress(let address)):
            components.host = webHost; components.queryItems = [URLQueryItem(name: addressKey, value: address.absoluteString)]
        case .symbol(let systemName):
            components.host = symbolHost; components.path = "/" + systemName
        }
        return components.url.map { url in PreviewImageFragment.url(for: url, displaySize: size, version: 0) }
    }

    /// What an icon address names.
    enum Named: Equatable {
        case symbol(String)
        case webAddress(URL)
        case emoji(String)
        case vaultFile(URL)
    }

    static func named(by location: URL) -> Named? {
        guard location.scheme == scheme else { return nil }
        if location.host == symbolHost { return .symbol(String(location.path.dropFirst())) }
        guard let text = URLComponents(url: location, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { item in item.name == addressKey })?.value
        else { return nil }
        switch location.host {
        case emojiHost: return .emoji(text)
        case vaultHost: return .vaultFile(URL(fileURLWithPath: text))
        case webHost: return URL(string: text).map(Named.webAddress)
        default: return nil
        }
    }
}

extension ReadingViewBuilder {
    /// The linked note's icon and a space, written before the link, or nothing: for an embed, a link inside the note, a
    /// note without an icon, or while icons are off.
    func iconPrefix(ofLinkTo link: NoteLink, note: VaultPath, root: URL, index: some ReadingFileLookup,
                    configuration: ReadingConfiguration) async -> String {
        guard !configuration.noteIconLinkPrefixes.iconsByPath.isEmpty, !link.isEmbed, !link.target.hasPrefix("#"),
              let linkedNote = await resolve(link.target, isWiki: link.isWiki, note: note, root: root, index: index),
              let icon = configuration.noteIconLinkPrefixes.iconsByPath[linkedNote] else { return "" }
        guard let location = NoteIconInlineAddress.url(of: icon, root: root) else { return "" }
        // An emoji is its picture's description, which reads it aloud and copies it.
        let description = if case .emoji(let emoji) = icon { emoji } else { "" }
        return "![\(description)](\(GraphiteOpenLink.markdownDestination(location))) "
    }

    /// A plain page drawn before a link to a note without an icon, as Notion draws a page without one.
    static let pageGlyph = NoteIcon.symbol(systemName: "doc.text")

    func pageGlyphPrefix(configuration: ReadingConfiguration) -> String {
        NoteIconInlineAddress.url(of: Self.pageGlyph, root: configuration.noteIconLinkPrefixes.root ?? URL(fileURLWithPath: "/"))
            .map { location in "![](\(GraphiteOpenLink.markdownDestination(location))) " } ?? ""
    }

    /// Where the links that get `pageGlyph` start in `markdown`: those alone on a line of a list of two or more such lines
    /// (`CompactLinkLines.isLinkLine`) where another line's link shows an icon, so the list's text lines up as in Notion.
    /// Links in prose, and lists where no link has an icon, are left as they are.
    func linksWithoutIconInIconLists(_ links: [NoteLink], in markdown: String, paddingLength: Int, note: VaultPath, root: URL,
                                     index: some ReadingFileLookup, configuration: ReadingConfiguration) async -> Set<Int> {
        guard !configuration.noteIconLinkPrefixes.iconsByPath.isEmpty, markdown.contains("[[") else { return [] }
        let text = markdown as NSString
        var lists: [[NoteLink]] = [[]]
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let linkOnLine = links.first { link in
                link.isWiki && !link.isEmbed && NSLocationInRange(link.location - paddingLength, lineRange)
            }
            if CompactLinkLines.isLinkLine(line), let linkOnLine {
                lists[lists.count - 1].append(linkOnLine)
            } else if !lists[lists.count - 1].isEmpty {
                lists.append([])
            }
        }
        var locations: Set<Int> = []
        for list in lists where list.count > 1 {
            var withoutIcon: [Int] = []
            for link in list {
                let icon = await iconPrefix(ofLinkTo: link, note: note, root: root, index: index, configuration: configuration)
                if icon.isEmpty { withoutIcon.append(link.location - paddingLength) }
            }
            if withoutIcon.count < list.count { locations.formUnion(withoutIcon) }
        }
        return locations
    }
}

extension ReadingViewBuilder {
    /// Records the weights of a multi-column callout's columns, read from each column's callout header in the note
    /// (`> > [!blank|wide-2]`); nothing for columns that are all even.
    func recordColumnWeights(of blockIdentifier: String, columns: [NotePreviewDocument.LocatedBlock], taskSource: ReadingTaskSource) {
        let noteText = taskSource.noteText as NSString
        let weights = columns.map { column -> Int in
            guard case .callout = column.block, let offset = taskSource.noteOffset(column.startOffset) else { return 1 }
            return CalloutColumnArrangement.weight(ofColumnStartingAt: offset, in: noteText)
        }
        if weights.contains(where: { weight in weight != 1 }) { columnWeightsByBlock[blockIdentifier] = weights }
    }
}

/// Paragraphs of the reading view's text whose every line is an icon, a space and one link, as a list of links to notes
/// is drawn with icons on (`CompactLinkLines`). Notion keeps each such line on one line and cuts it with an ellipsis in
/// a narrow column, where a wrapped line would start again under the icon. Paragraphs in a list item or a table, and
/// lines with other text beside their link, are left to wrap.
enum ReadingIconLinkLines {
    static func paragraphRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        guard text.runs[\.imageURL].contains(where: { imageURL, _ in imageURL?.scheme == NoteIconInlineAddress.scheme }) else { return [] }
        var ranges: [Range<AttributedString.Index>] = []
        for (intent, range) in text.runs[\.presentationIntent] {
            guard let intent, intent.components.first?.kind == .paragraph,
                  !intent.components.contains(where: { component in Self.wrapsItsLines(component.kind) }),
                  isIconLinkParagraph(text[range]) else { continue }
            ranges.append(range)
        }
        return ranges
    }

    private static func wrapsItsLines(_ kind: PresentationIntent.Kind) -> Bool {
        switch kind {
        case .listItem, .tableCell, .tableRow, .tableHeaderRow, .table: true
        default: false
        }
    }

    /// Whether each line of `paragraph` (its hard line breaks) is an icon of `NoteIconInlineAddress`, then one link.
    static func isIconLinkParagraph(_ paragraph: AttributedSubstring) -> Bool {
        var hasIcon = false
        var link: URL?
        func lineEnds() -> Bool {
            defer { hasIcon = false; link = nil }
            return hasIcon && link != nil
        }
        for run in paragraph.runs {
            let segments = String(paragraph[run.range].characters).split(separator: "\n", omittingEmptySubsequences: false)
            for (segmentIndex, segment) in segments.enumerated() {
                if segmentIndex > 0, !lineEnds() { return false }
                if segment.allSatisfy(\.isWhitespace) { continue }
                if run.imageURL?.scheme == NoteIconInlineAddress.scheme, !hasIcon, link == nil {
                    hasIcon = true
                } else if let runLink = run.link, hasIcon, link == nil || link == runLink {
                    link = runLink
                } else {
                    return false
                }
            }
        }
        return lineEnds()
    }
}
