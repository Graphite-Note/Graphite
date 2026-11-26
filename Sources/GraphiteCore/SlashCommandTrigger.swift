/**
 * File: SlashCommandTrigger.swift
 * -------------------------------
 * Layer: Core
 * Description: Finding a `/` typed to open the slash commands, and the letters typed after it, as Obsidian's
 *              Slash commands core plugin reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// A `/` typed to open the slash commands, and what was typed after it.
public struct SlashCommandQuery: Equatable, Sendable {
    /// The letters after the `/`, up to the cursor.
    public let text: String
    /// The `/` and the letters after it, which are taken out when an entry is chosen.
    public let replacementRange: NSRange

    public init(text: String, replacementRange: NSRange) {
        self.text = text
        self.replacementRange = replacementRange
    }
}

/// Obsidian's rule for its Slash commands core plugin: the line before the cursor ends with
/// `(^|\s)\/([^\s\/]*)$`, a `/` at the start of the line or after a space, then letters with
/// no space and no other `/`. Graphite also opens nothing in code, display math or the
/// frontmatter, where `/usr/bin` and `// note` are common and Return must start a line
/// (Docs/Slash-menu-and-block-handles-todo.md, decision 3): the block a line is in comes from
/// `MarkdownStyleScanner`'s block context, and inline code from the cursor's line alone.
public enum SlashCommandTrigger {
    /// A longer run after `/` is a path or an address, not a command being looked for.
    static let maximumQueryLength = 64
    private static let slash: unichar = 0x2F

    /// The slash command query typed before `cursor`, or nil when the text there does not open one.
    /// - Parameter blockContext: The block the line starting at the given location is in. An
    ///   editor answers from the checkpoints it keeps for styling, so a key typed in a long note
    ///   does not read the note again; asked only once a `/` is found.
    public static func query(in text: NSString, cursor: Int, blockContext: (Int) -> MarkdownBlockContext) -> SlashCommandQuery? {
        guard cursor > 0, cursor <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        guard let slashLocation = slashLocation(before: cursor, lineStart: lineRange.location, in: text),
              blockContext(lineRange.location) == .normal, !isInInlineCode(text, lineRange: lineRange, cursor: cursor) else { return nil }
        let queryStart = slashLocation + 1
        return SlashCommandQuery(text: text.substring(with: NSRange(location: queryStart, length: cursor - queryStart)),
                                 replacementRange: NSRange(location: slashLocation, length: cursor - slashLocation))
    }

    /// The query typed before `cursor`, the block context read from the top of the text.
    public static func query(in text: NSString, cursor: Int) -> SlashCommandQuery? {
        query(in: text, cursor: cursor) { lineStart in
            MarkdownStyleScanner.blockCheckpoint(atLineStart: lineStart, in: text, resumingFrom: nil).context
        }
    }

    /// Whether inline code on the cursor's line holds it, as `` `ls /tmp` ``.
    private static func isInInlineCode(_ text: NSString, lineRange: NSRange, cursor: Int) -> Bool {
        let localCursor = cursor - lineRange.location
        return MarkdownCodeRanges.ranges(in: text.substring(with: lineRange) as NSString).contains { range in
            range.location < localCursor && localCursor <= NSMaxRange(range)
        }
    }

    /// Where the `/` that starts the query is: the nearest before the cursor on its line, with
    /// no space between it and the cursor, and at the line's start or after a space.
    private static func slashLocation(before cursor: Int, lineStart: Int, in text: NSString) -> Int? {
        let lowerLimit = max(lineStart, cursor - maximumQueryLength - 1)
        var index = cursor - 1
        while index >= lowerLimit {
            let character = text.character(at: index)
            if character == slash {
                guard index == lineStart || isWhitespace(text.character(at: index - 1)) else { return nil }
                return index
            }
            if isWhitespace(character) { return nil }
            index -= 1
        }
        return nil
    }

    /// JavaScript's `\s` for one UTF-16 unit: spaces of every width, tabs and line breaks.
    static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "\u{FEFF}"
    }
}
