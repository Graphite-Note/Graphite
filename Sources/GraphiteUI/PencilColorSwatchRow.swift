/**
 * File: PencilColorSwatchRow.swift
 * --------------------------------
 * Layer: UI
 * Description: The Pencil bar's row of colors inside its strip, arranged by dragging as in Apple's markup palette: a
 *              color held a moment lifts and follows the finger, Apple Pencil or pointer along the row while the others
 *              slide aside, letting go puts it there, a swipe scrolls the strip, a tap chooses a color and a second tap
 *              opens its color picker.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit
import GraphiteCore

/// How the row's strip scrolls under a drag held near either end (`PencilColorStrip`).
struct PencilColorRowScrolling {
    /// The width of the strip's visible part, in points.
    let visibleWidth: Double
    /// Scrolls the strip by up to this many points (negative towards the start) and returns how far it went.
    let scrollBy: @MainActor (Double) -> Double
    /// Brings the strip to rest on a color's edge, after a drag scrolled it.
    let settle: @MainActor () -> Void
}

/// What the row asks of its owner, which keeps the lists where Settings › Colors keeps them (`PencilColorButtons`).
struct PencilColorRowActions {
    /// Puts the color at a place of the row, after a drag let go there.
    let arrange: (PaletteColor.ID, Int) -> Void
    /// Takes the color off the row, after its menu's Remove.
    let remove: (PaletteColor) -> Void
    /// Changes a color's hex to what its color picker picked.
    let changeHex: (PaletteColor.ID, String) -> Void
    /// The color a removal took off the row, which Undo and the menus' Put Back bring back, if any.
    let removedColorName: String?
    let putBack: () -> Void
}

/// The drag of one color: which, from where, and how far along the row the finger has gone in its visible space.
private struct PencilColorDrag: Equatable {
    let colorIdentifier: PaletteColor.ID
    let originalIndex: Int
    var horizontalTravel: Double
}

/// The colors the bar arranges: the favorite colors after black (`PencilFixedColorSwatch`, before the strip), or the
/// highlighter's. The drag lives in this row's state, so moving a color redraws this row alone and lays out nothing: the
/// others slide by offsets, and the order is stored once, when the drag ends.
struct PencilColorSwatchRow: View {
    let toolbox: PencilToolbox
    let colors: [PaletteColor]
    let pickerTitle: String
    let rowHeight: CGFloat
    let density: PencilToolRowLayout.Density
    let scrolling: PencilColorRowScrolling
    let actions: PencilColorRowActions

    @State private var drag: PencilColorDrag?
    @State private var autoscroller = PencilColorRowAutoscroller()
    @State private var pickerPresenter = PencilColorPickerPresenter()

    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight, density: density) }
    private var arrangement: PencilColorArrangement {
        PencilColorArrangement(colorCount: colors.count, swatchPitch: density.swatchPitch)
    }

    var body: some View {
        let dragDestination = drag.map { drag in destinationIndex(of: drag) }
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.element.id) { index, color in
                arrangeableSwatch(color, at: index, destinationIndex: dragDestination)
            }
        }
        .background { PencilColorPickerAnchor(presenter: pickerPresenter) }
        .overlay { PencilColorRowTouchSurface(touches: touches) }
        .scrollTargetLayout()
    }

    /// The row's touches by place, the first color's being 0.
    private var touches: PencilColorRowTouches {
        PencilColorRowTouches(
            swatchPitch: density.swatchPitch,
            canArrange: { place in colors.indices.contains(place) },
            tapped: { place in
                if colors.indices.contains(place) { tap(colors[place], at: place) }
            },
            dragged: { place, phase in
                guard colors.indices.contains(place) else { return }
                follow(phase, of: colors[place], at: place)
            },
            menu: { place in colors.indices.contains(place) ? menu(for: colors[place]) : nil })
    }

    // MARK: Swatches

    private func arrangeableSwatch(_ color: PaletteColor, at index: Int, destinationIndex: Int?) -> some View {
        let isInUse = buttons.isColorInUse(hex: color.hex)
        let isDragged = drag?.colorIdentifier == color.id
        var slide = 0.0
        if let drag, let destinationIndex {
            slide = arrangement.slideOffset(ofColorAt: index, draggedFrom: drag.originalIndex, destinationIndex: destinationIndex)
        }
        var draggedOffset = 0.0
        if isDragged, let drag { draggedOffset = drag.horizontalTravel + autoscroller.scrolledDistance }
        // A lifted color stays on the row's line: it follows the finger along the row only.
        return buttons.colorSwatch(hex: color.hex, isInUse: isInUse)
            .scaleEffect(isDragged ? 1.25 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 4, y: 2)
            .offset(x: isDragged ? draggedOffset : slide)
            .animation(isDragged ? nil : .snappy(duration: 0.22), value: slide)
            .zIndex(isDragged ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel(color.name)
            .accessibilityAddTraits(isInUse ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tap(color, at: index) }
            .accessibilityAction(named: "Move Left") { if index > 0 { actions.arrange(color.id, index - 1) } }
            .accessibilityAction(named: "Move Right") { if index < colors.count - 1 { actions.arrange(color.id, index + 1) } }
            .accessibilityAction(named: "Remove") { withAnimation(.snappy(duration: 0.22)) { actions.remove(color) } }
    }

    /// A color's menu (a hold let go where the color lifted): Remove, and Put Back while a removal can be undone.
    private func menu(for color: PaletteColor) -> UIMenu {
        var items: [UIMenuElement] = [UIAction(title: "Remove from Favorite Colors", image: UIImage(systemName: "minus.circle"),
                                               attributes: .destructive) { _ in withAnimation(.snappy(duration: 0.22)) { actions.remove(color) } }]
        if let removedColorName = actions.removedColorName {
            items.append(UIAction(title: "Put Back \(removedColorName)", image: UIImage(systemName: "arrow.uturn.backward")) { _ in actions.putBack() })
        }
        return UIMenu(children: items)
    }

    // MARK: Choosing

    /// A tap chooses the color; a second tap on the color in use opens its color picker, which changes the color itself.
    private func tap(_ color: PaletteColor, at swatchIndex: Int) {
        guard buttons.isColorInUse(hex: color.hex), pickerPresenter.canPresent else {
            toolbox.chooseColor(hex: color.hex)
            return
        }
        let swatchFrame = CGRect(x: Double(swatchIndex) * density.swatchPitch, y: 0, width: density.swatchPitch, height: rowHeight)
        pickerPresenter.present(hex: color.hex, title: pickerTitle, sourceRect: swatchFrame) { [toolbox, actions] pickedHex, phase in
            toolbox.chooseColor(hex: pickedHex)
            if phase != .moving { actions.changeHex(color.id, pickedHex) }
        }
    }

    // MARK: Dragging

    /// A color lifts after a short hold, since a swipe scrolls the strip; a tap fails the hold, so it still chooses.
    private func follow(_ phase: PencilColorRowTouches.DragPhase, of color: PaletteColor, at index: Int) {
        switch phase {
        case .moved(let translation, let visibleLocation):
            drag = PencilColorDrag(colorIdentifier: color.id, originalIndex: index, horizontalTravel: translation.width)
            let direction = arrangement.scrollDirection(atVisibleLocation: visibleLocation, visibleWidth: scrolling.visibleWidth)
            autoscroller.follow(direction: direction, step: density.swatchPitch / 4, scrollBy: scrolling.scrollBy)
        case .ended(let translation):
            let endedDrag = PencilColorDrag(colorIdentifier: color.id, originalIndex: index, horizontalTravel: translation.width)
            let landingIndex = destinationIndex(of: endedDrag)
            autoscroller.finish()
            withAnimation(.snappy(duration: 0.22)) {
                drag = nil
                actions.arrange(color.id, landingIndex)
                scrolling.settle()
            }
        case .cancelled:
            autoscroller.finish()
            withAnimation(.snappy(duration: 0.22)) {
                drag = nil
                scrolling.settle()
            }
        }
    }

    private func destinationIndex(of drag: PencilColorDrag) -> Int {
        arrangement.destinationIndex(draggedFrom: drag.originalIndex, horizontalTravel: drag.horizontalTravel + autoscroller.scrolledDistance)
    }
}

/// Black before the strip of a pen's bar: always first, always in view, never arranged or removed. A tap chooses it,
/// and a second tap opens the color picker for the ink alone (black stays black). A SwiftUI button: outside the strip
/// no scroll view competes for its touches.
struct PencilFixedColorSwatch: View {
    let toolbox: PencilToolbox
    let color: PaletteColor
    let rowHeight: CGFloat
    let density: PencilToolRowLayout.Density
    @State private var pickerPresenter = PencilColorPickerPresenter()

    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight, density: density) }

    var body: some View {
        let isInUse = buttons.isColorInUse(hex: color.hex)
        Button(action: choose) { buttons.colorSwatch(hex: color.hex, isInUse: isInUse) }
            .buttonStyle(.plain)
            .background { PencilColorPickerAnchor(presenter: pickerPresenter) }
            .accessibilityLabel(color.name)
            .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func choose() {
        guard buttons.isColorInUse(hex: color.hex), pickerPresenter.canPresent else {
            toolbox.chooseColor(hex: color.hex)
            return
        }
        let swatchFrame = CGRect(x: 0, y: 0, width: density.swatchPitch, height: rowHeight)
        pickerPresenter.present(hex: color.hex, title: "Pen Color", sourceRect: swatchFrame) { [toolbox] pickedHex, _ in
            toolbox.chooseColor(hex: pickedHex)
        }
    }
}

/// Scrolls a strip in small steps while a drag is held near either end, and adds up how far it went, so the dragged
/// color stays under the finger and lands where it shows. One per row; nothing runs while no drag is near an end.
@MainActor
@Observable
final class PencilColorRowAutoscroller {
    /// How far the strip has scrolled under the drag in progress, in points.
    private(set) var scrolledDistance: Double = 0
    @ObservationIgnored private var direction = 0
    @ObservationIgnored private var stepping: Task<Void, Never>?
    @ObservationIgnored private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    /// Scrolls towards `direction` (-1, 0 or 1) by `step` points about thirty times a second until told otherwise.
    func follow(direction: Int, step: Double, scrollBy: @escaping @MainActor (Double) -> Double) {
        guard direction != self.direction else { return }
        self.direction = direction
        stepping?.cancel()
        stepping = nil
        guard direction != 0 else { return }
        stepping = Task { [weak self, clock] in
            while !Task.isCancelled {
                guard let self else { return }
                self.scrolledDistance += scrollBy(Double(direction) * step)
                try? await clock.sleep(for: .milliseconds(33)) // Cancelled when the drag leaves the end: the loop then stops.
            }
        }
    }

    /// Stops scrolling and forgets the distance, when the drag ends.
    func finish() {
        stepping?.cancel()
        stepping = nil
        direction = 0
        scrolledDistance = 0
    }
}
#endif
