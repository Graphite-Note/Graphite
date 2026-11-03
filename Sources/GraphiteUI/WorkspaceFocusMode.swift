/**
 * File: WorkspaceFocusMode.swift
 * ------------------------------
 * Layer: UI
 * Description: Focus mode: hides the sidebars and tabs, remembering the panel layout to restore.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI

/// Remembers the panel layout for one window while its documents stay mounted.
struct WorkspaceFocusMode {
    private(set) var isActive = false
    private var previousColumnVisibility = NavigationSplitViewVisibility.automatic
    private var previouslyShowedInspector = false

    /// Whether the window offers Focus: not at a compact width, where the file list is already a
    /// stack beside the document and there is no tab bar to hide, so entering it would change
    /// nothing visible and leave the window holding a state it cannot show or end.
    static func isOffered(isCompactWidth: Bool) -> Bool { !isCompactWidth }

    /// Leaves Focus when the window becomes compact (a rotation, a Stage Manager resize), since
    /// the compact layout has no Exit Focus button.
    mutating func widthDidChange(isCompactWidth: Bool, columnVisibility: inout NavigationSplitViewVisibility, showsInspector: inout Bool) {
        guard !Self.isOffered(isCompactWidth: isCompactWidth) else { return }
        leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
    }

    mutating func enter(columnVisibility: inout NavigationSplitViewVisibility, showsInspector: inout Bool) {
        guard !isActive else { return }
        previousColumnVisibility = columnVisibility
        previouslyShowedInspector = showsInspector
        isActive = true
        columnVisibility = .detailOnly
        showsInspector = false
    }

    mutating func leave(columnVisibility: inout NavigationSplitViewVisibility, showsInspector: inout Bool) {
        guard isActive else { return }
        isActive = false
        columnVisibility = previousColumnVisibility
        showsInspector = previouslyShowedInspector
    }
}
