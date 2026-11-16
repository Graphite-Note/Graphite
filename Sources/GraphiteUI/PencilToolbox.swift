/**
 * File: PencilToolbox.swift
 * -------------------------
 * Layer: UI
 * Description: The state of the Pencil bar: its ink presets, the tool in use and the eraser. The types it holds have files of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.23
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// The state of the fixed tool bar: its ink presets, the tool in use, and the eraser, kept
/// between launches and shared by every canvas, as the floating palette's is.
@MainActor @Observable
final class PencilToolbox {
    static let shared = PencilToolbox()
    static let storageKey = "GraphitePencilToolbox.v2"
    static let maximumPresetCount = 6
    /// The three sizes the eraser that removes only the ink it passes over starts with (`PencilEraserWidths`).
    static let defaultEraserWidthChoices: [Double] = PencilEraserWidths.defaultChoices
    /// The widths those sizes can be changed to, in points of the page.
    static let eraserWidthRange: ClosedRange<Double> = PencilEraserWidths.range

    static var defaultPresets: [InkPreset] { [InkPreset(ink: .pen), InkPreset(ink: .pencil), InkPreset(ink: .highlighter)] }

    private struct StoredState: Codable {
        var toolInUse: PencilToolKind
        var presets: [InkPreset]
        var presetInUseIndex: Int
        var erasesWholeStrokes: Bool
        var eraserWidth: Double
        /// Absent from a state saved before the eraser's sizes could be changed.
        var eraserWidthChoices: [Double]?
    }

    @ObservationIgnored private var lastPencilGestureTimestamp: TimeInterval?

    /// Whether an Apple Pencil gesture is one not yet answered: every bar on screen hears
    /// it, and they share this toolbox.
    func acceptsPencilGesture(at timestamp: TimeInterval) -> Bool {
        guard timestamp != lastPencilGestureTimestamp else { return false }
        lastPencilGestureTimestamp = timestamp
        return true
    }

    /// Posted, with the toolbox as its object, as soon as the tool in use or anything about
    /// it changes. Canvases take the new tool then, before the next touch arrives, rather
    /// than when SwiftUI next updates their view.
    static let selectionDidChange = Notification.Name("GraphitePencilToolboxSelectionDidChange")

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var toolInUse: PencilToolKind { didSet { selectionChanged() } }
    private(set) var presets: [InkPreset] { didSet { selectionChanged() } }
    private(set) var presetInUseIndex: Int { didSet { selectionChanged() } }
    var erasesWholeStrokes: Bool { didSet { selectionChanged() } }
    private(set) var eraserWidth: Double { didSet { selectionChanged() } }
    /// The pixel eraser's three sizes on the bar; a second tap on the one in use changes it.
    private(set) var eraserWidthChoices: [Double] { didSet { selectionChanged() } }
    /// The ruler is put away with the app, like a real one.
    var isRulerActive = false { didSet { NotificationCenter.default.post(name: Self.selectionDidChange, object: self) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { storedState in try? JSONDecoder().decode(StoredState.self, from: storedState) }
        var storedPresets = (stored?.presets ?? []).prefix(Self.maximumPresetCount).map(\.validated)
        // Two presets with one identifier would be one button to the bar.
        if Set(storedPresets.map(\.id)).count != storedPresets.count { storedPresets = [] }
        let hasStoredPresets = !storedPresets.isEmpty
        if !hasStoredPresets { storedPresets = Self.defaultPresets }
        presets = storedPresets
        presetInUseIndex = hasStoredPresets ? min(max(stored?.presetInUseIndex ?? 0, 0), storedPresets.count - 1) : 0
        let storedTool = stored?.toolInUse ?? .ink
        toolInUse = storedTool
        toolSavedInPlaceOfLaser = storedTool.isPutAwayWithApp ? .ink : storedTool
        erasesWholeStrokes = stored?.erasesWholeStrokes ?? true
        let storedEraserWidths = PencilEraserWidths.restored(choices: stored?.eraserWidthChoices, widthInUse: stored?.eraserWidth)
        eraserWidthChoices = storedEraserWidths.choices
        eraserWidth = storedEraserWidths.widthInUse
    }

    /// The tool kept between launches in place of the laser pointer: the one in use before
    /// it. The laser points while presenting and is put away with the app; and a build
    /// without it could not read a saved state naming it, and would start with its default
    /// presets.
    @ObservationIgnored private var toolSavedInPlaceOfLaser = PencilToolKind.ink

    private func selectionChanged() {
        if !toolInUse.isPutAwayWithApp { toolSavedInPlaceOfLaser = toolInUse }
        let savedTool = toolInUse.isPutAwayWithApp ? toolSavedInPlaceOfLaser : toolInUse
        let state = StoredState(toolInUse: savedTool, presets: presets, presetInUseIndex: presetInUseIndex,
                                erasesWholeStrokes: erasesWholeStrokes, eraserWidth: eraserWidth, eraserWidthChoices: eraserWidthChoices)
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
        NotificationCenter.default.post(name: Self.selectionDidChange, object: self)
    }

    /// The ink preset in use, or the one last in use while erasing or selecting.
    var presetInUse: InkPreset { presets[presetInUseIndex] }

    /// A tool of the bar, told apart from the others by its kind and, for an ink, its preset.
    struct Tool: Equatable {
        var kind: PencilToolKind
        var presetIdentifier: UUID
    }

    private var toolTakenUp: Tool { Tool(kind: toolInUse, presetIdentifier: presetInUse.id) }
    /// The tool in use before the last change of tool, which Apple Pencil's "switch to the
    /// previous tool" takes up again. Not kept between launches, as Apple's palette does not.
    @ObservationIgnored private(set) var previousTool: Tool?

    /// Makes a change of tool and remembers the tool it replaced.
    private func changeTool(_ change: () -> Void) {
        let toolBefore = toolTakenUp
        change()
        if toolTakenUp != toolBefore { previousTool = toolBefore }
    }

    func use(_ kind: PencilToolKind) {
        changeTool { if toolInUse != kind { toolInUse = kind } }
    }

    func usePreset(at presetIndex: Int) {
        guard presets.indices.contains(presetIndex) else { return }
        changeTool {
            if presetInUseIndex != presetIndex { presetInUseIndex = presetIndex }
            if toolInUse != .ink { toolInUse = .ink }
        }
    }

    /// Takes up the tool in use before the last change, as a double tap or squeeze of Apple
    /// Pencil does when set to switch to the previous tool. A preset removed meanwhile is
    /// replaced by the one in use. With no earlier tool, as just after launch, the gesture
    /// still answers: it takes up the eraser, which is what a double tap does by default.
    func switchToPreviousTool() {
        guard let previousTool else {
            use(.eraser)
            return
        }
        let presetIndex = presets.firstIndex { preset in preset.id == previousTool.presetIdentifier } ?? presetInUseIndex
        changeTool {
            if presetInUseIndex != presetIndex { presetInUseIndex = presetIndex }
            if toolInUse != previousTool.kind { toolInUse = previousTool.kind }
        }
    }

    /// Takes up the eraser, or, when it is in use, the tool before it: Apple Pencil's
    /// "switch between the current tool and the eraser".
    func switchToEraser() {
        guard toolInUse == .eraser else { use(.eraser); return }
        if let previousTool, previousTool.kind != .eraser { switchToPreviousTool() } else { use(.ink) }
    }

    /// Gives the ink in use the color. With the eraser or the lasso in use, the ink last in
    /// use takes the color and is in use again: choosing a color means wanting to draw.
    func chooseColor(hex: String) {
        guard let canonicalHex = TextColorMarkup.canonicalHex(hex) else { return }
        use(.ink)
        if presets[presetInUseIndex].colorHex != canonicalHex { presets[presetInUseIndex].colorHex = canonicalHex }
    }

    /// Any width the ink can draw, as the options' slider gives it. The size in use on the
    /// bar, when the width was one of the three, takes the new width.
    func chooseWidth(_ width: Double) {
        guard toolInUse == .ink, width.isFinite, presetInUse.ink.widthRange.contains(width), presetInUse.width != width else { return }
        if let chosenWidthIndex {
            changeWidthChoice(at: chosenWidthIndex, to: width)
        } else {
            presets[presetInUseIndex].width = width
        }
    }

    /// Which of the three sizes of the ink in use is chosen; nil when its width is none of them.
    var chosenWidthIndex: Int? { presetInUse.widthChoices.firstIndex(of: presetInUse.width) }

    /// Draws with one of the three sizes of the ink in use.
    func useWidthChoice(at choiceIndex: Int) {
        guard toolInUse == .ink, presetInUse.widthChoices.indices.contains(choiceIndex) else { return }
        let width = presetInUse.widthChoices[choiceIndex]
        if presetInUse.width != width { presets[presetInUseIndex].width = width }
    }

    /// Gives one of the three sizes of the ink in use another width, kept within what the
    /// ink draws, and draws with it.
    func changeWidthChoice(at choiceIndex: Int, to width: Double) {
        guard toolInUse == .ink, presetInUse.widthChoices.indices.contains(choiceIndex), width.isFinite else { return }
        let widthRange = presetInUse.ink.widthRange
        var preset = presetInUse
        preset.widthChoices[choiceIndex] = min(max(width, widthRange.lowerBound), widthRange.upperBound)
        preset.width = preset.widthChoices[choiceIndex]
        if preset != presetInUse { presets[presetInUseIndex] = preset }
    }

    func chooseOpacity(_ opacity: Double) {
        guard toolInUse == .ink, opacity.isFinite, InkPreset.opacityRange.contains(opacity), presetInUse.opacity != opacity else { return }
        presets[presetInUseIndex].opacity = opacity
    }

    /// Turns the preset in use into another ink. It keeps its color; the width becomes the
    /// new ink's medium one and the sizes the new ink's, as a pen's width would be a hairline
    /// for watercolor.
    func chooseInk(_ ink: PencilInk) {
        guard toolInUse == .ink, presetInUse.ink != ink else { return }
        var preset = presetInUse
        // A highlighter in the pen's black hides what it marks, and a pen in highlighter
        // yellow is hard to read: a color that is still the old ink's default follows.
        if preset.colorHex == preset.ink.defaultColorHex { preset.colorHex = ink.defaultColorHex }
        preset.ink = ink
        preset.width = ink.mediumWidth
        preset.widthChoices = ink.widthChoices
        presets[presetInUseIndex] = preset
    }

    var canAddPreset: Bool { presets.count < Self.maximumPresetCount }
    var canRemovePreset: Bool { presets.count > 1 }

    /// Adds a copy of the preset in use after it and takes it up, to be set up differently.
    func addPreset() {
        guard canAddPreset else { return }
        var preset = presetInUse
        preset.id = UUID()
        let newPresetIndex = presetInUseIndex + 1
        presets.insert(preset, at: newPresetIndex)
        usePreset(at: newPresetIndex)
    }

    func removePresetInUse() {
        guard canRemovePreset else { return }
        let removedIndex = presetInUseIndex
        // The index is moved first: the presets are never shorter than it reaches.
        if removedIndex == presets.count - 1 { presetInUseIndex = removedIndex - 1 }
        presets.remove(at: removedIndex)
    }

    func chooseEraserWidth(_ width: Double) {
        guard eraserWidthChoices.contains(width), eraserWidth != width else { return }
        eraserWidth = width
    }

    /// Erases with one of the eraser's three sizes. A width is the pixel eraser's, so a size
    /// chosen while the eraser removes whole strokes turns it to erasing pixels: the bar
    /// shows the eraser's sizes in both kinds, as it shows an ink's.
    func useEraserWidthChoice(at choiceIndex: Int) {
        guard eraserWidthChoices.indices.contains(choiceIndex) else { return }
        if toolInUse != .eraser { use(.eraser) }
        if erasesWholeStrokes { erasesWholeStrokes = false }
        chooseEraserWidth(eraserWidthChoices[choiceIndex])
    }

    /// Which of the eraser's three sizes is in use; nil while it removes whole strokes.
    var chosenEraserWidthIndex: Int? { erasesWholeStrokes ? nil : eraserWidthChoices.firstIndex(of: eraserWidth) }

    /// Gives one of the eraser's three sizes another width, the nearest of its steps
    /// (`PencilEraserWidths.steps`) within `eraserWidthRange`, and erases with it.
    func changeEraserWidthChoice(at choiceIndex: Int, to width: Double) {
        guard eraserWidthChoices.indices.contains(choiceIndex), width.isFinite else { return }
        let erasingWidth = PencilEraserWidths.snapped(width)
        if eraserWidthChoices[choiceIndex] != erasingWidth { eraserWidthChoices[choiceIndex] = erasingWidth }
        if eraserWidth != erasingWidth { eraserWidth = erasingWidth }
    }

    var selection: PencilToolSelection {
        PencilToolSelection(kind: toolInUse, preset: presetInUse, erasesWholeStrokes: erasesWholeStrokes,
                            eraserWidth: eraserWidth, isRulerActive: isRulerActive)
    }
}
