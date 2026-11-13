/**
 * File: PencilColorButtons.swift
 * ------------------------------
 * Layer: UI
 * Description: The Pencil bar's colors: black and the favorite colors, or the highlighter's own, Other Color, and the
 *              arranging (by dragging, `PencilColorSwatchRow`), changing, removal with Undo and adding of a color at
 *              the bar itself; and the strip that scrolls them on a bar too narrow for every color even at the mini size.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 13/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

/// Which of the bar's color controls a place shows.
enum PencilColorControls {
    /// The swatches, Other Color and the plus: the whole bar, and the condensed form's popover.
    case all
    /// The swatches alone: the compact bar, which keeps every color a tap away.
    case swatches
    /// Other Color and the plus alone: the compact bar's More popover.
    case otherColorAndAdd
}

/// The colors of the ink in use on the fixed bar. A highlighter marks text in light colors of
/// its own; a pen writes in black and the note colors. The lists are the ones Settings › Colors
/// keeps, followed with `@AppStorage`, so a change there shows on a bar already on screen.
///
/// A favorite color is dragged to its place along the bar, as in Apple's markup palette, or off the bar to remove it
/// (with Undo); a second tap on the color in use opens its color picker, its menu (a long press) removes it, and the
/// plus after Other Color adds the color in use to the list, as Settings › Colors does with its rows: the bar is where
/// the colors are used, so it is where they are arranged (HUNT-312, the owner's request of 2026-11-13).
struct PencilColorButtons: View {
    @Bindable var toolbox: PencilToolbox
    let rowHeight: CGFloat
    var density: PencilToolRowLayout.Density = .regular
    var controls: PencilColorControls = .all
    /// How the strip the colors sit in scrolls under a drag, when they sit in one (`PencilColorStrip`).
    var scrolling: PencilColorRowScrolling?
    @State private var removalUndo = PencilColorRemovalUndo()
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    /// The two lists of Settings › Colors the bar shows: the favorite colors for writing, the
    /// highlighter's own while a highlighter is in use.
    enum EditedPalette {
        case favorites, highlighter
    }

    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight, density: density) }
    private var editedPalette: EditedPalette { Self.editsHighlighterColors(toolbox) ? .highlighter : .favorites }

    var body: some View {
        if controls != .otherColorAndAdd { swatches }
        if controls != .swatches {
            ColorPicker("Other Color", selection: Binding(
                get: { Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .black },
                set: { newColor in if let hex = newColor.sRGBHex { toolbox.chooseColor(hex: hex) } }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: density.otherColorWidth, height: rowHeight)
            if Self.showsAddColor(toolbox, favorites: palette(.favorites), highlighterColors: palette(.highlighter)) { addColorButton }
        }
    }

    /// Black and the favorite colors, or the highlighter's colors, arranged by dragging.
    private var swatches: some View {
        let editedPalette = editedPalette
        let colors = palette(editedPalette)
        let removal = removalUndo.removal.flatMap { removal in removal.palette == editedPalette ? removal : nil }
        return PencilColorSwatchRow(
            toolbox: toolbox,
            fixedLeadingColor: editedPalette == .favorites ? PaletteColor(name: "black", hex: PencilInk.pen.defaultColorHex) : nil,
            colors: colors,
            pickerTitle: editedPalette == .favorites ? "Pen Color" : "Highlighter Color",
            rowHeight: rowHeight, density: density, scrolling: scrolling,
            actions: PencilColorRowActions(
                arrange: { colorIdentifier, destinationIndex in
                    store(FavoriteColorEditing.moving(colorIdentifier, toIndex: destinationIndex, in: palette(editedPalette)), as: editedPalette)
                },
                remove: { color in remove(color, from: editedPalette) },
                changeHex: { colorIdentifier, hex in
                    store(FavoriteColorEditing.changingHex(of: colorIdentifier, to: hex, in: palette(editedPalette)), as: editedPalette)
                },
                removedColorName: removal?.color.name,
                putBack: { putBack() }))
    }

    // MARK: Counted by the bar

    /// Whether the bar shows the highlighter's colors rather than black and the favorite colors.
    static func editsHighlighterColors(_ toolbox: PencilToolbox) -> Bool { PencilToolRowLayout.editsHighlighterColors(toolbox) }

    /// Whether the plus that adds the color in use shows (`PencilToolRowLayout.showsAddColor`).
    static func showsAddColor(_ toolbox: PencilToolbox, favorites: [PaletteColor], highlighterColors: [PaletteColor]) -> Bool {
        PencilToolRowLayout.showsAddColor(toolbox, favorites: favorites, highlighterColors: highlighterColors)
    }

    // MARK: Editing

    private func palette(_ palette: EditedPalette) -> [PaletteColor] {
        switch palette {
        case .favorites: GraphitePreferences.colorPalette(decoding: storedColorPalette)
        case .highlighter: GraphitePreferences.highlighterPalette(decoding: storedHighlighterPalette)
        }
    }

    /// Stores the list where Settings › Colors keeps it, which `GraphitePreferences` follows.
    private func store(_ colors: [PaletteColor], as palette: EditedPalette) {
        guard let encodedColors = try? JSONEncoder().encode(colors) else { return } // A list of names and hexes always encodes.
        switch palette {
        case .favorites: storedColorPalette = encodedColors
        case .highlighter: storedHighlighterPalette = encodedColors
        }
    }

    private func remove(_ color: PaletteColor, from editedPalette: EditedPalette) {
        let colors = palette(editedPalette)
        guard let index = colors.firstIndex(where: { existing in existing.id == color.id }) else { return }
        store(FavoriteColorEditing.removing(color.id, from: colors), as: editedPalette)
        removalUndo.offer(PencilColorRemovalUndo.Removal(color: color, index: index, palette: editedPalette))
    }

    /// Brings back the color the last removal took off the bar, at its place.
    private func putBack() {
        guard let removal = removalUndo.take() else { return }
        withAnimation(.snappy(duration: 0.22)) {
            store(FavoriteColorEditing.puttingBack(removal.color, at: removal.index, in: palette(removal.palette)), as: removal.palette)
        }
    }

    /// Adds the color in use, as Other Color chose it, to the list the bar shows.
    private var addColorButton: some View {
        Button {
            store(FavoriteColorEditing.adding(hex: toolbox.presetInUse.colorHex, to: palette(editedPalette)), as: editedPalette)
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 17))
                .frame(width: density.swatchPitch, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to Favorite Colors")
    }
}

/// The colors as a strip that scrolls sideways, as wide as `visibleSwatchCount` whole colors and coming to rest on a
/// color's edge, so none is ever cut in half: the compact bar's form where every color does not fit even at the mini
/// size (`PencilToolRowLayout.Arrangement.compactWithScrollingColors`).
struct PencilColorStrip: View {
    @Bindable var toolbox: PencilToolbox
    let rowHeight: CGFloat
    let visibleSwatchCount: Int
    @State private var scrollPosition = ScrollPosition(x: 0)
    /// Where the strip stands and how far it can scroll, in points, as its scroll view reports them.
    @State private var scrollOffset: Double = 0
    @State private var largestScrollOffset: Double = 0

    var body: some View {
        let density = PencilToolRowLayout.Density.tightest
        let visibleWidth = Double(visibleSwatchCount) * density.swatchPitch
        ScrollView(.horizontal, showsIndicators: false) {
            PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight, density: density, controls: .swatches,
                               scrolling: PencilColorRowScrolling(visibleWidth: visibleWidth, scrollBy: scroll(by:)))
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(.viewAligned)
        .onScrollGeometryChange(for: CGSize.self) { geometry in
            CGSize(width: geometry.contentOffset.x, height: max(0, geometry.contentSize.width - geometry.containerSize.width))
        } action: { _, offsetAndLargest in
            scrollOffset = offsetAndLargest.width
            largestScrollOffset = offsetAndLargest.height
        }
        .frame(width: visibleWidth, height: rowHeight)
    }

    /// Scrolls by up to `distance` points within the strip's ends, for a drag held near one, and says how far it went.
    private func scroll(by distance: Double) -> Double {
        let target = max(0, min(scrollOffset + distance, largestScrollOffset))
        let travelled = target - scrollOffset
        guard travelled != 0 else { return 0 }
        scrollPosition.scrollTo(x: target)
        scrollOffset = target
        return travelled
    }
}

/// The color the last removal took off the bar, which the bar's Undo and the colors' Put Back bring back for a few
/// seconds; the bar keeps one for its life.
@MainActor
@Observable
final class PencilColorRemovalUndo {
    struct Removal {
        let color: PaletteColor
        let index: Int
        let palette: PencilColorButtons.EditedPalette
    }

    /// How long Undo stays on the bar after a removal.
    static let offeredSeconds = 6.0

    private(set) var removal: Removal?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    /// Offers to bring this removal back, in place of any earlier one.
    func offer(_ removal: Removal) {
        self.removal = removal
        expiry?.cancel()
        expiry = Task { [weak self, clock] in
            try? await clock.sleep(for: .seconds(Self.offeredSeconds)) // Cancelled by a later removal or Undo, checked next.
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.22)) { self?.removal = nil }
        }
    }

    /// The removal to bring back, which is then no longer offered.
    func take() -> Removal? {
        defer {
            removal = nil
            expiry?.cancel()
        }
        return removal
    }
}
#endif
