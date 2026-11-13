/**
 * File: PencilColorSwatchRow.swift
 * --------------------------------
 * Layer: UI
 * Description: The Pencil bar's row of colors, arranged by dragging as in Apple's markup palette: a color lifts and
 *              follows the finger, Apple Pencil or pointer along the row while the others slide aside, letting go puts
 *              it there, a drag off the row removes it, a tap chooses a color and a second tap opens its color picker.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit
import GraphiteCore

/// How a row inside a scrolling strip scrolls under a drag held near either end (`PencilColorStrip`).
struct PencilColorRowScrolling {
    /// The width of the strip's visible part, in points.
    let visibleWidth: Double
    /// Scrolls the strip by up to this many points (negative towards the start) and returns how far it went.
    let scrollBy: @MainActor (Double) -> Double
}

/// What the row asks of its owner, which keeps the lists where Settings › Colors keeps them (`PencilColorButtons`).
struct PencilColorRowActions {
    /// Puts the color at a place of the row, after a drag let go there.
    let arrange: (PaletteColor.ID, Int) -> Void
    /// Takes the color off the row, after a drag off it or its menu's Remove.
    let remove: (PaletteColor) -> Void
    /// Changes a color's hex to what its color picker picked.
    let changeHex: (PaletteColor.ID, String) -> Void
    /// The color a removal took off the row, which Undo and the menus' Put Back bring back, if any.
    let removedColorName: String?
    let putBack: () -> Void
}

/// The drag of one color: which, from where, and how far the finger has gone in the row's visible space.
private struct PencilColorDrag: Equatable {
    let colorIdentifier: PaletteColor.ID
    let originalIndex: Int
    var translation: CGSize
}

/// The colors the bar arranges, after black when it shows the favorite colors. Black always comes first and is not
/// dragged. The drag lives in this row's state, so moving a color redraws this row alone and lays out nothing: the
/// others slide by offsets, and the order is stored once, when the drag ends.
struct PencilColorSwatchRow: View {
    let toolbox: PencilToolbox
    /// Black for the favorite colors; nil for the highlighter's.
    let fixedLeadingColor: PaletteColor?
    let colors: [PaletteColor]
    let pickerTitle: String
    let rowHeight: CGFloat
    let density: PencilToolRowLayout.Density
    let scrolling: PencilColorRowScrolling?
    let actions: PencilColorRowActions

    @State private var drag: PencilColorDrag?
    @State private var autoscroller = PencilColorRowAutoscroller()
    @State private var pickerPresenter = PencilColorPickerPresenter()

    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight, density: density) }
    private var arrangement: PencilColorArrangement {
        PencilColorArrangement(colorCount: colors.count, swatchPitch: density.swatchPitch, removalDistance: rowHeight)
    }
    private var leadingCount: Int { fixedLeadingColor == nil ? 0 : 1 }

    var body: some View {
        let dragOutcome = drag.map { drag in outcome(of: drag) }
        HStack(spacing: 0) {
            if let fixedLeadingColor { fixedSwatch(fixedLeadingColor) }
            ForEach(Array(colors.enumerated()), id: \.element.id) { index, color in
                arrangeableSwatch(color, at: index, outcome: dragOutcome)
            }
            if let removedColorName = actions.removedColorName { undoButton(removedColorName) }
        }
        .background { PencilColorPickerAnchor(presenter: pickerPresenter) }
        .overlay { PencilColorRowTouchSurface(touches: touches) }
        .scrollTargetLayout()
    }

    /// The row's touches by place: black first when shown, then the colors, then Undo when offered.
    private var touches: PencilColorRowTouches {
        PencilColorRowTouches(
            swatchPitch: density.swatchPitch,
            canArrange: { place in colors.indices.contains(place - leadingCount) },
            holdSeconds: scrolling == nil ? nil : 0.25,
            tapped: { place in
                if let fixedLeadingColor, place == 0 { return tap(fixedLeadingColor, at: 0, isArranged: false) }
                if colors.indices.contains(place - leadingCount) { return tap(colors[place - leadingCount], at: place, isArranged: true) }
                if place == leadingCount + colors.count, actions.removedColorName != nil { actions.putBack() }
            },
            dragged: { place, phase in
                guard colors.indices.contains(place - leadingCount) else { return }
                follow(phase, of: colors[place - leadingCount], at: place - leadingCount)
            },
            menu: { place in colors.indices.contains(place - leadingCount) ? menu(for: colors[place - leadingCount]) : nil })
    }

    // MARK: Swatches

    private func fixedSwatch(_ color: PaletteColor) -> some View {
        let isInUse = buttons.isColorInUse(hex: color.hex)
        return buttons.colorSwatch(hex: color.hex, isInUse: isInUse)
            .accessibilityElement()
            .accessibilityLabel(color.name)
            .accessibilityAddTraits(isInUse ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tap(color, at: 0, isArranged: false) }
    }

    private func arrangeableSwatch(_ color: PaletteColor, at index: Int, outcome: PencilColorArrangement.Outcome?) -> some View {
        let isInUse = buttons.isColorInUse(hex: color.hex)
        let isDragged = drag?.colorIdentifier == color.id
        let wouldBeRemoved = isDragged && outcome == .removed
        var slide = 0.0
        if let drag, let outcome { slide = arrangement.slideOffset(ofColorAt: index, draggedFrom: drag.originalIndex, outcome: outcome) }
        var draggedOffset = CGSize.zero
        if isDragged, let drag { draggedOffset = CGSize(width: drag.translation.width + autoscroller.scrolledDistance, height: drag.translation.height) }
        return buttons.colorSwatch(hex: color.hex, isInUse: isInUse)
            .scaleEffect(isDragged ? (wouldBeRemoved ? 0.8 : 1.25) : 1)
            .opacity(wouldBeRemoved ? 0.35 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 4, y: 2)
            .offset(x: isDragged ? draggedOffset.width : slide, y: draggedOffset.height)
            .animation(isDragged ? nil : .snappy(duration: 0.22), value: slide)
            .zIndex(isDragged ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel(color.name)
            .accessibilityAddTraits(isInUse ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tap(color, at: index + leadingCount, isArranged: true) }
            .accessibilityAction(named: "Move Left") { if index > 0 { actions.arrange(color.id, index - 1) } }
            .accessibilityAction(named: "Move Right") { if index < colors.count - 1 { actions.arrange(color.id, index + 1) } }
    }

    private func undoButton(_ removedColorName: String) -> some View {
        Button(action: actions.putBack) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 17))
                .frame(width: density.swatchPitch, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo Remove \(removedColorName)")
        .transition(.opacity)
    }

    /// A color's menu (a long press): Remove, and Put Back while a removal can be undone.
    private func menu(for color: PaletteColor) -> UIMenu {
        var items: [UIMenuElement] = [UIAction(title: "Remove from Favorite Colors", image: UIImage(systemName: "minus.circle"),
                                               attributes: .destructive) { _ in withAnimation(.snappy(duration: 0.22)) { actions.remove(color) } }]
        if let removedColorName = actions.removedColorName {
            items.append(UIAction(title: "Put Back \(removedColorName)", image: UIImage(systemName: "arrow.uturn.backward")) { _ in actions.putBack() })
        }
        return UIMenu(children: items)
    }

    // MARK: Choosing

    /// A tap chooses the color; a second tap on the color in use opens its color picker, which changes the color
    /// itself when it is one of the row's (black stays black: its picker changes only the ink's color).
    private func tap(_ color: PaletteColor, at swatchIndex: Int, isArranged: Bool) {
        guard buttons.isColorInUse(hex: color.hex), pickerPresenter.canPresent else {
            toolbox.chooseColor(hex: color.hex)
            return
        }
        let swatchFrame = CGRect(x: Double(swatchIndex) * density.swatchPitch, y: 0, width: density.swatchPitch, height: rowHeight)
        pickerPresenter.present(hex: color.hex, title: pickerTitle, sourceRect: swatchFrame) { [toolbox, actions] pickedHex, isFinal in
            toolbox.chooseColor(hex: pickedHex)
            if isFinal, isArranged { actions.changeHex(color.id, pickedHex) }
        }
    }

    // MARK: Dragging

    /// A drag on the bar's row arranges at once; in a scrolling strip, where a sideways drag scrolls, a color lifts
    /// after a short hold. A tap fails both, so it still chooses.
    private func follow(_ phase: PencilColorRowTouches.DragPhase, of color: PaletteColor, at index: Int) {
        switch phase {
        case .moved(let translation, let visibleLocation):
            drag = PencilColorDrag(colorIdentifier: color.id, originalIndex: index, translation: translation)
            guard let scrolling else { return }
            let direction = arrangement.scrollDirection(atVisibleLocation: visibleLocation, visibleWidth: scrolling.visibleWidth)
            autoscroller.follow(direction: direction, step: density.swatchPitch / 4, scrollBy: scrolling.scrollBy)
        case .ended(let translation):
            let endedDrag = PencilColorDrag(colorIdentifier: color.id, originalIndex: index, translation: translation)
            let endedOutcome = outcome(of: endedDrag)
            autoscroller.finish()
            withAnimation(.snappy(duration: 0.22)) {
                drag = nil
                switch endedOutcome {
                case .removed: actions.remove(color)
                case .arranged(let destinationIndex): actions.arrange(color.id, destinationIndex)
                }
            }
        case .cancelled:
            autoscroller.finish()
            withAnimation(.snappy(duration: 0.22)) { drag = nil }
        }
    }

    private func outcome(of drag: PencilColorDrag) -> PencilColorArrangement.Outcome {
        arrangement.outcome(draggedFrom: drag.originalIndex, horizontalTravel: drag.translation.width + autoscroller.scrolledDistance,
                            verticalTravel: drag.translation.height)
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
