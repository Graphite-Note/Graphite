/**
 * File: ReadingLinkIcons.swift
 * ----------------------------
 * Layer: UI
 * Description: The emoji icon the reading view puts before a wikilink to a note that has one, as Iconize shows it in
 *              Obsidian, and when the build reads every wikilink of a note at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteIndex

extension ReadingConfiguration {
    /// Whether the build answers every wikilink of the note in one read of the index: a theme marks those no file
    /// answers, and links to notes with an emoji icon show it. Neither costs a read in a vault without them.
    var resolvesEveryWikilink: Bool { marksUnresolvedLinks || !noteIconLinkPrefixes.emojiByPath.isEmpty }
}

extension ReadingViewBuilder {
    /// The linked note's emoji and a space, or nothing: for an embed, a link inside the note, a note without an emoji
    /// icon, or while icons are off.
    func iconPrefix(ofLinkTo link: NoteLink, note: VaultPath, root: URL, index: VaultIndex,
                    configuration: ReadingConfiguration) async -> String {
        guard !configuration.noteIconLinkPrefixes.emojiByPath.isEmpty, !link.isEmbed, !link.target.hasPrefix("#"),
              let linkedNote = await resolve(link.target, isWiki: link.isWiki, note: note, root: root, index: index),
              let emoji = configuration.noteIconLinkPrefixes.emojiByPath[linkedNote] else { return "" }
        return emoji + " "
    }
}
