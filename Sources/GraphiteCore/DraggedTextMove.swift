/**
 * File: DraggedTextMove.swift
 * ---------------------------
 * Layer: Core
 * Description: Text dragged within a note and let go elsewhere in it, as one edit, so the move is one step of the
 *              note's history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

/// Moving a run of a note's text to another place in the same note, as a drag within the
/// editor does. The move is one edit over the span from the first place to the last, so it is
/// one step of the history and undoing it puts the text back where it was.
public enum DraggedTextMove {
    /// The edit that moves `range` of `text` to `location`, a place in the text as it is before
    /// the move, with the moved text selected at its new place. Nil when nothing moves: an empty
    /// range, a range outside the text, or a place inside the range or at one of its edges.
    public static func edit(moving range: NSRange, to location: Int, in text: NSString) -> MarkdownTextEdit? {
        guard range.length > 0, range.location >= 0, NSMaxRange(range) <= text.length, location >= 0, location <= text.length else { return nil }
        guard location < range.location || location > NSMaxRange(range) else { return nil }
        let movedText = text.substring(with: range)
        if location > NSMaxRange(range) {
            // Later in the note: the text between the range and the place moves up in front of it.
            let between = text.substring(with: NSRange(location: NSMaxRange(range), length: location - NSMaxRange(range)))
            let spanned = NSRange(location: range.location, length: location - range.location)
            let movedLocation = range.location + (between as NSString).length
            return MarkdownTextEdit(range: spanned, replacement: between + movedText,
                                    selectionAfter: NSRange(location: movedLocation, length: range.length))
        }
        // Earlier in the note: the moved text goes in front of the text between the place and the range.
        let between = text.substring(with: NSRange(location: location, length: range.location - location))
        let spanned = NSRange(location: location, length: NSMaxRange(range) - location)
        return MarkdownTextEdit(range: spanned, replacement: movedText + between, selectionAfter: NSRange(location: location, length: range.length))
    }
}
