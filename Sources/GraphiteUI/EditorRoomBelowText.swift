/**
 * File: EditorRoomBelowText.swift
 * -------------------------------
 * Layer: UI
 * Description: How much room the note editor leaves below a note's last line, on the iPad, the iPhone and the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import CoreGraphics

/// The room below a note's last line, as Obsidian leaves it: scrolled to its end, a note's last
/// line stops at the middle of the editor instead of at its bottom edge, so the end of a note
/// being written can be brought up to the eye.
enum EditorRoomBelowText {
    /// The share of the editor's height left below the last line.
    static let shareOfVisibleHeight: CGFloat = 0.5

    /// The room below the last line of an editor this tall.
    static func height(forVisibleHeight visibleHeight: CGFloat) -> CGFloat {
        (max(visibleHeight, 0) * shareOfVisibleHeight).rounded()
    }
}
