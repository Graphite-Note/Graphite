/**
 * File: RenderedBlockCaretPlacement.swift
 * ---------------------------------------
 * Layer: UI
 * Description: Where the note's caret goes when it leaves a rendered block, such as a table, by its top or bottom edge.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation

/// Where the caret goes beside a rendered block, as Obsidian puts it when an arrow leaves a
/// table: at the start of the line before the block, or of the line after it. A block that
/// starts the note gets an empty line before it first, and one whose last line ends the note
/// without a line break gets one after it.
struct RenderedBlockCaretPlacement: Equatable {
    /// Where a line break is inserted first, in the source before the insertion; nil for none.
    let lineBreakLocation: Int?
    /// The caret's place, in the source after the insertion.
    let caretLocation: Int

    init(lineBreakLocation: Int?, caretLocation: Int) {
        self.lineBreakLocation = lineBreakLocation
        self.caretLocation = caretLocation
    }

    init(beside blockRange: NSRange, side: RenderedBlockSide, in source: NSString) {
        switch side {
        case .before:
            guard blockRange.location > 0 else {
                lineBreakLocation = 0
                caretLocation = 0
                return
            }
            lineBreakLocation = nil
            caretLocation = source.lineRange(for: NSRange(location: blockRange.location - 1, length: 0)).location
        case .after:
            let lastCharacter = max(NSMaxRange(blockRange) - 1, blockRange.location)
            let lineEnd = lastCharacter < source.length ? NSMaxRange(source.lineRange(for: NSRange(location: lastCharacter, length: 0))) : source.length
            let endsWithLineBreak = lineEnd > 0 && CharacterSet.newlines.contains(UnicodeScalar(source.character(at: lineEnd - 1)) ?? " ")
            lineBreakLocation = endsWithLineBreak ? nil : lineEnd
            caretLocation = endsWithLineBreak ? lineEnd : lineEnd + 1
        }
    }
}
