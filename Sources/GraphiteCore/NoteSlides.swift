/**
 * File: NoteSlides.swift
 * ----------------------
 * Layer: Core
 * Description: A note split into the slides it is presented as, by the rule of Obsidian's Slides core plugin:
 *              a new slide at each thematic break at the top level of the note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// One slide of a note presented as slides: the note's text between two separators.
public struct NoteSlide: Equatable, Sendable {
    /// Where the slide's text is in the note, in UTF-16 offsets, its separators left out.
    public let noteRange: NSRange
    /// The slide's text as it is built for reading: the note's text in `noteRange`, then the note's link
    /// reference definitions the slide uses and does not define, so a `[text][label]` link works on any slide.
    public let markdown: String
}

/// Splits a note into slides as Obsidian's Slides core plugin does (Obsidian 1.15.1, `slides:start`): it walks
/// the top-level blocks of the note's Markdown tree and starts a new slide at each thematic break, so `---`,
/// `***`, `___` and their spaced forms separate slides, but not a `---` that underlines a heading, nor one in
/// code, math, a quote, a callout, a comment or a list item. The frontmatter is left out. A slide with nothing
/// to draw is skipped, where Obsidian skips only one with no block at all (Docs/Present-a-note-todo.md,
/// decision 1).
public enum NoteSlides {
    /// The slides of `note`, in order; a note without separators is one slide, and a note with nothing to
    /// draw has none.
    public static func slides(in note: String) -> [NoteSlide] {
        let text = note as NSString
        let bodyStart = FrontmatterLocator.length(in: text)
        let definitions = ReferenceLinkDefinitions.definitions(in: text.substring(from: bodyStart))
        var slides: [NoteSlide] = []
        var slideStart = bodyStart
        for separator in separatorRanges(in: text) + [NSRange(location: text.length, length: 0)] {
            let slideRange = NSRange(location: slideStart, length: max(0, separator.location - slideStart))
            slideStart = NSMaxRange(separator)
            let slideText = text.substring(with: slideRange)
            guard hasSomethingToDraw(slideText) else { continue }
            slides.append(NoteSlide(noteRange: slideRange,
                                    markdown: ReferenceLinkDefinitions.appendingDefinitions(definitions, neededBy: slideText)))
        }
        return slides
    }

    /// The lines of the note that separate slides, each with its line break: the rules Live Preview and the
    /// reading view find (`LivePreviewBlockScanner`), less those inside a list item, which belong to the item.
    static func separatorRanges(in text: NSString) -> [NSRange] {
        LivePreviewBlockScanner.blocks(in: text).compactMap { block in
            guard case .horizontalRule = block.kind,
                  ListItemContainers.containerColumn(ofLineAt: block.range.location, in: text) == 0 else { return nil }
            return block.range
        }
    }

    /// Whether a slide's text draws anything: not only blank lines and `%%` comments.
    private static func hasSomethingToDraw(_ slideText: String) -> Bool {
        !ObsidianComments.removingComments(from: slideText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
