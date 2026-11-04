/**
 * File: PencilModesHostedTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Hosted tests that the two ways of writing on a PDF (Settings › Pencil Drawings: Graphite's fixed bar,
 *              or the system's floating palette with Graphite's button at its end) offer the same tools (HUNT-309).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import GraphiteCore
@testable import GraphiteUI

/// The owner's report of 2026-11-04: "why is it that I cannot access a bunch of features when I use one of the two
/// modes to handwrite?" Each mode is read here as the person meets it: the palette's own tools and the menu of
/// Graphite's button at its end, and the fixed bar's tools. Nothing here plays sound.
@MainActor
final class PencilModesHostedTests: XCTestCase {
    private func titles(of elements: [UIMenuElement]) -> [String] {
        elements.flatMap { element -> [String] in
            if let menu = element as? UIMenu { return (menu.title.isEmpty ? [] : [menu.title]) + titles(of: menu.children) }
            return [(element as? UIAction)?.title].compactMap { $0 }
        }
    }

    /// The floating palette has, from the system, every ink, the eraser, its own lasso and the ruler, and from
    /// Graphite's button what the bar has besides: the favorite colors, adding the color in use to them, shapes, Graphite's
    /// lasso, the laser pointer, the text box and the Read Aloud pen.
    func testThePaletteOffersTheBarsToolsAndAddingAColor() throws {
        let toolPicker = PencilToolPalette.makeToolPicker()
        // The test must not change the tools the simulator's app remembers.
        toolPicker.stateAutosaveName = nil
        let systemTools = toolPicker.toolItems
        XCTAssertTrue(systemTools.contains { item in item is PKToolPickerEraserItem }, "The eraser, both kinds, with its widths")
        XCTAssertTrue(systemTools.contains { item in item is PKToolPickerLassoItem })
        XCTAssertTrue(systemTools.contains { item in item is PKToolPickerRulerItem })
        let inks = Set(systemTools.compactMap { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType })
        XCTAssertTrue(inks.isSuperset(of: [.pen, .pencil, .marker]), "The bar's three starting tools: \(inks)")

        let pen = try XCTUnwrap(systemTools.first { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType == .pen })
        toolPicker.selectedToolItemIdentifier = pen.identifier
        PencilToolPalette.applyColor(try XCTUnwrap(UIColor(graphiteHex: "#123abc")), to: toolPicker)
        let menuTitles = titles(of: PencilToolPalette.menuElements(for: toolPicker, inkSelection: PaletteInkSelection(),
                                                                   palette: [PaletteColor(name: "red", hex: "#e93147")], highlighterPalette: [],
                                                                   offersReadAloudPen: true, offersTextBoxes: true))
        for title in ["Favorite Colors", "Add to Favorite Colors", "Draw Shapes", "Select Ink", "Laser Pointer", "Text Box", "Read Aloud Pen"] {
            XCTAssertTrue(menuTitles.contains(title), "The palette's button offers \(title): \(menuTitles)")
        }

        PencilToolPalette.applyColor(try XCTUnwrap(UIColor(graphiteHex: "#e93147")), to: toolPicker)
        let titlesWithAFavoriteInUse = titles(of: PencilToolPalette.menuElements(for: toolPicker, inkSelection: PaletteInkSelection(),
                                                                                 palette: [PaletteColor(name: "red", hex: "#e93147")]))
        XCTAssertFalse(titlesWithAFavoriteInUse.contains("Add to Favorite Colors"), "A color in the list is not added again")
    }

    /// Adding the palette's color stores it where Settings › Colors and the bar read the favorite colors.
    func testAddingThePalettesColorStoresItWithTheFavoriteColors() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PencilModesHostedTests-\(UUID().uuidString)"))
        let toolPicker = PencilToolPalette.makeToolPicker()
        toolPicker.stateAutosaveName = nil
        let pen = try XCTUnwrap(toolPicker.toolItems.first { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType == .pen })
        toolPicker.selectedToolItemIdentifier = pen.identifier
        PencilToolPalette.applyColor(try XCTUnwrap(UIColor(graphiteHex: "#123abc")), to: toolPicker)
        let favorites = [PaletteColor(name: "red", hex: "#e93147")]
        let action = try XCTUnwrap(PencilToolPalette.addColorInUseAction(for: toolPicker, palette: favorites, storageKey: GraphitePreferences.colorPaletteKey,
                                                                         defaults: defaults))
        action.performWithSender(nil, target: nil)
        let stored = GraphitePreferences.colorPalette(decoding: defaults.data(forKey: GraphitePreferences.colorPaletteKey))
        XCTAssertEqual(stored.map(\.hex), ["#e93147", TextColorMarkup.canonicalHex("#123abc")])
    }

    /// The fixed bar has the palette's tools as Graphite's own: the inks, the eraser, the lasso, the laser pointer, the
    /// text box and the Read Aloud pen, each a button; shapes, the ruler and adding an image are on it too.
    func testTheBarOffersThePalettesTools() async throws {
        let tools = PencilToolRowLayout.tools(presetCount: 3, offersTextBoxes: true, offersReadAloudPen: true)
        XCTAssertEqual(tools, [.preset(index: 0), .preset(index: 1), .preset(index: 2), .eraser, .lasso, .laser, .text, .readAloud])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        PencilToolRowForm.lastShown = nil
        let controller = UIHostingController(rootView: PencilToolRow(toolbox: PencilToolbox.shared, drawsShapes: .constant(false), addImage: {},
                                                                     offersReadAloudPen: true, offersTextBoxes: true)
            .frame(width: 1_100, height: PencilToolbarMetrics.height)
            .background(Color(uiColor: .systemBackground)))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 100, width: 1_100, height: 60)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the bar shows") { PencilToolRowForm.lastShown != nil }
        XCTAssertEqual(PencilToolRowForm.lastShown?.form, .full, "Every tool, size, color and toggle on the bar at 1,100 points")
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "The fixed bar's tools"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
