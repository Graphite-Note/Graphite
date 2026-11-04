/**
 * File: PencilColorButtons.swift
 * ------------------------------
 * Layer: UI
 * Description: The Pencil bar's colors: black and the favorite colors, or the highlighter's own, Other Color, and the
 *              moves, removal and adding of a color at the bar itself; and the one well that opens them on a narrower bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

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
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    /// The two lists of Settings › Colors the bar shows: the favorite colors for writing, the
    /// highlighter's own while a highlighter is in use.
    private enum EditedPalette {
        case favorites, highlighter
    }

    private var buttonSide: CGFloat { PencilToolbarMetrics.buttonSide }
    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight) }
    private var editedPalette: EditedPalette { toolbox.presetInUse.ink == .highlighter ? .highlighter : .favorites }

    var body: some View {
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
        ColorPicker("Other Color", selection: Binding(
            get: { Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .black },
            set: { newColor in if let hex = newColor.sRGBHex { toolbox.chooseColor(hex: hex) } }), supportsOpacity: false)
            .labelsHidden()
            .frame(width: buttonSide, height: rowHeight)
        addColorButton
    }

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

    /// Adds the color in use, as Other Color chose it, to the list the bar shows; there only
    /// while that color is not in it (black is always on a pen's bar).
    @ViewBuilder private var addColorButton: some View {
        let colorInUse = toolbox.presetInUse.colorHex
        let isBlackOnAPensBar = editedPalette == .favorites
            && TextColorMarkup.canonicalHex(colorInUse) == TextColorMarkup.canonicalHex(PencilInk.pen.defaultColorHex)
        if toolbox.toolInUse == .ink, !isBlackOnAPensBar, !FavoriteColorEditing.contains(hex: colorInUse, in: palette(editedPalette)) {
            Button {
                store(FavoriteColorEditing.adding(hex: colorInUse, to: palette(editedPalette)), as: editedPalette)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .frame(width: buttonSide, height: rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Favorite Colors")
        }
    }
}

/// The color in use as one well, which opens the colors (`PencilColorButtons`) in a popover: the
/// row's form where the bar has room for the tools and sizes but not for every color.
struct PencilColorWell: View {
    @Bindable var toolbox: PencilToolbox
    let rowHeight: CGFloat
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?
    @State private var showsColors = false

    /// The name of the color in use where a list has it, else its hex.
    private var colorInUseName: String {
        let canonicalHex = TextColorMarkup.canonicalHex(toolbox.presetInUse.colorHex)
        let colors = GraphitePreferences.colorPalette(decoding: storedColorPalette) + GraphitePreferences.highlighterPalette(decoding: storedHighlighterPalette)
        return colors.first { color in TextColorMarkup.canonicalHex(color.hex) == canonicalHex }?.name ?? toolbox.presetInUse.colorHex
    }

    var body: some View {
        Button {
            showsColors = true
        } label: {
            Circle()
                .fill(Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .black)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1) }
                .frame(width: 20, height: 20)
                .overlay { Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 28, height: 28) }
                .frame(width: PencilToolbarMetrics.buttonSide, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colors")
        .accessibilityValue(colorInUseName)
        .popover(isPresented: $showsColors) {
            HStack(spacing: 2) { PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight) }
                .padding(12)
                .tint(.primary)
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
