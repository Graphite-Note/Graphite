/**
 * File: ToolbarFallbacks.swift
 * ----------------------------
 * Layer: UI
 * Description: Toolbar parts the system has only from iOS 27 and macOS 26.1, with what iOS 26 and macOS 26.0
 *              show instead: the More commands, and items kept in view when the bar is narrow.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

import SwiftUI

extension ToolbarContent {
    /// Kept in view when the bar is narrow, where the system can (iOS 27, macOS 26.1); earlier
    /// systems fold it like any other item.
    @ToolbarContentBuilder func keptInViewWhenNarrow() -> some ToolbarContent {
        if #available(iOS 27, macOS 26.1, *) {
            visibilityPriority(.high)
        } else {
            self
        }
    }
}

#if os(iOS)

struct MoreToolbarMenu<Items: View>: ToolbarContent {
    @ViewBuilder let items: () -> Items

    var body: some ToolbarContent {
        if #available(iOS 27, *) {
            ToolbarOverflowMenu { items() }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") { items() }.tint(.primary)
            }
        }
    }
}
#endif
