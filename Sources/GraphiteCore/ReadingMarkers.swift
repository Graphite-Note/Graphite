/**
 * File: ReadingMarkers.swift
 * --------------------------
 * Layer: Core
 * Description: The private-use characters the reading-view rewrite puts into a note's text, and the escape for the note's own.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import Foundation

/// The private-use characters the reading-view rewrite (`ObsidianInlineMarkup`) puts into a
/// note's text so the renderer's parser keeps colored and highlighted runs, checkboxes and
/// numbered equations in place, and the escape that keeps the note's own such characters
/// apart from them. The reading view and Live Preview both read the markers and restore the
/// escaped characters through this one type.
package enum ReadingMarkers {
    package static let colorStartMarker: Character = "\u{E000}"
    package static let colorHexEndMarker: Character = "\u{E001}"
    package static let colorEndMarker: Character = "\u{E002}"
    package static let highlightStartMarker: Character = "\u{E003}"
    package static let highlightEndMarker: Character = "\u{E004}"
    /// Stand for a task's `[ ]` and `[x]`, which the reading view draws as checkboxes.
    package static let uncheckedTaskMarker: Character = "\u{E005}"
    package static let checkedTaskMarker: Character = "\u{E006}"
    /// Stands for a `<br>` of the note, a line break within a paragraph or a table cell.
    package static let lineBreakMarker: Character = "\u{E007}"
    /// Around text of the note in `<u>`, which is underlined.
    package static let underlineStartMarker: Character = "\u{E00C}"
    package static let underlineEndMarker: Character = "\u{E00D}"
    /// Around a display formula that has equation numbers, kept as written with its `\tag`
    /// commands, which the reading view lays out itself.
    package static let numberedEquationStartMarker: Character = "\u{E00A}"
    package static let numberedEquationEndMarker: Character = "\u{E00B}"
    static let numberedEquationStartScalar: Unicode.Scalar = "\u{E00A}"
    static let numberedEquationEndScalar: Unicode.Scalar = "\u{E00B}"

    /// The markers, U+E000 to U+E007 and U+E00A to U+E00D, the escape lead, U+E009, and the
    /// unused U+E008. A note's own character in this range, such as an icon-font
    /// glyph, is escaped, so it is not turned into a checkbox or a color that deletes the
    /// text after it.
    private static let escapedScalarValues: ClosedRange<UInt32> = 0xE000...0xE00D
    package static let escapeLead: Unicode.Scalar = "\u{E009}"
    /// A character `escapedScalarValues.lowerBound + n` is written as the lead, then the
    /// scalar `standInOffset` above it. Stand-ins follow a lead only when written here.
    private static let standInOffset: UInt32 = 0x10

    /// `text` with each character in the marker range written as the escape lead followed
    /// by a stand-in; `original(ofStandIn:)` gives the character back.
    package static func escaping(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { scalar in escapedScalarValues.contains(scalar.value) }) else { return text }
        var escaped = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if escapedScalarValues.contains(scalar.value), let standIn = Unicode.Scalar(scalar.value + standInOffset) {
                escaped.append(escapeLead)
                escaped.append(standIn)
            } else {
                escaped.append(scalar)
            }
        }
        return String(escaped)
    }

    /// The character an escape lead followed by `standIn` stands for, or nil when `standIn`
    /// is not a stand-in.
    package static func original(ofStandIn standIn: Unicode.Scalar) -> Unicode.Scalar? {
        guard standIn.value >= standInOffset, escapedScalarValues.contains(standIn.value - standInOffset) else { return nil }
        return Unicode.Scalar(standIn.value - standInOffset)
    }
}
