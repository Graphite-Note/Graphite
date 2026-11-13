/**
 * File: FavoriteColorEditing.swift
 * --------------------------------
 * Layer: UI
 * Description: The changes the Pencil bar makes to the favorite colors of Settings › Colors: moving a color one place
 *              (VoiceOver's actions) or to the place a drag left it, changing a color's hex, adding the color in use,
 *              removing one and putting it back. Pure: the bar stores what these return.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
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

    /// The palette with the color taken out of its place and put at `destinationIndex`, the first or last place when
    /// the index is past either end; unchanged for a color it does not have or a drop on its own place.
    static func moving(_ colorIdentifier: PaletteColor.ID, toIndex destinationIndex: Int, in palette: [PaletteColor]) -> [PaletteColor] {
        guard let index = palette.firstIndex(where: { color in color.id == colorIdentifier }) else { return palette }
        let clampedDestination = max(0, min(destinationIndex, palette.count - 1))
        guard clampedDestination != index else { return palette }
        var moved = palette
        let color = moved.remove(at: index)
        moved.insert(color, at: clampedDestination)
        return moved
    }

    /// The palette with the color's hex changed, as the color picker a second tap opens changes it; unchanged when the
    /// hex is not a color or another color of the palette has it already.
    static func changingHex(of colorIdentifier: PaletteColor.ID, to hex: String, in palette: [PaletteColor]) -> [PaletteColor] {
        guard let canonicalHex = TextColorMarkup.canonicalHex(hex),
              let index = palette.firstIndex(where: { color in color.id == colorIdentifier }),
              !palette.contains(where: { color in color.id != colorIdentifier && TextColorMarkup.canonicalHex(color.hex) == canonicalHex })
        else { return palette }
        var changed = palette
        changed[index].hex = canonicalHex
        return changed
    }

    /// The palette with a removed color back at the place it had, or at the end when the palette is shorter now;
    /// unchanged when the palette has that color, or one of its hex, again.
    static func puttingBack(_ color: PaletteColor, at index: Int, in palette: [PaletteColor]) -> [PaletteColor] {
        guard !palette.contains(where: { existing in existing.id == color.id }), !contains(hex: color.hex, in: palette) else { return palette }
        var restored = palette
        restored.insert(color, at: max(0, min(index, palette.count)))
        return restored
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
