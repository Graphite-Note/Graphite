/**
 * File: CalloutIconTitle.swift
 * ----------------------------
 * Layer: Core
 * Description: Callouts drawn as Notion draws its callouts, an icon before the body and no title row: one whose title is a
 *              single emoji (`> [!tip] 💡`), and one whose metadata says `no-title` (`> [!info|no-title]`), with the type's
 *              own glyph. The Notion importer writes both.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import Foundation

public enum CalloutIconTitle {
    /// The emoji a callout's title is made of alone, spaces aside; nil for any other title, or for a character that is
    /// an emoji only when asked to be and was not (a digit, `#`, `©` without its emoji variation selector).
    public static func emoji(in title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 1, let character = trimmed.first, let first = character.unicodeScalars.first, first.properties.isEmoji else { return nil }
        if first.properties.isEmojiPresentation { return trimmed }
        // A text-default emoji asked to draw as one (U+FE0F), a keycap, or a sequence joined into one emoji.
        let drawsAsEmoji = character.unicodeScalars.contains { scalar in
            scalar.value == 0xFE0F || scalar.value == 0x20E3 || scalar.value == 0x200D || scalar.properties.isEmojiModifier
        }
        return drawsAsEmoji ? trimmed : nil
    }

    /// The metadata word, after the type's `|`, that draws a callout without its title row, as some Obsidian themes do.
    public static let noTitleWord = "no-title"

    /// Whether a callout's metadata (`wide-2 no-title`, words split by spaces or commas) holds `noTitleWord`.
    public static func hidesTitle(metadata: String) -> Bool {
        metadata.split(whereSeparator: { character in character == " " || character == "," }).contains { word in word.lowercased() == noTitleWord }
    }

    /// The title a callout block is drawn with: empty for `no-title` over a body and without a fold, so its type's glyph
    /// stands on the body's first line, else `title`. No other callout has an empty title: one written without a title
    /// takes its type's name, so a native `> [!info]` keeps its "Info" row.
    public static func shownTitle(_ title: String, metadata: String, folding: CalloutFolding, bodyLines: [String]) -> String {
        let hidesIt = hidesTitle(metadata: metadata) && folding == .notFoldable
            && bodyLines.contains { bodyLine in !bodyLine.trimmingCharacters(in: .whitespaces).isEmpty }
        return hidesIt ? "" : title
    }
}
