/**
 * File: PencilColorButtons.swift
 * ------------------------------
 * Layer: UI
 * Description: The Pencil bar's colors: black and the favorite colors, or the highlighter's own, Other Color, and the
 *              moves, removal and adding of a color at the bar itself; and the strip that scrolls them on a bar too narrow
 *              for every color even at the mini size.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 04/11/2026
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
/// Each favorite color's menu (a long press) moves it along the bar or removes it, and the plus
/// after Other Color adds the color in use to the list, as Settings › Colors does with its rows:
/// the bar is where the colors are used, so it is where they are arranged (HUNT-312).
struct PencilColorButtons: View {
    @Bindable var toolbox: PencilToolbox
    let rowHeight: CGFloat
    var density: PencilToolRowLayout.Density = .regular
    var controls: PencilColorControls = .all
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    /// The two lists of Settings › Colors the bar shows: the favorite colors for writing, the
    /// highlighter's own while a highlighter is in use.
    private enum EditedPalette {
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

    /// Black and the favorite colors, or the highlighter's colors, each with its editing menu.
    @ViewBuilder private var swatches: some View {
        switch editedPalette {
        case .highlighter:
            ForEach(palette(.highlighter)) { highlighterColor in
                buttons.colorButton(name: highlighterColor.name, hex: highlighterColor.hex)
                    .contextMenu { editingMenu(for: highlighterColor, in: .highlighter) }
            }
        case .favorites:
            buttons.colorButton(name: "black", hex: PencilInk.pen.defaultColorHex)
            ForEach(palette(.favorites)) { favorite in
                buttons.colorButton(name: favorite.name, hex: favorite.hex)
                    .contextMenu { editingMenu(for: favorite, in: .favorites) }
            }
        }
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

    @ViewBuilder private func editingMenu(for color: PaletteColor, in editedPalette: EditedPalette) -> some View {
        let colors = palette(editedPalette)
        Button("Move Left", systemImage: "arrow.left") { store(FavoriteColorEditing.moving(color.id, .earlier, in: colors), as: editedPalette) }
            .disabled(!FavoriteColorEditing.canMove(color.id, .earlier, in: colors))
        Button("Move Right", systemImage: "arrow.right") { store(FavoriteColorEditing.moving(color.id, .later, in: colors), as: editedPalette) }
            .disabled(!FavoriteColorEditing.canMove(color.id, .later, in: colors))
        Button("Remove from Favorite Colors", systemImage: "minus.circle", role: .destructive) {
            store(FavoriteColorEditing.removing(color.id, from: colors), as: editedPalette)
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

    var body: some View {
        let density = PencilToolRowLayout.Density.tightest
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight, density: density, controls: .swatches)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .frame(width: CGFloat(Double(visibleSwatchCount) * density.swatchPitch), height: rowHeight)
    }
}
#endif
