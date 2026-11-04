/**
 * File: PencilBarOwnersToolboxHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The fixed Pencil bar with the owner's own toolbox (a monoline, a pencil and a highlighter, no pen) on the
 *              11-inch iPad, sideways, beside the sidebar, upright, and upright beside Undo, Redo and Write: the buttons
 *              wholly on screen, printed, with every favorite color, the ruler, the writing tools and Add Image among
 *              them (HUNT-317).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
@testable import GraphiteUI

/// A hosted run on the owner's iPad found his saved toolbox has no pen preset, and his upright bar folded with the
/// colors' Other Color, Shapes and Add Image behind the More control. This test sets his toolbox up through the
/// toolbox's own store, in settings of its own (the device's are neither read nor changed), and reads the buttons of
/// the bar the app builds, with each of his inks, the eraser and the lasso in use. `PencilBarOwnersToolboxTests` (Mac)
/// checks the layout's decision for every toolbox shape. Nothing here plays sound.
@MainActor
final class PencilBarOwnersToolboxHostedTests: XCTestCase {
    /// The owner's toolbox as the store keeps it (`GraphitePencilToolbox.v2`): only the tool kinds, colors, widths and
    /// counts of his iPad's settings of 2026-11-04. The same record as `PencilBarOwnersToolboxTests.ownersToolboxRecord`.
    private static let ownersToolboxRecord = """
    {"toolInUse":"ink","presetInUseIndex":0,"erasesWholeStrokes":false,"eraserWidth":4,"eraserWidthChoices":[4,36,64],"presets":[
    {"id":"7D0E3C1A-0000-4000-8000-000000000001","ink":"monoline","colorHex":"#086ddd","width":1.6,"widthChoices":[0.5,1.6,3],"opacity":1},
    {"id":"7D0E3C1A-0000-4000-8000-000000000002","ink":"pencil","colorHex":"#e93147","width":2.4,"widthChoices":[2.4,4,7],"opacity":1},
    {"id":"7D0E3C1A-0000-4000-8000-000000000003","ink":"highlighter","colorHex":"#8fe378","width":18,"widthChoices":[10,18,28],"opacity":0.33}]}
    """

    /// A width of the 11-inch iPad, and whether the bar shares its row with Undo, Redo and Write, as in Focus, where no
    /// tab bar holds them.
    private struct BarPlace {
        let name: String
        let width: CGFloat
        let sharesRowWithUndoRedoAndWrite: Bool
    }

    private static let places = [
        BarPlace(name: "sideways", width: 1_194, sharesRowWithUndoRedoAndWrite: false),
        BarPlace(name: "sideways beside the sidebar", width: 874, sharesRowWithUndoRedoAndWrite: false),
        BarPlace(name: "upright", width: 834, sharesRowWithUndoRedoAndWrite: false),
        BarPlace(name: "upright beside Undo, Redo and Write", width: 834, sharesRowWithUndoRedoAndWrite: true),
    ]

    func testTheOwnersToolboxKeepsEveryColorTheRulerAndTheWritingToolsOnTheBar() async throws {
        let suiteName = "PencilBarOwnersToolbox-\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        isolatedDefaults.set(Data(Self.ownersToolboxRecord.utf8), forKey: PencilToolbox.storageKey)
        let toolbox = PencilToolbox(defaults: isolatedDefaults)
        try PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(true)
        defer {
            try? PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(false) // Left on, it slows later tests.
            isolatedDefaults.removePersistentDomain(forName: suiteName)
        }
        XCTAssertEqual(toolbox.presets.map(\.ink), [.monoline, .pencil, .highlighter], "The store reads his toolbox, not the default presets.")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        weak var previousController: UIViewController?
        for place in Self.places {
            for toolIndex in 0..<(toolbox.presets.count + 2) {
                try await waitUntil("the bar before is let go") { previousController == nil }
                let toolName = takeUpTool(at: toolIndex, of: toolbox)
                PencilToolRowForm.lastShown = nil
                let controller = UIHostingController(rootView: bar(toolbox: toolbox, at: place)
                    .frame(width: place.width, height: PencilToolbarMetrics.height)
                    .background(Color(uiColor: .systemBackground))
                    .defaultAppStorage(isolatedDefaults))
                previousController = controller
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 100, width: place.width, height: 60)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                let label = "\(toolName) in use, \(place.name) (\(Int(place.width)) points)"
                let visibleLabels = try await labelsWhollyOnScreen(in: controller.view, window: window, waitingFor: label)
                let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
                print("Owner's toolbox, \(label): \(shownRow.arrangement); on the bar: \(visibleLabels.joined(separator: ", "))")
                let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                })
                screenshot.name = "Owner's Pencil bar, \(label): \(shownRow.arrangement)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTAssertNotEqual(shownRow.form, .condensed, "\(label): the colors are on the bar.")
                for expected in expectedLabels(toolbox: toolbox, sharesRowWithUndoRedoAndWrite: place.sharesRowWithUndoRedoAndWrite) {
                    XCTAssertTrue(visibleLabels.contains(expected), "\(label): \(expected) is a button wholly on the bar.")
                }
            }
        }
    }

    /// Takes up his inks in turn, then the eraser and the lasso; returns the tool's name.
    private func takeUpTool(at toolIndex: Int, of toolbox: PencilToolbox) -> String {
        if toolbox.presets.indices.contains(toolIndex) {
            toolbox.usePreset(at: toolIndex)
            return toolbox.presetInUse.ink.title
        }
        let kind: PencilToolKind = toolIndex == toolbox.presets.count ? .eraser : .lasso
        toolbox.use(kind)
        return kind.title
    }

    /// The bar as a PDF shows it: the row alone, its side's tab bar holding Undo, Redo and Write, or the bar with them at
    /// its end, as `PDFPane` builds it in Focus.
    @ViewBuilder private func bar(toolbox: PencilToolbox, at place: BarPlace) -> some View {
        if place.sharesRowWithUndoRedoAndWrite {
            let undoAvailability = UndoAvailability()
            PencilToolbar(toolbox: toolbox, drawsShapes: .constant(false), addImage: {}, undoAvailability: undoAvailability,
                          offersReadAloudPen: true, offersTextBoxes: true) {
                EmptyView()
            } trailingControls: {
                HStack(spacing: 12) {
                    UndoRedoButtons(availability: undoAvailability)
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                    DocumentModeToggle(isWriting: .constant(true), drawsOwnBackground: true)
                }
            }
        } else {
            PencilToolRow(toolbox: toolbox, drawsShapes: .constant(false), addImage: {}, offersReadAloudPen: true, offersTextBoxes: true)
        }
    }

    /// What must be on the bar: each of his inks, the eraser, the lasso, the ruler, Add Image, black and every favorite
    /// color (the highlighter's colors while it is in use), and Undo and Redo where the bar shares their row.
    private func expectedLabels(toolbox: PencilToolbox, sharesRowWithUndoRedoAndWrite: Bool) -> [String] {
        let colors = PencilToolRowLayout.editsHighlighterColors(toolbox) ? PaletteColor.defaultHighlighterPalette.map(\.name)
            : ["black"] + PaletteColor.defaultPalette.map(\.name)
        return toolbox.presets.map(\.ink.title) + ["Eraser", "Lasso", "Ruler", "Add Image"] + colors
            + (sharesRowWithUndoRedoAndWrite ? ["Undo", "Redo"] : [])
    }

    /// The labels of the bar's elements standing wholly inside the window, left to right, once the bar has settled and
    /// its ruler is accessible.
    private func labelsWhollyOnScreen(in view: UIView, window: UIWindow, waitingFor label: String) async throws -> [String] {
        try await waitUntil("the bar shows, \(label)") { PencilToolRowForm.lastShown != nil }
        var lastRowFrame = CGRect.null
        var unchangedPolls = 0
        try await waitUntil("the bar has settled, \(label)") {
            guard let frame = PencilToolRowForm.lastShown?.frameInWindow else { return false }
            unchangedPolls = frame == lastRowFrame ? unchangedPolls + 1 : 0
            lastRowFrame = frame
            return unchangedPolls >= 10
        }
        var elements: [NSObject] = []
        try await waitUntil("the bar's buttons are accessible, \(label)", pollingIntervalSeconds: 0.25) {
            elements = PencilBarPlacementHostedTests.accessibilityElements(in: view)
            return elements.contains { element in element.accessibilityLabel == "Ruler" }
        }
        let windowFrame = window.frame
        return elements
            .filter { element in
                let frame = element.accessibilityFrame
                return element.accessibilityLabel?.isEmpty == false && frame.width >= 12
                    && frame.minX >= windowFrame.minX - 0.5 && frame.maxX <= windowFrame.maxX + 0.5
            }
            .sorted { leftElement, rightElement in leftElement.accessibilityFrame.minX < rightElement.accessibilityFrame.minX }
            .compactMap(\.accessibilityLabel)
    }
}
#endif
