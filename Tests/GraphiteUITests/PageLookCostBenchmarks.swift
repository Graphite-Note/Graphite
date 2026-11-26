/**
 * File: PageLookCostBenchmarks.swift
 * ----------------------------------
 * Layer: Tests
 * Description: What icons, covers and columns cost in a vault of 3,000 notes: scrolling the Mac's file list from top to
 *              bottom and opening notes in the reading view, with the core plugin off, on without any icon, and on with
 *              icons on a third of the notes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// Runs with the other benchmarks: `GRAPHITE_BENCHMARKS=1 swift test -c release -Xswiftc -enable-testing
/// --filter PerformanceBenchmarkTests/testPageLookCost`. Each variant prints `GRAPHITE-BENCH` lines for the file list's
/// scroll and `GRAPHITE-SWITCH` lines for the notes opened. The switch is found by its stored name, so the same file
/// measures a build without the feature, where every variant is that build's own.
extension PerformanceBenchmarkTests {
    private enum PageLookVariant: String, CaseIterable {
        case off = "page-look-off"
        case onWithoutIcons = "page-look-on"
        case onWithIcons = "page-look-icons"

        var isOn: Bool { self != .off }
        var writesIcons: Bool { self == .onWithIcons }
    }

    private static let pageLookVault = OwnerShapedVault(noteCount: 3_000, pictureCount: 0, subjectCount: 200)
    private static let notesOpenedPerVariant = 8

    func testPageLookCostInAVaultOfThreeThousandNotes() async throws {
        for variant in PageLookVariant.allCases {
            let (workspace, window) = try await ViewSwitchingWindow.open(Self.pageLookVault, for: self) { vault in
                if variant.writesIcons { try Self.writeIcons(onAThirdOfTheNotesIn: vault) }
            }
            if let pageLook = CorePlugin(rawValue: "pageLook") { workspace.setCorePluginEnabled(pageLook, variant.isOn) }
            let quietWatch = MainThreadQuietWatch(window: window)
            _ = try await quietWatch.measure { workspace.preferences.library.presentation = .list }
            let courseFolders = try (0..<20).map { course in try VaultPath("Course \(course)") }
            _ = try await quietWatch.measure({ workspace.expandedFolders.formUnion(courseFolders) },
                                              until: { Self.fileTree(in: window)?.numberOfRows ?? 0 >= Self.pageLookVault.noteCount })
            try await measureFileListScroll(in: window, scenario: variant.rawValue + "-file-list-scroll")
            try await measureNoteOpening(workspace: workspace, quietWatch: quietWatch, scenario: variant.rawValue + "-note-open")
        }
    }

    private func measureFileListScroll(in window: NSWindow, scenario: String) async throws {
        let outline = try XCTUnwrap(Self.fileTree(in: window))
        let scrollView = try XCTUnwrap(outline.enclosingScrollView)
        let measurement = BenchmarkMeasurement(scenario: scenario, run: 1)
        var offset: CGFloat = 0
        let lastOffset = max(0, outline.bounds.height - scrollView.contentView.bounds.height)
        while offset < lastOffset {
            offset = min(lastOffset, offset + scrollView.contentView.bounds.height * 0.4)
            await measurement.measureFrame {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
            }
        }
        measurement.finish()
    }

    private func measureNoteOpening(workspace: WorkspaceModel, quietWatch: MainThreadQuietWatch, scenario: String) async throws {
        let notes = GeneratedCourseVault(noteCount: Self.pageLookVault.noteCount).notes
        var openings: [MainThreadQuietWatch.Measurement] = []
        for noteNumber in 0..<Self.notesOpenedPerVariant {
            let path = notes[noteNumber * 37 + 11].path
            openings.append(try await quietWatch.measure({
                Task {
                    await workspace.open(path, placement: .currentTab)
                    workspace.markdownSession?.viewMode = .reading
                }
            }, until: { workspace.activeDocument.loadedPath == path && workspace.markdownSession?.viewMode == .reading }))
        }
        MainThreadQuietWatch.report(scenario: scenario, shape: Self.pageLookVault, measurements: openings)
    }

    /// An emoji `icon` property at the top of every third note.
    private static func writeIcons(onAThirdOfTheNotesIn vault: URL) throws {
        let notes = GeneratedCourseVault(noteCount: pageLookVault.noteCount).notes
        for (noteNumber, note) in notes.enumerated() where noteNumber % 3 == 0 {
            let location = vault.appendingPathComponent(note.path.rawValue)
            let text = try String(contentsOf: location, encoding: .utf8)
            let withIcon = text.hasPrefix("---\n") ? "---\nicon: 📚\n" + text.dropFirst(4) : "---\nicon: 📚\n---\n" + text
            try Data(withIcon.utf8).write(to: location)
        }
    }

    private static func fileTree(in window: NSWindow) -> FileTreeOutlineView? {
        func search(_ view: NSView) -> FileTreeOutlineView? {
            (view as? FileTreeOutlineView) ?? view.subviews.lazy.compactMap(search).first
        }
        return window.contentView.flatMap(search)
    }
}
#endif
