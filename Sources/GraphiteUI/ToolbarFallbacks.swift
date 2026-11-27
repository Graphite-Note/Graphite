/**
 * File: ToolbarFallbacks.swift
 * ----------------------------
 * Layer: UI
 * Description: Items kept in view when the bar is narrow, which macOS has only from 26.1: macOS 26.0 folds
 *              them like any other item.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

import SwiftUI

extension ToolbarContent {
    /// Kept in view when the bar is narrow, where the system can (iOS 27, macOS 26.1); macOS 26.0
    /// folds it like any other item.
    @ToolbarContentBuilder func keptInViewWhenNarrow() -> some ToolbarContent {
        if #available(iOS 27, macOS 26.1, *) {
            visibilityPriority(.high)
        } else {
            self
        }
    }
}
