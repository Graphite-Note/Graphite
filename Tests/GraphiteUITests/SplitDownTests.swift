/**
 * File: SplitDownTests.swift
 * --------------------------
 * Layer: Tests
 * Description: Split Down: the two sides one above the other in the window, turning the split without building the
 *              editors again, and the direction kept between launches.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Split Down, as Obsidian's "Split down": the second side below the first.
@MainActor
final class SplitDownTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        TabTestBed.close(windows)
        windows.removeAll()
    }

    func testSplitDownShowsTheSidesOneAboveTheOtherAndTurningKeepsTheirEditors() async throws {
        let bed = try await TabTestBed.make(notes: ["Upper", "Lower"], for: self)
        bed.workspace.splitDown()
        bed.workspace.moveTabToOtherGroup(bed.tabs[1])
        XCTAssertEqual(bed.workspace.layout.splitDirection, .aboveAndBelow)
        let window = TabTestBed.window(width: 900, height: 1_000, showing: NavigationStack {
            WorkspacePanes(workspace: bed.workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        })
        windows.append(window)
        try await waitUntil("both notes are shown") { TabTestBed.shownNoteTitles(in: window).count == 2 }

        let editorsAboveAndBelow = try editorsByTitle(in: window)
        let upperFrame = try XCTUnwrap(editorsAboveAndBelow["Upper"]).frameInWindow
        let lowerFrame = try XCTUnwrap(editorsAboveAndBelow["Lower"]).frameInWindow
        // AppKit's window coordinates grow upward.
        XCTAssertGreaterThanOrEqual(upperFrame.minY, lowerFrame.maxY, "The first side is above the second.")
        XCTAssertGreaterThan(upperFrame.width, 800, "Each side takes the whole width: \(upperFrame.width)")
        XCTAssertLessThan(upperFrame.height, 600, "Each side takes part of the height: \(upperFrame.height)")
        saveSnapshot(of: window, named: "split-down-above-and-below")

        bed.workspace.splitRight()
        XCTAssertEqual(bed.workspace.layout.splitDirection, .sideBySide)
        try await waitUntil("the sides are side by side") {
            guard let editors = try? self.editorsByTitle(in: window), let upper = editors["Upper"], let lower = editors["Lower"] else { return false }
            return upper.frameInWindow.maxX <= lower.frameInWindow.minX
        }
        let editorsSideBySide = try editorsByTitle(in: window)
        XCTAssertTrue(editorsSideBySide["Upper"]?.textView === editorsAboveAndBelow["Upper"]?.textView, "Turning the split keeps the first side's editor.")
        XCTAssertTrue(editorsSideBySide["Lower"]?.textView === editorsAboveAndBelow["Lower"]?.textView, "Turning the split keeps the second side's editor.")
        saveSnapshot(of: window, named: "split-down-turned-side-by-side")
    }

    /// A picture of the window for a person to look at, when `GRAPHITE_SNAPSHOT_DIRECTORY` names a folder.
    private func saveSnapshot(of window: NSWindow, named name: String) {
        guard let directory = ProcessInfo.processInfo.environment["GRAPHITE_SNAPSHOT_DIRECTORY"], let contentView = window.contentView,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        try? representation.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")) // A picture that cannot be written is only not looked at.
    }

    func testTheDirectionIsKeptBetweenLaunches() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let vault = try TemporaryVault.make(prefix: "SplitDownVault", files: ["Notes.md": "# Notes\n", "Slides.md": "# Slides\n"], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Notes.md"))
        workspace.splitDown()
        await workspace.open(try VaultPath("Slides.md"))
        workspace.layout.splitFraction = 0.4

        let relaunched = device.makeWorkspace()
        try await relaunched.openFolderAsVault(vault)
        XCTAssertTrue(relaunched.layout.isSplit)
        XCTAssertEqual(relaunched.layout.splitDirection, .aboveAndBelow)
        XCTAssertEqual(relaunched.layout.splitFraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(relaunched.layout.groups.map { group in group.activeTab.path?.name }, ["Notes.md", "Slides.md"])
    }

    /// A note's editor and where it is in the window.
    private struct ShownEditor {
        let textView: MarkdownMacTextView
        let frameInWindow: CGRect
    }

    /// Every note's editor in the window, by the note's heading.
    private func editorsByTitle(in window: NSWindow) throws -> [String: ShownEditor] {
        TabTestBed.layOut(window)
        var editors: [String: ShownEditor] = [:]
        for textView in TabTestBed.textViews(in: window.contentView) where textView.window != nil && textView.visibleRect.width > 0 {
            guard let heading = textView.string.split(separator: "\n").first(where: { line in line.hasPrefix("# ") }) else { continue }
            let frame = textView.enclosingScrollView?.convert(textView.enclosingScrollView?.bounds ?? .zero, to: nil) ?? .zero
            editors[String(heading.dropFirst(2))] = ShownEditor(textView: textView, frameInWindow: frame)
        }
        return editors
    }
}
#endif
