/**
 * File: NotePDFMenuHostedTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Export to PDF…, Print… and Start Presentation taken from a note's More menu in the iPad's window, on a
 *              demo vault of course notes: the options sheet with its preview, the file exporter it hands the PDF to, the
 *              system's print panel after the progress sheet, and the note's slides full screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import GraphiteCore
@testable import GraphiteUI

/// More › File › Export to PDF… and Print… of a note in the whole window on the iPad simulator. The menu's items are
/// found in the bar button's own menu and run as a tap on them runs them; the sheets and panels they open are found
/// in the window's presented controllers. The vault is two course notes of the test vault, shortened, never a
/// person's own notes. Nothing here plays sound or prints: the print panel is closed as soon as it is shown.
@MainActor
final class NotePDFMenuHostedTests: SettingsHostedTestCase {
    /// Shortened from the test vault's `9_Static logic` (Digital IC Design): wide formulas and a callout.
    private static let staticLogicNote = #"""
        # Static logic

        ## DCVSPG design examples

        **AND/NAND**

        $$\bar{f} = \overline{x \cdot y} = \bar{x} + \bar{y} = \bar{x} \cdot 1 + x \cdot \bar{y}$$

        $$f = x \cdot y = \bar{x} \cdot 0 + x \cdot y$$

        ### Carry of a full adder

        $$Carry = x \cdot y + y \cdot z + x \cdot z = \bar{z} \cdot (x \cdot y) + z \cdot (y + x) \#
         = \bar{z} \cdot (\bar{x} \cdot 0 + x \cdot y) + z \cdot (\bar{x} \cdot y + x \cdot 1)$$

        ## DPL (Double Pass-Transistor Logic)

        - Pass-transistor logic which uses both nMOS and pMOS switches
        	- True and complementary inputs and outputs deliver rail-to-rail output
        	- Symmetric arrangement of transistors

        > [!note]
        > The pMOS network implements the complementary pass-gate logic (pMOS implementation of $y'$).
        """#

    /// Shortened from the test vault's `Lecture_L01_Shannon` (Digital IC Design): folded callouts with derivations.
    private static let shannonNote = #"""
        # Lecture L01 — Shannon's Expansion Theorem

        > [!note]- PUN Equation — Slide 29
        > The PUN equation of Slide #29 is correct as follows:
        >
        > $$f = (\bar{w} + \bar{x})(\bar{y} + \bar{z})$$

        > [!note]- Shannon's Expansion — w.r.t. variable $x$
        > $$f(x,y,z) = xy + yz + xz$$
        >
        > Expanding w.r.t. $x$:
        >
        > $$= x(y + yz + z) + \bar{x}(yz)$$
        """#

    /// Three slides, as Obsidian's Slides splits them.
    private static let slidesNote = "# Sampling\n\nA signal read every $T$ seconds.\n\n---\n\n## Nyquist\n\n$$\nf_s > 2 f_{max}\n$$\n\n---\n\n> [!note] Aliasing\n> Too slow.\n"

    private static let windowSize = CGSize(width: 1180, height: 820)

    override func tearDown() async throws {
        UIPrintInteractionController.shared.dismiss(animated: false)
        try await super.tearDown()
    }

    /// The window of a workspace with the demo vault open and `note` in front.
    private func showNote(_ note: String) async throws -> (workspace: WorkspaceModel, controller: UIViewController) {
        let vault = try TemporaryVault.make(prefix: "NotePDFMenuHosted", files: [
            "Digital IC Design/Static logic.md": Self.staticLogicNote,
            "Digital IC Design/Lecture L01 Shannon.md": Self.shannonNote,
            "Digital IC Design/Sampling slides.md": Self.slidesNote,
        ], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        try await waitUntil("the vault is indexed") { workspace.hasCompletedIndexScan }
        await workspace.open(try VaultPath(note))
        // Start Presentation as the window's scene adds it (`GraphiteWindowScene`).
        let launcher = NotePresentationLauncher(isEnabled: true, focusedNote: workspace.markdownSession,
                                                vault: ReadingVault(workspace.folderAccess?.root, workspace.index, store: workspace.store),
                                                readingConfiguration: ReadingConfiguration(),
                                                appearance: PresentationAppearance(noteTheme: nil, typography: .standard, codeColorTheme: .obsidian,
                                                                                   accent: .blue, colorScheme: .light),
                                                deviceDefaults: device.defaults, clock: LiveApplicationClock())
        let controller = try host(GraphiteRootView(workspace: workspace).modifier(launcher), size: Self.windowSize, horizontalSizeClass: .regular)
        try await waitUntil("the note is in front") { workspace.markdownSession?.path.rawValue == note }
        return (workspace, controller)
    }

    // MARK: The More menu

    /// The More menu of the window's bar, read as opening it fills it.
    private let moreMenu = MoreMenuReader()

    /// Runs the More menu's item as a tap on it runs it.
    private func choose(_ title: String, inSubmenu submenu: String, of controller: UIViewController) async throws {
        var entry: (path: [String], action: UIAction)?
        try await waitUntil("More › \(submenu) › \(title)", timeoutSeconds: 15) {
            entry = self.moreMenu.entries(in: controller).first { entry in entry.action.title == title }
            return entry != nil
        }
        guard let entry else {
            let titles = moreMenu.entries(in: controller).map { entry in (entry.path + [entry.action.title]).joined(separator: " › ") }
            return XCTFail("More has \(title): \(titles)")
        }
        XCTAssertEqual(entry.path.last, submenu, "\(title) is in More › \(submenu).")
        entry.action.performWithSender(nil, target: nil)
    }

    // MARK: What is presented

    /// The controllers the window presents, front last.
    private func presentedControllers(over controller: UIViewController) -> [UIViewController] {
        var presented: [UIViewController] = []
        var current = controller.presentedViewController
        while let shown = current {
            presented.append(shown)
            current = shown.presentedViewController
        }
        return presented
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPresented(over controller: UIViewController, named name: String) {
        let names = presentedControllers(over: controller).map { shown in String(describing: type(of: shown)) }
        let attachment = XCTAttachment(string: names.joined(separator: "\n"))
        attachment.name = "Presented when waiting for \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Tests

    func testExportToPDFFromTheMoreMenuShowsTheOptionsWithAPreviewThenTheFileExporter() async throws {
        let (_, controller) = try await showNote("Digital IC Design/Static logic.md")
        attachScreenshot(named: "Note before Export to PDF")
        try await choose("Export to PDF…", inSubmenu: "File", of: controller)

        // The options sheet, its preview of the first page drawn.
        let preview = try await element(in: controller, "the sheet's preview of the first pages") { object in
            object.accessibilityLabel == "Page 1"
        }
        XCTAssertGreaterThan(preview.accessibilityFrame.height, 100, "The preview shows the page.")
        _ = try await element(in: controller, "the sheet's Export button") { object in
            object.accessibilityLabel == "Export" && object.accessibilityTraits.contains(.button)
        }
        _ = try await element(in: controller, "the sheet's page size") { object in object.accessibilityLabel?.hasPrefix("Page Size") == true }
        attachScreenshot(named: "Export to PDF sheet from More")

        // Export hands the PDF to the system's file exporter, over the sheet.
        let exportButton = try await element(in: controller, "the sheet's Export button") { object in
            object.accessibilityLabel == "Export" && object.accessibilityTraits.contains(.button)
        }
        await follow(exportButton)
        var exporter: UIDocumentPickerViewController?
        try await waitUntil("the file exporter", timeoutSeconds: 40) {
            exporter = self.presentedControllers(over: controller).compactMap { shown in shown as? UIDocumentPickerViewController }.first
            return exporter != nil
        }
        if exporter == nil { attachPresented(over: controller, named: "the file exporter") }
        let shownExporter = try XCTUnwrap(exporter)
        try await waitUntil("the exporter is on screen", timeoutSeconds: 10) { shownExporter.viewIfLoaded?.window != nil }
        attachScreenshot(named: "File exporter for the PDF")
        shownExporter.dismiss(animated: false)
    }

    func testPrintFromTheMoreMenuShowsItsProgressThenTheSystemsPrintPanel() async throws {
        let (_, controller) = try await showNote("Digital IC Design/Lecture L01 Shannon.md")
        try await choose("Print…", inSubmenu: "File", of: controller)

        // The PDF is made with the last options, then the print panel shows it.
        var panelShown = false
        try await waitUntil("the print panel", timeoutSeconds: 40) {
            let presentedNames = self.presentedControllers(over: controller).map { shown in String(describing: type(of: shown)) }
            panelShown = presentedNames.contains("UIPrintPanelViewController")
            return panelShown
        }
        if !panelShown { attachPresented(over: controller, named: "the print panel") }
        let printing = UIPrintInteractionController.shared
        let printedData = try XCTUnwrap((printing.printingItem ?? printing.printingItems?.first) as? Data, "The panel prints the note's PDF.")
        XCTAssertEqual(printedData.prefix(5), Data("%PDF-".utf8))
        XCTAssertEqual(UIPrintInteractionController.shared.printInfo?.jobName, "Lecture L01 Shannon")
        let settled = ContinuousClock.now + .seconds(2)
        try await waitUntil("the panel's preview", timeoutSeconds: 10) { ContinuousClock.now >= settled }
        attachScreenshot(named: "Print panel for the note")
        UIPrintInteractionController.shared.dismiss(animated: false)
    }

    func testStartPresentationFromTheMoreMenuShowsTheSlidesFullScreenAndLeavesTheNoteAsItWas() async throws {
        let (workspace, controller) = try await showNote("Digital IC Design/Sampling slides.md")
        let noteLocation = try XCTUnwrap(workspace.folderAccess?.root).appendingPathComponent("Digital IC Design/Sampling slides.md")
        try await choose("Start Presentation", inSubmenu: "File", of: controller)
        var surface: PresentationTouchSurfaceView?
        try await waitUntil("the slides full screen", timeoutSeconds: 15) {
            surface = self.presentedControllers(over: controller).lazy.compactMap { shown in Self.touchSurface(in: shown.view) }.first
            return surface != nil
        }
        let shownSurface = try XCTUnwrap(surface)
        let window = try XCTUnwrap(self.window)
        let frame = shownSurface.convert(shownSurface.bounds, to: window)
        XCTAssertGreaterThan(frame.width, Self.windowSize.width - 1, "The slide covers the window: \(frame)")
        attachScreenshot(named: "First slide from More › File › Start Presentation")

        try SynthesizedInputCapability.requireItReachesSystemControls(
            "A real swipe and tap move to the next slides (checked on an iOS 26.5 simulator by XCUITest, 2026-11-27).")
        await SynthesizedTouches(window: window).drag(from: CGPoint(x: frame.maxX - 200, y: frame.midY),
                                                      to: CGPoint(x: frame.minX + 200, y: frame.midY), steps: 6, stepSeconds: 0.012, holdSeconds: 0)
        _ = try await element(in: controller, "the second slide's number") { object in object.accessibilityLabel == "2 of 3" }
        attachScreenshot(named: "Second slide after a swipe")

        let end = try await element(in: controller, "End Presentation") { object in object.accessibilityLabel == "End Presentation" }
        XCTAssertTrue(end.accessibilityActivate())
        try await waitUntil("the presentation ends", timeoutSeconds: 10) { self.presentedControllers(over: controller).isEmpty }
        XCTAssertEqual(try String(contentsOf: noteLocation, encoding: .utf8), Self.slidesNote, "Presenting writes nothing.")
        XCTAssertEqual(workspace.markdownSession?.text, Self.slidesNote)
    }

    private static func touchSurface(in view: UIView) -> PresentationTouchSurfaceView? {
        (view as? PresentationTouchSurfaceView) ?? view.subviews.lazy.compactMap(touchSurface(in:)).first
    }
}
#endif
