/**
 * File: PencilBarPlacementHostedTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the fixed Pencil bar over a PDF on the 11-inch iPad, upright and sideways: a row of its
 *              own, centered over the page, with every tool and the sizes of the tool in use on it, the same tools in
 *              the same order both ways, and every favorite color and the ruler on the bar at every width (HUNT-312,
 *              HUNT-310, HUNT-311, HUNT-317).
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 04/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The owner's report of 2026-11-04: the tools were "squished to the right" of the tab bar with their sizes and
/// colors behind one control, and the bar looked different upright and sideways. These tests put a PDF that is
/// written on in a real window at both sizes of the 11-inch iPad and read where the bar's row stands and which form
/// it took. Nothing here plays sound.
@MainActor
final class PencilBarPlacementHostedTests: XCTestCase {
    /// The device settings the hosted workspaces read their `@AppStorage` from, with the fixed bar chosen, and what
    /// they held before.
    private var deviceDefaults: UserDefaults?
    private var savedToolbarStyle: Any?

    override func tearDown() async throws {
        guard let deviceDefaults else { return }
        if let savedToolbarStyle { deviceDefaults.set(savedToolbarStyle, forKey: PencilToolbarStyle.preferenceKey) }
        else { deviceDefaults.removeObject(forKey: PencilToolbarStyle.preferenceKey) }
    }

    /// Chooses the fixed bar in the settings the workspace's views read, as Settings › Pencil Drawings does.
    private func chooseTheFixedBar(for workspace: WorkspaceModel) {
        if deviceDefaults == nil {
            deviceDefaults = workspace.deviceDefaults
            savedToolbarStyle = workspace.deviceDefaults.object(forKey: PencilToolbarStyle.preferenceKey)
        }
        workspace.deviceDefaults.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
    }

    private var scene: UIWindowScene {
        get throws { try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) }
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A vault holding a note and a four-page PDF, with the PDF open in the second tab and written on.
    private func pdfWorkspace(named name: String) async throws -> (WorkspaceModel, PDFSession) {
        let directory = try TemporaryVault.make(prefix: name, for: self).root
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 4).write(to: directory.appendingPathComponent("Paper.pdf"))
        try Data("# Untitled\n".utf8).write(to: directory.appendingPathComponent("Untitled.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Paper.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        chooseTheFixedBar(for: workspace)
        return (workspace, session)
    }

    private func host(_ workspace: WorkspaceModel, size: CGSize) throws -> UIWindow {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: try scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    /// Where the bar's row stands over the PDF, sideways and upright: centered on the PDF's side, not at the end of
    /// the tab bar, and in a form that keeps every tool and the sizes on the bar.
    func testTheBarIsCenteredOverThePDFWithEveryToolUprightAndSideways() async throws {
        let toolbox = PencilToolbox.shared
        let savedPresetIndex = toolbox.toolInUse == .ink ? toolbox.presetInUseIndex : nil
        defer { if let savedPresetIndex { toolbox.usePreset(at: savedPresetIndex) } }
        toolbox.usePreset(at: 0)
        // The bar shows the device's own presets: on the owner's iPad (2026-11-04) the upright bar folded to its compact form.
        let savedToolbarStyle = HostedDevicePreferences.value(forKey: PencilToolbarStyle.preferenceKey)
        print("PENCIL-BAR placement: presets \(toolbox.presets.map(\.ink.rawValue)), toolbar style \(String(describing: savedToolbarStyle))")
        var formsByOrientation: [String: PencilToolRowForm] = [:]
        for (name, size) in [("sideways", CGSize(width: 1_194, height: 834)), ("upright", CGSize(width: 834, height: 1_194))] {
            let (workspace, session) = try await pdfWorkspace(named: "BarPlacement\(name)")
            PencilToolRowForm.lastShown = nil
            let window = try host(workspace, size: size)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitUntil("the PDF shows \(name)") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
            try await waitUntil("the bar shows \(name)") { PencilToolRowForm.lastShown != nil }
            let pdfView = try XCTUnwrap(session.pdfView)
            var lastRowFrame = CGRect.null
            var unchangedPolls = 0
            try await waitUntil("the bar has settled \(name)") {
                guard let frame = PencilToolRowForm.lastShown?.frameInWindow else { return false }
                unchangedPolls = frame == lastRowFrame ? unchangedPolls + 1 : 0
                lastRowFrame = frame
                return unchangedPolls >= 15
            }
            attachScreenshot(of: window, named: "Fixed Pencil bar over a PDF, 11-inch iPad \(name)")
            let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
            let pdfFrame = pdfView.convert(pdfView.bounds, to: window)
            XCTAssertEqual(shownRow.frameInWindow.midX, pdfFrame.midX, accuracy: 24, "\(name): the tools are centered over the PDF, not at the right edge.")
            XCTAssertGreaterThanOrEqual(shownRow.frameInWindow.minX, pdfFrame.minX - 1, "\(name): the bar is inside the PDF's side.")
            XCTAssertLessThanOrEqual(shownRow.frameInWindow.maxX, pdfFrame.maxX + 1, "\(name): the bar is inside the PDF's side.")
            XCTAssertEqual(shownRow.form, .full, "\(name): every tool, its sizes and every color are on the bar, nothing behind a menu (\(shownRow.arrangement)).")
            formsByOrientation[name] = shownRow.form
        }
        XCTAssertEqual(formsByOrientation.count, 2)
    }

    /// HUNT-312: the bar is above the page while the PDF is read too, so writing, begun by the Pencil or the bar, moves
    /// nothing: the PDF keeps its frame and its zoom, and its pages are not laid out for another size.
    func testStartingToWriteMovesNeitherThePageNorItsZoom() async throws {
        let (workspace, session) = try await pdfWorkspace(named: "BarWhileReading")
        session.isWriting = false
        PencilToolRowForm.lastShown = nil
        let window = try host(workspace, size: CGSize(width: 834, height: 1_194))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        try await waitUntil("the bar shows while the PDF is read") { PencilToolRowForm.lastShown != nil }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        var lastFrame = CGRect.null
        var unchangedPolls = 0
        try await waitUntil("the PDF has settled") {
            let frame = pdfView.convert(pdfView.bounds, to: window)
            unchangedPolls = frame == lastFrame ? unchangedPolls + 1 : 0
            lastFrame = frame
            return unchangedPolls >= 15
        }
        attachScreenshot(of: window, named: "PDF read, the bar above it")
        let frameWhileReading = pdfView.convert(pdfView.bounds, to: window)
        let zoomWhileReading = pdfView.scaleFactor
        let zoomChangesWhileReading = pdfView.zoomChangesForWidth
        session.isWriting = true
        var answers = 0
        try await waitUntil("the view has answered the switch to writing") {
            answers += 1
            return answers >= 20 && pdfView.window === window
        }
        attachScreenshot(of: window, named: "PDF written on, nothing moved")
        XCTAssertEqual(pdfView.convert(pdfView.bounds, to: window), frameWhileReading, "Writing moves the page neither down nor up.")
        XCTAssertEqual(pdfView.scaleFactor, zoomWhileReading, accuracy: 0.0001)
        XCTAssertEqual(pdfView.zoomChangesForWidth, zoomChangesWhileReading, "No zoom was chosen again for another size.")
        XCTAssertTrue(session.pdfView === pdfView, "The PDF's view is the same one, not built again.")
    }

    /// The row alone, at the widths of the 11-inch iPad: 834 upright, about 874 sideways beside the sidebar, and 514
    /// upright beside it. The sizes of the tool in use are on the bar at every one of them, for an ink and the eraser;
    /// beside the sidebar the laser pointer, the text tool and the Read Aloud pen are behind the More control (HUNT-317).
    func testTheSizesOfTheToolInUseAreOnTheBarAtEveryWidthOfTheElevenInchIPad() async throws {
        let toolbox = PencilToolbox.shared
        let savedPresetIndex = toolbox.toolInUse == .ink ? toolbox.presetInUseIndex : nil
        defer { if let savedPresetIndex { toolbox.usePreset(at: savedPresetIndex) } }
        let scene = try scene
        // The row of the width before, its window put away, still follows the shared toolbox until it is let go: on
        // GitHub's iPad it laid the eraser out at 874 points after the switch to the eraser and reported that (727.5
        // points wide) as the row at 514, where the screenshot showed the compact row fitting.
        weak var previousController: UIViewController?
        for tool in [PencilToolKind.ink, .eraser] {
            try await waitUntil("the row of the width before is let go") { previousController == nil }
            if tool == .ink { toolbox.usePreset(at: 0) } else { toolbox.use(.eraser) }
            for width in [514, 834, 874] as [CGFloat] {
                try await waitUntil("the row of the width before is let go") { previousController == nil }
                PencilToolRowForm.lastShown = nil
                let controller = UIHostingController(rootView: PencilToolRow(toolbox: toolbox, drawsShapes: .constant(false), addImage: {},
                                                                             offersReadAloudPen: true, offersTextBoxes: true)
                    .frame(width: width, height: PencilToolbarMetrics.height)
                    .background(Color(uiColor: .systemBackground)))
                previousController = controller
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 100, width: width, height: 60)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                try await waitUntil("the row shows at \(Int(width)) points") { PencilToolRowForm.lastShown != nil }
                let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
                attachScreenshot(of: window, named: "Pencil row, \(tool), \(Int(width)) points: \(shownRow.form)")
                XCTAssertLessThanOrEqual(shownRow.frameInWindow.width, width + 0.5)
                // Every form but the condensed one has the sizes of the ink or eraser in use on the bar.
                XCTAssertNotEqual(shownRow.form, .condensed, "\(tool) at \(Int(width)) points: the sizes stay on the bar.")
            }
        }
    }

    // MARK: HUNT-317: every favorite color and the ruler on the bar

    /// The owner's report of 2026-11-04: "what happened to the row of colors we used to see", and the ruler and the other
    /// tools only behind the bar's "…". The row alone, with the pen in use and the default favorite colors, at 514 points
    /// (upright beside the sidebar), 834 (upright) and 1,194 (sideways): black and every favorite color are whole on
    /// screen, each its own button, and the ruler is a button on the bar. The form shown is the one `PencilToolRowLayout`
    /// chooses for the width, and the row is as wide as it says.
    func testEveryFavoriteColorAndTheRulerAreButtonsOnTheBarAtEveryWidthOfTheElevenInchIPad() async throws {
        let toolbox = PencilToolbox.shared
        let savedTool = toolbox.toolInUse
        let savedPresetIndex = toolbox.presetInUseIndex
        // Settings of their own, which hold no colors: the row shows the default favorite colors.
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: "PencilBarColors-\(UUID().uuidString)"))
        try Self.setAccessibilityRuntimeEnabled(true)
        defer {
            try? Self.setAccessibilityRuntimeEnabled(false) // Left on, it slows later tests and changes nothing they check.
            if savedTool == .ink { toolbox.usePreset(at: savedPresetIndex) } else { toolbox.use(savedTool) }
        }
        toolbox.usePreset(at: try XCTUnwrap(toolbox.presets.firstIndex { preset in preset.ink == .pen }))
        let favorites = PaletteColor.defaultPalette
        let contents = PencilToolRowLayout.Contents(
            tools: PencilToolRowLayout.tools(presetCount: toolbox.presets.count, offersTextBoxes: true, offersReadAloudPen: true),
            toolInUse: .preset(index: toolbox.presetInUseIndex), sizeCount: 3, offersColors: true, swatchCount: 1 + favorites.count,
            showsAddColor: PencilColorButtons.showsAddColor(toolbox, favorites: favorites, highlighterColors: PaletteColor.defaultHighlighterPalette),
            offersImages: true)
        let scene = try scene
        weak var previousController: UIViewController?
        for width in [514, 834, 1_194] as [CGFloat] {
            try await waitUntil("the row of the width before is let go") { previousController == nil }
            PencilToolRowForm.lastShown = nil
            let controller = UIHostingController(rootView: PencilToolRow(toolbox: toolbox, drawsShapes: .constant(false), addImage: {},
                                                                         offersReadAloudPen: true, offersTextBoxes: true)
                .frame(width: width, height: PencilToolbarMetrics.height)
                .background(Color(uiColor: .systemBackground))
                .defaultAppStorage(isolatedDefaults))
            previousController = controller
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 100, width: width, height: 60)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            let expected = PencilToolRowLayout.arrangement(forWidth: Double(width), holding: contents)
            try await waitUntil("the row shows at \(Int(width)) points") { PencilToolRowForm.lastShown?.arrangement == expected }
            let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
            attachScreenshot(of: window, named: "Pencil row with the pen, \(Int(width)) points: \(shownRow.arrangement)")
            XCTAssertNotEqual(shownRow.form, .condensed, "\(Int(width)) points: the colors are on the bar, not behind a control.")
            if case .compactWithScrollingColors = expected { XCTFail("\(Int(width)) points: the default colors all fit; none scrolls.") }
            // The bar is built at the layout's widths: the row measured here is as wide as the layout says.
            let expectedWidth = try XCTUnwrap(PencilToolRowLayout.width(of: expected, holding: contents))
            XCTAssertEqual(Double(shownRow.frameInWindow.width), expectedWidth, accuracy: 1, "\(Int(width)) points: the row's measured width.")
            XCTAssertLessThanOrEqual(shownRow.frameInWindow.width, width + 0.5)

            var elements: [NSObject] = []
            try await waitUntil("the row's buttons are accessible at \(Int(width)) points", pollingIntervalSeconds: 0.25) {
                elements = self.accessibilityElements(in: controller.view)
                return elements.contains { element in element.accessibilityLabel == "Ruler" }
            }
            let windowFrame = window.frame
            /// Whether an element with `label` stands wholly inside the window, at least as wide as a mini color.
            func isWhollyOnScreen(_ label: String) -> Bool {
                elements.contains { element in
                    let frame = element.accessibilityFrame
                    return element.accessibilityLabel == label && frame.minX >= windowFrame.minX - 0.5 && frame.maxX <= windowFrame.maxX + 0.5
                        && frame.width >= PencilToolRowLayout.Density.tightest.swatchPitch - 0.5
                }
            }
            for colorName in ["black"] + favorites.map(\.name) {
                XCTAssertTrue(isWhollyOnScreen(colorName), "\(Int(width)) points: \(colorName) is a button wholly on the bar.")
            }
            let ruler = elements.first { element in element.accessibilityLabel == "Ruler" }
            XCTAssertTrue(isWhollyOnScreen("Ruler"), "\(Int(width)) points: the ruler is on the bar.")
            XCTAssertTrue(ruler?.accessibilityTraits.contains(.button) == true, "\(Int(width)) points: the ruler is a button, not a menu item.")
        }
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
