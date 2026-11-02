/**
 * File: PencilToolRowLayout.swift
 * -------------------------------
 * Layer: UI
 * Description: Which of the Pencil bar's tools stay on a narrow bar and which move into the one control that opens the
 *              rest, and how wide the bar's compact row is, so a bar never has to scroll sideways.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics

/// The pure part of the Pencil bar's narrow forms: nothing here draws.
enum PencilToolRowLayout {
    /// A tool of the bar's row: one of the ink presets by position, or one of the other tools.
    enum Tool: Hashable {
        case preset(index: Int)
        case eraser, lasso, laser, text, readAloud
    }

    /// One tool's button with the gap that follows it (`PencilToolbarMetrics.buttonSide` and the row's spacing).
    static let toolSlotWidth: CGFloat = 38
    /// What the compact row spends besides its tools: the row's side padding, the separator, and the one control for
    /// the rest (44 points).
    static let compactRowFixedWidth: CGFloat = 81

    /// The tools of the row in the order the bar shows them: the presets, the eraser, the lasso, the laser pointer,
    /// then the text tool and the Read Aloud pen where the page has them.
    static func tools(presetCount: Int, offersTextBoxes: Bool, offersReadAloudPen: Bool) -> [Tool] {
        var tools = (0..<max(presetCount, 0)).map { presetIndex in Tool.preset(index: presetIndex) }
        tools += [.eraser, .lasso, .laser]
        if offersTextBoxes { tools.append(.text) }
        if offersReadAloudPen { tools.append(.readAloud) }
        return tools
    }

    /// The width the compact row needs to show `toolCount` tools and its one control.
    static func compactRowWidth(toolCount: Int) -> CGFloat {
        CGFloat(max(toolCount, 0)) * toolSlotWidth + compactRowFixedWidth
    }

    /// Which tools a bar that keeps room for `shownCount` of them shows, and which it folds into its control. The tools
    /// shown are the first ones, but the tool in use is always among them: it takes the last place when it would have
    /// been folded, so the person always sees what they write with.
    /// - Parameters:
    ///   - tools: Every tool of the row, in order.
    ///   - shownCount: How many the bar has room for; at least one is always shown.
    ///   - toolInUse: The tool in use, nil when it is not among `tools` (the Read Aloud pen on a page without text).
    static func split(_ tools: [Tool], showing shownCount: Int, toolInUse: Tool?) -> (shown: [Tool], folded: [Tool]) {
        let limit = max(1, min(shownCount, tools.count))
        guard limit < tools.count else { return (tools, []) }
        var kept = Set(tools.prefix(limit))
        if let toolInUse, tools.contains(toolInUse), !kept.contains(toolInUse), let lastKept = tools.prefix(limit).last {
            kept.remove(lastKept)
            kept.insert(toolInUse)
        }
        return (tools.filter { tool in kept.contains(tool) }, tools.filter { tool in !kept.contains(tool) })
    }
}
