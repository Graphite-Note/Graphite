/**
 * File: PencilToolRowLayout.swift
 * -------------------------------
 * Layer: UI
 * Description: The Pencil bar's forms and how closely it sets its buttons: which tools, sizes, colors and toggles a bar
 *              of a given width shows, how wide each form is, and which tools move into the one control that opens the
 *              rest, so a bar never has to scroll sideways past its colors.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 04/11/2026
 */

/// The pure part of the Pencil bar's forms: nothing here draws. The bar (`PencilToolRow`) builds each form at the widths
/// given here, so the widths below are the bar's own, and tries them in `preferredArrangements`' order.
enum PencilToolRowLayout {
    /// A tool of the bar's row: one of the ink presets by position, or one of the other tools.
    enum Tool: Hashable {
        case preset(index: Int)
        case eraser, lasso, laser, text, readAloud
    }

    /// The tools of the row in the order the bar shows them: the presets, the eraser, the lasso, the laser pointer,
    /// then the text tool and the Read Aloud pen where the page has them.
    static func tools(presetCount: Int, offersTextBoxes: Bool, offersReadAloudPen: Bool) -> [Tool] {
        var tools = (0..<max(presetCount, 0)).map { presetIndex in Tool.preset(index: presetIndex) }
        tools += [.eraser, .lasso, .laser]
        if offersTextBoxes { tools.append(.text) }
        if offersReadAloudPen { tools.append(.readAloud) }
        return tools
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

    /// The tools the compact form keeps on the bar: the ones a person writes with (every ink preset, the eraser and the
    /// lasso), and the tool in use wherever it is, in the bar's order. The laser pointer, the text tool and the Read
    /// Aloud pen, used now and then rather than while writing, go behind the More control.
    static func compactSplit(_ tools: [Tool], toolInUse: Tool?) -> (shown: [Tool], folded: [Tool]) {
        let shown = tools.filter { tool in
            switch tool {
            case .preset, .eraser, .lasso: true
            case .laser, .text, .readAloud: tool == toolInUse
            }
        }
        return (shown, tools.filter { tool in !shown.contains(tool) })
    }

    // MARK: Densities and forms

    /// How closely the bar sets its buttons. Each button is touched over the row's whole height and its own width; a
    /// narrower bar puts them closer and draws the color dots smaller before it moves anything into a menu.
    struct Density: Hashable {
        /// The width of a tool, a toggle, Add Image or the More control.
        let toolPitch: Double
        /// The width of each of the three sizes.
        let sizePitch: Double
        /// The width of a color, its dot centered in it.
        let swatchPitch: Double
        let swatchDiameter: Double
        /// A hairline with room on both sides.
        let separatorWidth: Double
        /// The room at each end of the row.
        let edgeInset: Double

        static let regular = Density(toolPitch: 36, sizePitch: 36, swatchPitch: 32, swatchDiameter: 22, separatorWidth: 13, edgeInset: 10)
        static let tight = Density(toolPitch: 32, sizePitch: 30, swatchPitch: 28, swatchDiameter: 20, separatorWidth: 9, edgeInset: 6)
        /// Mini colors: 16-point dots 22 points apart, the closest a finger still picks one from its neighbors.
        static let tightest = Density(toolPitch: 28, sizePitch: 26, swatchPitch: 22, swatchDiameter: 16, separatorWidth: 5, edgeInset: 4)

        /// The ring around the color in use, three points clear of its dot on each side.
        var swatchRingDiameter: Double { swatchDiameter + 6 }
        /// Other Color, the system's color well, which draws its own wheel and needs 28 points.
        var otherColorWidth: Double { max(swatchPitch, 28) }
        /// The side of a tool's or a size's selected fill: the pitch, at most the 36-point button.
        var toolSide: Double { min(toolPitch, 36) }
        var sizeSide: Double { min(sizePitch, 36) }
    }

    /// One form of the bar at one density.
    enum Arrangement: Hashable {
        /// Everything on the bar: every tool, the tool's own choices and sizes, every color with Other Color and the
        /// plus, Shapes, Ruler and Add Image. Nothing is behind a menu.
        case whole(Density)
        /// The tools a person writes with (`compactSplit`), the sizes, every color and the ruler on the bar; the other
        /// tools, the tool's own choices, Other Color with the plus, Shapes and Add Image behind one More control.
        case compact(Density)
        /// The compact form with its colors in a strip that scrolls sideways, as wide as `visibleSwatchCount` whole
        /// colors, so none is ever cut in half: only where every color does not fit even at the mini size.
        case compactWithScrollingColors(visibleSwatchCount: Int)
        /// Fewer tools, with the rest, the colors and the toggles behind one control: a window too narrow for any other.
        case condensed
    }

    /// The forms the bar tries, widest first, before the scrolling colors and the condensed form; the first that fits
    /// is shown. Spacing, button widths and dot sizes shrink before anything moves into the More control.
    static let preferredArrangements: [Arrangement] = [.whole(.regular), .whole(.tight), .whole(.tightest), .compact(.tight), .compact(.tightest)]

    /// The fewest colors a scrolling strip shows; narrower than that the colors go behind the condensed form's control.
    static let minimumVisibleSwatchCount = 3

    /// What a bar holds, counted for its widths.
    struct Contents: Equatable {
        /// Every tool of the row, in order (`tools(presetCount:offersTextBoxes:offersReadAloudPen:)`).
        var tools: [Tool]
        var toolInUse: Tool?
        /// Three for an ink or the eraser; none for the other tools, which have no width.
        var sizeCount: Int
        /// Whether the tool in use takes a color: not the laser pointer, the text tool or the Read Aloud pen.
        var offersColors: Bool
        /// Black and the favorite colors, or the highlighter's colors; none for a tool that takes no color.
        var swatchCount: Int
        /// Whether the plus that adds the color in use to the colors shows.
        var showsAddColor: Bool
        /// Whether Add Image is on the bar.
        var offersImages: Bool
        /// The width of the tool's own choices on the whole form (the eraser's kind, the lasso's type), which the system
        /// draws and only the bar measures; none for an ink.
        var toolChoicesWidth: Double = 0
    }

    /// How wide the bar is in `arrangement` holding `contents`; nil for the condensed form, the last resort.
    static func width(of arrangement: Arrangement, holding contents: Contents) -> Double? {
        switch arrangement {
        case .whole(let density):
            let colors = !contents.offersColors ? 0
                : Double(contents.swatchCount) * density.swatchPitch + density.otherColorWidth + (contents.showsAddColor ? density.swatchPitch : 0)
            let toggleCount = 2 + (contents.offersImages ? 1 : 0)
            return rowWidth([Double(contents.tools.count) * density.toolPitch, contents.toolChoicesWidth + Double(contents.sizeCount) * density.sizePitch,
                             colors, Double(toggleCount) * density.toolPitch], density: density)
        case .compact(let density):
            return compactWidth(density: density, holding: contents, swatchCount: contents.swatchCount)
        case .compactWithScrollingColors(let visibleSwatchCount):
            return compactWidth(density: .tightest, holding: contents, swatchCount: visibleSwatchCount)
        case .condensed:
            return nil
        }
    }

    /// The compact form with `swatchCount` colors in view: its tools, the sizes, the colors, then Ruler and More.
    private static func compactWidth(density: Density, holding contents: Contents, swatchCount: Int) -> Double {
        let shownTools = compactSplit(contents.tools, toolInUse: contents.toolInUse).shown
        return rowWidth([Double(shownTools.count) * density.toolPitch, Double(contents.sizeCount) * density.sizePitch,
                         Double(swatchCount) * density.swatchPitch, 2 * density.toolPitch], density: density)
    }

    /// The row's sections side by side, a separator between each two that show, inside the row's ends.
    private static func rowWidth(_ sectionWidths: [Double], density: Density) -> Double {
        let shownSections = sectionWidths.filter { sectionWidth in sectionWidth > 0 }
        return 2 * density.edgeInset + shownSections.reduce(0, +) + Double(max(shownSections.count - 1, 0)) * density.separatorWidth
    }

    /// The compact form with scrolling colors for a bar `availableWidth` wide: as many whole colors as fit beside the
    /// rest. Nil where every color fits (a compact form without scrolling is then shown) or fewer than
    /// `minimumVisibleSwatchCount` would.
    static func scrollingColorsArrangement(forWidth availableWidth: Double, holding contents: Contents) -> Arrangement? {
        let density = Density.tightest
        guard contents.swatchCount > minimumVisibleSwatchCount else { return nil }
        let widthWithoutColors = compactWidth(density: density, holding: contents, swatchCount: 0) + density.separatorWidth
        let fittingCount = Int(((availableWidth - widthWithoutColors) / density.swatchPitch).rounded(.down))
        guard fittingCount >= minimumVisibleSwatchCount, fittingCount < contents.swatchCount else { return nil }
        return .compactWithScrollingColors(visibleSwatchCount: fittingCount)
    }

    /// The form a bar `availableWidth` wide shows: the first of `preferredArrangements` that fits, else the compact form
    /// with scrolling colors, else the condensed one. The bar decides with `ViewThatFits` in the same order, measuring
    /// the views built at these widths.
    static func arrangement(forWidth availableWidth: Double, holding contents: Contents) -> Arrangement {
        let fitting = preferredArrangements.first { arrangement in
            (width(of: arrangement, holding: contents) ?? .infinity) <= availableWidth + 0.5
        }
        return fitting ?? scrollingColorsArrangement(forWidth: availableWidth, holding: contents) ?? .condensed
    }
}
