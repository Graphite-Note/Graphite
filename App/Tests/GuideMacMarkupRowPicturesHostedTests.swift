/**
 * File: GuideMacMarkupRowPicturesHostedTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: Takes the Graphite Guide's pictures of the Mac's PDF markup row, light and dark, inside the running Mac
 *              app: a copy of the guide vault opened in Graphite's window, its slides shown and the toolbar's Show
 *              Markup Toolbar button pressed with a click sent through AppKit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import GraphiteCore
@testable import GraphiteUI

/// Docs/Guide-vault-todo.md, section 2: the pictures `PDF markup on the Mac.md` shows. The row appears only after its
/// button is pressed, and a package test's window has no toolbar, so this runs inside the app, as
/// `MacPDFMarkupInAppHostedTests` does. Runs only with `TEST_RUNNER_GRAPHITE_GUIDE_MAC_MARKUP` given to xcodebuild as a
/// folder, where each picture is written as a JPEG for a person to look at; it checks only that the row was shown.
@MainActor
final class GuideMacMarkupRowPicturesHostedTests: XCTestCase {
    static let folderVariable = "GRAPHITE_GUIDE_MAC_MARKUP"
    private static let slides = "6 Everyday examples/Everyday Electronics/Week 1 slides.pdf"

    func testTakeTheGuidesPicturesOfTheMarkupRow() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let folder = ProcessInfo.processInfo.environment[Self.folderVariable] else { return }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppearanceMode.light, .dark] {
            let window = try await showSlides(in: appearance)
            try await click(atWindowPoint: try toolbarItemCenter(labelled: "Show Markup Toolbar", in: window), in: window)
            try await waitUntil("the row is shown", timeoutSeconds: 10) { window.toolbar?.items.contains { item in item.label == "Hide Markup Toolbar" } == true }
            try await settle(window)
            let name = appearance == .dark ? "Mac - The markup row, dark" : "Mac - The markup row"
            try writeJPEG(of: window, to: output.appendingPathComponent("\(name).jpg"))
            window.close()
        }
    }

    /// The guide vault copied into a folder of the test's own, so the checkout's copy is never written, and its slides
    /// shown in Graphite's window in `appearance`.
    private func showSlides(in appearance: AppearanceMode) async throws -> NSWindow {
        let vaultRoot = try TemporaryVault.make(prefix: "GuideMarkupRow", for: self).root.appendingPathComponent("Graphite Guide", isDirectory: true)
        try FileManager.default.copyItem(at: FixtureFolders.guideVault, to: vaultRoot)
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.appearanceMode = appearance
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        // The pass's window is light whatever Graphite's scheme; a scene's window follows `preferredColorScheme`.
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        _ = await workspace.open(try VaultPath(Self.slides), placement: .currentTab)
        try await waitUntil("the PDF is shown", timeoutSeconds: 30) { (workspace.pdfSession?.pageCount ?? 0) > 0 }
        try await settle(window)
        return window
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 60).measure({}, until: { true })
    }

    private func toolbarItemCenter(labelled label: String, in window: NSWindow) throws -> CGPoint {
        let item = try XCTUnwrap(window.toolbar?.items.first { item in item.label == label }, "no toolbar item labelled \(label)")
        let view = try XCTUnwrap(item.view)
        let frame = view.convert(view.bounds, to: nil)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// A press and release of the left button at `windowPoint`, through the application's queue as a hand's click arrives.
    private func click(atWindowPoint windowPoint: CGPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: false)
        }
        try await settle(window)
    }

    private func writeJPEG(of window: NSWindow, to location: URL) throws {
        let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))))
        try XCTUnwrap(image.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.62])).write(to: location)
    }
}
#endif
