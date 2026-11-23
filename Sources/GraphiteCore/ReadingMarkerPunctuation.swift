/**
 * File: ReadingMarkerPunctuation.swift
 * ------------------------------------
 * Layer: Core
 * Description: Frames the reading view's inline markers with punctuation while the Markdown is parsed, so bold
 *              and italic beside them open and close as beside the Obsidian syntax they stand for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

/// The reading view writes a color's `~={…}` and `=~`, a highlight's `==`, `<u>`, `<mark>` and
/// `<br>` as `ReadingMarkers`, private-use characters, which CommonMark reads as letters. A `**`
/// between such a marker and punctuation, as in `~={orange}**If $x$**=~` where the formula's
/// `$` is punctuation, then cannot close (or open) bold, and the reading view showed the
/// asterisks. Obsidian's own delimiters are punctuation, so there the `**` is bold.
///
/// `framing(_:)` puts `frame`, a punctuation character, on each side of every such marker
/// before the Markdown is parsed, and `removingFrames(from:)` takes those frames out of the
/// parsed text before the markers are read.
package enum ReadingMarkerPunctuation {
    /// U+2E31 WORD SEPARATOR MIDDLE DOT: punctuation (Po) to CommonMark, and rare in notes.
    /// A note's own one is never next to a marker, since a frame always is.
    package static let frame: Unicode.Scalar = "\u{2E31}"

    /// The markers that stand inside a line for Obsidian syntax made of punctuation.
    private static let inlineMarkers: Set<Unicode.Scalar> = Set([
        ReadingMarkers.colorStartMarker, ReadingMarkers.colorHexEndMarker, ReadingMarkers.colorEndMarker,
        ReadingMarkers.highlightStartMarker, ReadingMarkers.highlightEndMarker,
        ReadingMarkers.underlineStartMarker, ReadingMarkers.underlineEndMarker, ReadingMarkers.lineBreakMarker,
    ].compactMap { marker in marker.unicodeScalars.first })

    /// `markdown` with `frame` before and after each inline marker.
    package static func framing(_ markdown: String) -> String {
        guard markdown.unicodeScalars.contains(where: inlineMarkers.contains) else { return markdown }
        var framed = String.UnicodeScalarView()
        for scalar in markdown.unicodeScalars {
            if inlineMarkers.contains(scalar) {
                framed.append(frame)
                framed.append(scalar)
                framed.append(frame)
            } else {
                framed.append(scalar)
            }
        }
        return String(framed)
    }

    /// Removes the frames `framing(_:)` put beside the markers of `text`, the text parsed
    /// from framed Markdown; a note's own `frame` characters stay.
    package static func removingFrames(from text: inout AttributedString) {
        let scalars = Array(text.unicodeScalars)
        guard scalars.contains(frame) else { return }
        var frameOffsets: [Int] = []
        for (offset, scalar) in scalars.enumerated() where scalar == frame {
            let followsMarker = offset > 0 && inlineMarkers.contains(scalars[offset - 1])
            let precedesMarker = offset + 1 < scalars.count && inlineMarkers.contains(scalars[offset + 1])
            if followsMarker || precedesMarker { frameOffsets.append(offset) }
        }
        // Last first, each index taken from the start, as `ObsidianMarkdownParser` removes markers.
        for offset in frameOffsets.reversed() {
            let frameIndex = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: offset)
            text.removeSubrange(frameIndex..<text.unicodeScalars.index(after: frameIndex))
        }
    }
}
