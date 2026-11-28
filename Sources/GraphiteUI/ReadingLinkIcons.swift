/**
 * File: ReadingLinkIcons.swift
 * ----------------------------
 * Layer: UI
 * Description: The icon the reading view puts before a wikilink to a note that has one, as Notion shows a link to a page
 *              and Iconize an icon in Obsidian: an emoji as text, a picture or a symbol as a small picture inside the text.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
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
    static let addressKey = "address"
    /// An icon before a link is as tall as a line's capitals and a little more.
    static let sizeInEms = 1.1

    static func url(of icon: NoteIcon, root: URL, textSize: Double) -> URL? {
        let size = EmbedDisplaySize(width: (textSize * sizeInEms).rounded(), height: nil)
        switch icon {
        case .emoji: return nil
        case .picture(.vaultFile(let linkTarget)):
            guard let path = try? VaultPath(linkTarget), let location = try? path.url(in: root) else { return nil } // Not a vault path: no icon.
            return PreviewImageFragment.url(for: location, displaySize: size, version: 0)
        case .picture(.webAddress(let address)):
            var components = URLComponents()
            components.scheme = scheme; components.host = webHost
            components.queryItems = [URLQueryItem(name: addressKey, value: address.absoluteString)]
            return components.url.map { url in PreviewImageFragment.url(for: url, displaySize: size, version: 0) }
        case .symbol(let systemName):
            var components = URLComponents()
            components.scheme = scheme; components.host = symbolHost; components.path = "/" + systemName
            return components.url.map { url in PreviewImageFragment.url(for: url, displaySize: size, version: 0) }
        }
    }

    /// What an icon address names: a symbol's name, or a picture's web address.
    enum Named: Equatable {
        case symbol(String)
        case webAddress(URL)
    }

    static func named(by location: URL) -> Named? {
        guard location.scheme == scheme else { return nil }
        if location.host == symbolHost { return .symbol(String(location.path.dropFirst())) }
        guard location.host == webHost,
              let text = URLComponents(url: location, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { item in item.name == addressKey })?.value,
              let address = URL(string: text) else { return nil }
        return .webAddress(address)
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
        if case .emoji(let emoji) = icon { return emoji + " " }
        guard let location = NoteIconInlineAddress.url(of: icon, root: root, textSize: configuration.textSize) else { return "" }
        return "![](\(GraphiteOpenLink.markdownDestination(location))) "
    }

    /// A plain page drawn before a link to a note without an icon, as Notion draws a page without one.
    static let pageGlyph = NoteIcon.symbol(systemName: "doc.text")

    func pageGlyphPrefix(configuration: ReadingConfiguration) -> String {
        NoteIconInlineAddress.url(of: Self.pageGlyph, root: configuration.noteIconLinkPrefixes.root ?? URL(fileURLWithPath: "/"),
                                  textSize: configuration.textSize).map { location in "![](\(GraphiteOpenLink.markdownDestination(location))) " } ?? ""
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
