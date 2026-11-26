/**
 * File: PencilColorButtons.swift
 * ------------------------------
 * Layer: UI
 * Description: The Pencil bar's colors: black before the favorite colors, or the highlighter's own, in a strip that
 *              scrolls sideways only and keeps its size, the plus that saves a color as a swatch (a picked one at once)
 *              and scrolls the strip to it, Other Color, and the arranging (by dragging, `PencilColorSwatchRow`),
 *              changing and removal with Undo of a color at the bar itself.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 18/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

/// Which of the bar's color controls a place shows.
enum PencilColorControls {
    /// The strip of colors, the plus and Other Color: the whole bar, and the condensed form's popover.
    case all
    /// The strip and the plus: a folded bar, whose Other Color is behind its More control.
    case stripAndAdd
    /// Other Color alone: the folded bar's More popover.
    case otherColor
}

/// The colors of the ink in use on the fixed bar. A highlighter marks text in light colors of
/// its own; a pen writes in black and the note colors. The lists are the ones Settings › Colors
/// keeps, followed with `@AppStorage`, so a change there shows on a bar already on screen.
///
/// The colors sit in a strip that scrolls sideways only (`PencilColorStrip`), as wide as at most
/// `PencilToolRowLayout.maximumVisibleSwatchCount` of them, so saving more colors never widens the bar or moves its other
/// controls (the report of 2026-11-14 that the palette moved "up, down, left, and right"). A swipe scrolls; a
/// favorite color held a moment lifts and is dragged to its place along the strip, as in Apple's markup palette, or off
/// its menu removes it (with Undo, which stands where the plus does for a few seconds); a second tap on the color in
/// use opens its color picker. Black stands before the strip and never scrolls. The plus after the strip saves the color
/// in use as a swatch, or, when the strip has it already, opens the color picker for a new one, saved at its first pick
/// (`FavoriteColorEditing.additionStep`): the bar is
/// where the colors are used, so it is where they are kept (HUNT-312, the requests of 2026-11-13 and 2026-11-14).
struct PencilColorButtons: View {
    @Bindable var toolbox: PencilToolbox
    let rowHeight: CGFloat
    var density: PencilToolRowLayout.Density = .regular
    var controls: PencilColorControls = .all
    /// How many colors the strip shows at once, the rest scrolling; nil for as many as it holds, up to
    /// `PencilToolRowLayout.maximumVisibleSwatchCount`.
    var visibleSwatchCount: Int?
    @State private var removalUndo = PencilColorRemovalUndo()
    /// The color picker the plus opens for a new color, pointing at the plus.
    @State private var additionPicker = PencilColorPickerPresenter()
    /// How many colors the plus has saved while this bar is shown: each one scrolls the strip to its end, where the
    /// new color stands, so a color saved past the strip's edge comes into view (the request of 2026-11-17 that
    /// a color picked from the plus be added "immediately").
    @State private var savedAdditionCount = 0
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    /// The two lists of Settings › Colors the bar shows: the favorite colors for writing, the
    /// highlighter's own while a highlighter is in use.
    enum EditedPalette {
        case favorites, highlighter
    }

    private var editedPalette: EditedPalette { Self.editsHighlighterColors(toolbox) ? .highlighter : .favorites }
    /// Black, first on a pen's bar and not one of the favorite colors; none on a highlighter's.
    private var fixedLeadingColor: PaletteColor? {
        editedPalette == .favorites ? PaletteColor(name: "black", hex: PencilInk.pen.defaultColorHex) : nil
    }

    var body: some View {
        switch controls {
        case .all, .stripAndAdd:
            let colors = palette(editedPalette)
            let leadingCount = fixedLeadingColor == nil ? 0 : 1
            let shownCount = visibleSwatchCount ?? min(colors.count + leadingCount, PencilToolRowLayout.maximumVisibleSwatchCount)
            // Black stands before the strip, so scrolling the colors never takes it out of view (the report of
            // 2026-11-17 that black was "not saved": ten colors scrolled it off the strip's start).
            if let fixedLeadingColor { PencilFixedColorSwatch(toolbox: toolbox, color: fixedLeadingColor, rowHeight: rowHeight, density: density) }
            PencilColorStrip(rowHeight: rowHeight, density: density, visibleSwatchCount: max(0, shownCount - leadingCount),
                             revealedAdditionCount: savedAdditionCount) { scrolling in
                swatches(colors, scrolling: scrolling)
            }
            if let removal = offeredRemoval {
                undoButton(removal.color.name)
            } else if Self.showsAddColor(toolbox) {
                addColorButton
            }
            if controls == .all { otherColorWell }
        case .otherColor:
            otherColorWell
        }
    }

    /// The removal of a color of the list the bar shows that Undo can bring back, if any.
    private var offeredRemoval: PencilColorRemovalUndo.Removal? {
        removalUndo.removal.flatMap { removal in removal.palette == editedPalette ? removal : nil }
    }

    /// The favorite colors, or the highlighter's colors, arranged by dragging.
    private func swatches(_ colors: [PaletteColor], scrolling: PencilColorRowScrolling) -> some View {
        let editedPalette = editedPalette
        return PencilColorSwatchRow(
            toolbox: toolbox,
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
                removedColorName: offeredRemoval?.color.name,
                putBack: { putBack() }))
    }

    /// The system's color well, which sets the ink's color without saving it.
    private var otherColorWell: some View {
        ColorPicker("Other Color", selection: Binding(
            get: { Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .black },
            set: { newColor in if let hex = newColor.sRGBHex { toolbox.chooseColor(hex: hex) } }), supportsOpacity: false)
            .labelsHidden()
            .frame(width: density.otherColorWidth, height: rowHeight)
    }

    // MARK: Counted by the bar

    /// Whether the bar shows the highlighter's colors rather than black and the favorite colors.
    static func editsHighlighterColors(_ toolbox: PencilToolbox) -> Bool { PencilToolRowLayout.editsHighlighterColors(toolbox) }

    /// Whether the plus that saves a color shows (`PencilToolRowLayout.showsAddColor`).
    static func showsAddColor(_ toolbox: PencilToolbox) -> Bool { PencilToolRowLayout.showsAddColor(toolbox) }

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

    /// Saves the color in use as a swatch at the end of the strip, or opens the color picker for a new color, which is
    /// saved as soon as one is picked; the ink draws in each color picked meanwhile.
    private func addColor() {
        let editedPalette = editedPalette
        let step = FavoriteColorEditing.additionStep(colorInUseHex: toolbox.presetInUse.colorHex, palette: palette(editedPalette),
                                                     fixedLeadingHex: fixedLeadingColor?.hex)
        switch step {
        case .saveColorInUse:
            withAnimation(.snappy(duration: 0.22)) {
                store(FavoriteColorEditing.adding(hex: toolbox.presetInUse.colorHex, to: palette(editedPalette)), as: editedPalette)
            }
            savedAdditionCount += 1
        case .chooseNewColor:
            // The first color picked is saved at once as a new swatch, which later picks change, so the strip shows
            // the new color while the picker is still open (the request of 2026-11-17).
            var addedColorIdentifier: PaletteColor.ID?
            let plusFrame = CGRect(x: 0, y: 0, width: density.swatchPitch, height: rowHeight)
            additionPicker.present(hex: toolbox.presetInUse.colorHex, title: "New Color", sourceRect: plusFrame) { [toolbox] pickedHex, phase in
                toolbox.chooseColor(hex: pickedHex)
                guard phase != .moving else { return }
                let saved = FavoriteColorEditing.savingPickedColor(hex: pickedHex, addedColorIdentifier: addedColorIdentifier,
                                                                   in: palette(editedPalette))
                let isNewSwatch = addedColorIdentifier == nil && saved.addedColorIdentifier != nil
                addedColorIdentifier = saved.addedColorIdentifier
                withAnimation(.snappy(duration: 0.22)) { store(saved.palette, as: editedPalette) }
                if isNewSwatch { savedAdditionCount += 1 }
            }
        }
    }

    private var addColorButton: some View {
        Button(action: addColor) {
            Image(systemName: "plus.circle")
                .font(.system(size: 17))
                .frame(width: density.swatchPitch, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { PencilColorPickerAnchor(presenter: additionPicker) }
        .accessibilityLabel(editedPalette == .favorites ? "Add to Favorite Colors" : "Add to Highlighter Colors")
    }

    /// Undo of the last removal, in the plus's place while it is offered, so the bar keeps its width.
    private func undoButton(_ removedColorName: String) -> some View {
        Button(action: putBack) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 17))
                .frame(width: density.swatchPitch, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo Remove \(removedColorName)")
        .transition(.opacity)
    }
}

/// The colors as a strip that scrolls sideways only, as wide as `visibleSwatchCount` whole colors and coming to rest on
/// a color's edge, so none is ever cut in half. Up or down it neither scrolls nor gives, and a strip that holds no more
/// colors than it shows does not move at all. A color the plus saves goes at the end, and the strip scrolls there.
struct PencilColorStrip<Swatches: View>: View {
    let rowHeight: CGFloat
    let density: PencilToolRowLayout.Density
    let visibleSwatchCount: Int
    /// How many colors the plus has saved; each new one scrolls the strip to its end, where the color stands.
    var revealedAdditionCount = 0
    /// The row of colors, given how the strip scrolls under a drag held near either end.
    @ViewBuilder let swatches: (PencilColorRowScrolling) -> Swatches
    @State private var scrollPosition = ScrollPosition(x: 0)
    /// Where the strip stands and how far it can scroll, in points, as its scroll view reports them.
    @State private var scrollOffset: Double = 0
    @State private var largestScrollOffset: Double = 0

    var body: some View {
        let visibleWidth = Double(visibleSwatchCount) * density.swatchPitch
        ScrollView(.horizontal, showsIndicators: false) {
            swatches(PencilColorRowScrolling(visibleWidth: visibleWidth, scrollBy: scroll(by:), settle: settle))
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(.viewAligned)
        // No give when every color shows, and none up or down: the strip moves only to show colors past its edge.
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .onScrollGeometryChange(for: CGSize.self) { geometry in
            CGSize(width: geometry.contentOffset.x, height: max(0, geometry.contentSize.width - geometry.containerSize.width))
        } action: { _, offsetAndLargest in
            scrollOffset = offsetAndLargest.width
            largestScrollOffset = offsetAndLargest.height
            // A removal shortens the strip under it: it then scrolls back to its new end, leaving no gap after the last
            // color (the recording of 2026-11-17).
            if scrollOffset > largestScrollOffset + 0.5 { settle() }
        }
        .onChange(of: revealedAdditionCount) { _, _ in
            // After the layout that lengthens the strip, so its end is where the new color stands.
            Task { @MainActor in
                withAnimation(.snappy(duration: 0.22)) { scrollPosition.scrollTo(edge: .trailing) }
            }
        }
        .frame(width: visibleWidth, height: rowHeight)
    }

    /// Scrolls to the color's edge nearest where the strip stands, within its ends.
    private func settle() {
        let pitch = density.swatchPitch
        guard pitch > 0 else { return }
        let target = max(0, min((scrollOffset / pitch).rounded() * pitch, largestScrollOffset))
        guard abs(target - scrollOffset) > 0.5 else { return }
        scrollPosition.scrollTo(x: target)
        scrollOffset = target
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
