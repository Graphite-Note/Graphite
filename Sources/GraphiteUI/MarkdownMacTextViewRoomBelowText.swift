/**
 * File: MarkdownMacTextViewRoomBelowText.swift
 * --------------------------------------------
 * Layer: UI
 * Description: Room below the last line of the Mac's note editor, so the end of a note can be scrolled up to the eye.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import AppKit

extension MarkdownMacTextView {
    /// The share of the visible height left below the last line, as Obsidian leaves it: the end
    /// of a note scrolls up to the middle of the editor instead of staying at its bottom edge.
    static let roomBelowTextShareOfVisibleHeight: CGFloat = 0.5

    /// The room below the last line for the editor's present height; none outside a scroll view.
    var roomBelowText: CGFloat {
        guard let clipView = enclosingScrollView?.contentView else { return 0 }
        return (clipView.bounds.height * Self.roomBelowTextShareOfVisibleHeight).rounded()
    }

    /// The editor grew or shrank: the room follows its new height. TextKit sizes the view to its
    /// text again, with the new room, only when the room changed.
    func updateRoomBelowTextForVisibleHeight() {
        guard abs(roomBelowText - appliedRoomBelowText) > 0.5 else { return }
        sizeToFit()
    }
}
#endif
