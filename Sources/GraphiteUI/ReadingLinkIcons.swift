/**
 * File: ReadingLinkIcons.swift
 * ----------------------------
 * Layer: UI
 * Description: The icon the reading view puts before a wikilink to a note that has one, as Notion shows a link to a page
 *              and Iconize an icon in Obsidian: an emoji as text, a picture or a symbol as a small picture inside the text.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteIndex

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
}
