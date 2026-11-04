/**
 * File: FavoriteColorEditing.swift
 * --------------------------------
 * Layer: UI
 * Description: The changes the Pencil bar makes to the favorite colors of Settings › Colors: moving a color one place,
 *              adding the color in use, removing one. Pure: the bar stores what these return.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import GraphiteCore

/// The Pencil bar's edits of a palette (the favorite colors, or the highlighter's), as values.
/// Settings › Colors edits the same lists with its own rows; the bar offers the same moves at
/// the colors themselves, so arranging them does not mean leaving the page.
enum FavoriteColorEditing {
    /// Which way a color moves along the bar.
    enum Direction {
        case earlier, later

        var offset: Int {
            switch self {
            case .earlier: -1
            case .later: 1
            }
        }
    }

    /// The palette with the color moved one place, or unchanged at either end or for a color it does not have.
    static func moving(_ colorIdentifier: PaletteColor.ID, _ direction: Direction, in palette: [PaletteColor]) -> [PaletteColor] {
        guard let index = palette.firstIndex(where: { color in color.id == colorIdentifier }) else { return palette }
        let destination = index + direction.offset
        guard palette.indices.contains(destination) else { return palette }
        var moved = palette
        moved.swapAt(index, destination)
        return moved
    }

    /// Whether the move can be made, so the bar's menu offers only the moves that change something.
    static func canMove(_ colorIdentifier: PaletteColor.ID, _ direction: Direction, in palette: [PaletteColor]) -> Bool {
        guard let index = palette.firstIndex(where: { color in color.id == colorIdentifier }) else { return false }
        return palette.indices.contains(index + direction.offset)
    }

    /// Whether the palette has a color of this hex already, however it is written.
    static func contains(hex: String, in palette: [PaletteColor]) -> Bool {
        guard let canonicalHex = TextColorMarkup.canonicalHex(hex) else { return false }
        return palette.contains { color in TextColorMarkup.canonicalHex(color.hex) == canonicalHex }
    }

    /// The palette with the color added at its end under a name no color has (`PaletteColorNames.unusedName`), which
    /// Settings › Colors can rename; unchanged when the palette has it already or the hex is not a color.
    static func adding(hex: String, to palette: [PaletteColor]) -> [PaletteColor] {
        guard let canonicalHex = TextColorMarkup.canonicalHex(hex), !contains(hex: canonicalHex, in: palette) else { return palette }
        return palette + [PaletteColor(name: PaletteColorNames.unusedName(in: palette), hex: canonicalHex)]
    }

    /// The palette without the color.
    static func removing(_ colorIdentifier: PaletteColor.ID, from palette: [PaletteColor]) -> [PaletteColor] {
        palette.filter { color in color.id != colorIdentifier }
    }
}
