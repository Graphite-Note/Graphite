/**
 * File: NoteIcon.swift
 * --------------------
 * Layer: Core
 * Description: A note's icon as its `icon` property writes it: an emoji, an SF Symbol name, or a Lucide name of
 *              Iconize's built-in pack (`LiBookOpen`), read once into a value the file list, tabs, the quick
 *              switcher, links and Library mode draw.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// The icon a note's `icon` property names, as Graphite draws it.
public enum NoteIcon: Hashable, Sendable {
    /// One emoji, drawn as text.
    case emoji(String)
    /// An SF Symbol, named as the system names it (`book.closed`).
    case symbol(systemName: String)
    /// A picture of the vault or of the web, written as a `banner` is (`[[clock.gif]]`, a web address), as the Notion
    /// importer writes a page's own icon.
    case picture(NoteBanner.Source)

    /// The property that holds a note's icon: Iconize's default frontmatter field, which Pixel Banner also reads.
    public static let propertyKey = "icon"

    /// At most this many characters of a property's text are looked at: an icon is one emoji or one symbol name.
    static let maximumReadCharacters = 80

    /// At most this many characters of a picture icon's text are read: a link or a web address.
    static let maximumPictureCharacters = 2_048

    /// The icon `propertyText` names, or nil when it names none Graphite can draw: empty text, an icon of an
    /// Iconize pack other than Lucide's, a Lucide name without an SF Symbol in `NoteIconSymbols`, or a link to a file
    /// that is not a picture.
    public init?(propertyText: String) {
        let trimmed = Self.unquoted(String(propertyText.prefix(Self.maximumReadCharacters)).trimmingCharacters(in: .whitespacesAndNewlines))
        guard let first = trimmed.first else { return nil }
        if Self.isEmoji(first) {
            self = .emoji(String(first))
        } else if let picture = Self.picture(in: String(propertyText.prefix(Self.maximumPictureCharacters))) {
            self = .picture(picture)
        } else if let systemName = NoteIconSymbols.systemName(forIconizeName: trimmed) {
            self = .symbol(systemName: systemName)
        } else if Self.isSymbolName(trimmed) {
            self = .symbol(systemName: trimmed)
        } else {
            return nil
        }
    }

    /// The text written into the `icon` property for this icon: the emoji, or for a symbol the Lucide name Iconize
    /// draws in Obsidian when the symbol has one, else the SF Symbol's own name.
    public var propertyText: String {
        switch self {
        case .emoji(let emoji): emoji
        case .symbol(let systemName): NoteIconSymbols.iconizeName(forSystemName: systemName) ?? systemName
        case .picture(.vaultFile(let linkTarget)): "[[\(linkTarget)]]"
        case .picture(.webAddress(let address)): address.absoluteString
        }
    }

    /// The picture a text names as a `banner` names one: a vault file only when its name is a picture's, so a link to a
    /// note is no icon.
    static func picture(in text: String) -> NoteBanner.Source? {
        guard let source = NoteBanner.source(ofBannerText: Self.unquoted(text.trimmingCharacters(in: .whitespacesAndNewlines))) else { return nil }
        switch source {
        case .webAddress: return source
        case .vaultFile(let linkTarget):
            return DocumentKind(fileExtension: (linkTarget as NSString).pathExtension) == .image ? source : nil
        }
    }

    /// Whether `character` is drawn as an emoji: a scalar with emoji presentation, or one made an emoji by the
    /// variation selector, a skin tone or a joiner sequence. Digits and `#`, which Unicode also counts as emoji,
    /// are emoji only with their keycap.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let firstScalar = scalars.first, firstScalar.properties.isEmoji else { return false }
        if firstScalar.properties.isEmojiPresentation { return true }
        return scalars.count > 1
    }

    /// Whether `text` has the shape of an SF Symbol name: lower-case words of letters and digits joined by dots.
    /// Whether the system has a symbol of that name is known only where it is drawn.
    static func isSymbolName(_ text: String) -> Bool {
        guard text.first?.isLetter == true else { return false }
        return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { word in
            !word.isEmpty && word.allSatisfy { character in
                character.isASCII && (character.isLowercase || character.isNumber)
            }
        }
    }

    /// `text` without one pair of surrounding quotes, as a value copied from YAML may keep them.
    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }
}
