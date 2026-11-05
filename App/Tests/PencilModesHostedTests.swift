/**
 * File: PencilModesHostedTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Hosted tests that the two ways of writing on a PDF (Settings › Pencil Drawings: Graphite's fixed bar,
 *              or the system's floating palette with Graphite's button at its end) offer the same tools, and that with
 *              the palette Add Image and Graphite's tools are buttons of the PDF's toolbar (HUNT-309).
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 05/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
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

    // MARK: The floating palette's companions in the toolbar

    /// The owner's report of 2026-11-04: "When I'm using the floating Apple Pencil utilities, I cannot add an image." A
    /// PDF written on with the Floating Palette, in a window of the 11-inch iPad held sideways: Add Image, the text tool,
    /// Graphite's lasso and the laser pointer are buttons of the PDF's toolbar, each one tap away, as on the Fixed Bar.
    func testWithTheFloatingPaletteAddImageAndGraphitesToolsAreButtonsOfTheToolbar() async throws {
        let directory = try TemporaryVault.make(prefix: "FloatingPaletteActions", for: self).root
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 2).write(to: directory.appendingPathComponent("Paper.pdf"))
        try Data("# Untitled\n".utf8).write(to: directory.appendingPathComponent("Untitled.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Paper.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        let deviceDefaults = workspace.deviceDefaults
        let savedToolbarStyle = deviceDefaults.object(forKey: PencilToolbarStyle.preferenceKey)
        deviceDefaults.set(PencilToolbarStyle.floating.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        try Self.setAccessibilityRuntimeEnabled(true)
        defer {
            try? Self.setAccessibilityRuntimeEnabled(false) // Left on, it slows later tests and changes nothing they check.
            if let savedToolbarStyle { deviceDefaults.set(savedToolbarStyle, forKey: PencilToolbarStyle.preferenceKey) }
            else { deviceDefaults.removeObject(forKey: PencilToolbarStyle.preferenceKey) }
        }
        session.isWriting = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_194, height: 834)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }

        let actions = ["Add Image", "Text Box", "Select Ink", "Laser Pointer"]
        var elements: [NSObject] = []
        try await waitUntil("the palette's companions are in the toolbar", timeoutSeconds: 30, pollingIntervalSeconds: 0.25) {
            elements = self.accessibilityElements(in: window)
            return actions.allSatisfy { action in elements.contains { element in element.accessibilityLabel == action } }
        }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Floating Palette: Add Image and Graphite's tools in the PDF's toolbar"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(PencilToolbarStyle.fixed.rawValue == deviceDefaults.string(forKey: PencilToolbarStyle.preferenceKey), "The Floating Palette is chosen.")
        for action in actions {
            let element = try XCTUnwrap(elements.first { element in element.accessibilityLabel == action }, "\(action) is in the toolbar.")
            XCTAssertTrue(element.accessibilityTraits.contains(.button), "\(action) is a button, one tap away.")
            XCTAssertTrue(window.bounds.intersects(element.accessibilityFrame), "\(action) is on screen.")
        }

        // A tap on Select Ink takes up Graphite's lasso for the palette's canvases, as the palette's own menu does.
        let inkSelection = PaletteInkSelection.of(scene)
        inkSelection.tool = .none
        let selectInk = try XCTUnwrap(elements.first { element in element.accessibilityLabel == "Select Ink" })
        let howActivated = activate(selectInk, in: window)
        print("PENCIL-MODES Select Ink, a \(type(of: selectInk)) at \(selectInk.accessibilityFrame), activated by \(howActivated)")
        try await waitUntil("the lasso is taken up") { inkSelection.tool == .lasso }
        inkSelection.tool = .none
    }

    /// Activates a toolbar button as VoiceOver does: its own activation, else the control under its activation point,
    /// as VoiceOver's double tap reaches it. On the owner's iPad (2026-11-05) the toolbar's button answered false to its
    /// activation, which VoiceOver then follows with a tap. Returns how it was activated.
    private func activate(_ element: NSObject, in window: UIWindow) -> String {
        if element.accessibilityActivate() { return "its accessibility activation" }
        let point = window.convert(element.accessibilityActivationPoint, from: window.screen.coordinateSpace)
        var view = window.hitTest(point, with: nil)
        while let candidate = view, !(candidate is UIControl) { view = candidate.superview }
        guard let control = view as? UIControl else { return "nothing: no control under \(point)" }
        var events: UIControl.Event = []
        control.enumerateEventHandlers { _, _, event, _ in events.insert(event) }
        let event: UIControl.Event = events.contains(.primaryActionTriggered) ? .primaryActionTriggered : .touchUpInside
        control.sendActions(for: event)
        return "the \(type(of: control)) under its activation point, event \(event.rawValue)"
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
    }
}
#endif
