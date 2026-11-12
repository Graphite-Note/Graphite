/**
 * File: ViewSwitchingBenchmarks.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The switches of views the owner found slow, timed in a vault of the owner's size on the Mac and the iPad:
 *              Library and List, the note's three views, another tab, and the sidebar's panels.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The switches of `Docs/View-switching-speed-todo.md` section 1 in an `OwnerShapedVault` of the owner's size, each made
/// six times, timed by `MainThreadQuietWatch`, with one `GRAPHITE-SWITCH` line per kind of switch. They are benchmarks of
/// `PerformanceBenchmarkTests` and run only when asked for, as those do:
/// `GRAPHITE_BENCHMARKS=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceBenchmarkTests/testSwitchingViews`
/// on the Mac, and `TEST_RUNNER_GRAPHITE_BENCHMARKS=1` with
/// `-only-testing:GraphiteIntegrationTests/PerformanceBenchmarkTests/testSwitchingViewsInAVaultOfTheOwnersSize` for the iPad.
extension PerformanceBenchmarkTests {
    private static let switchCount = 6

    func testSwitchingViewsInAVaultOfTheOwnersSize() async throws {
        let shape = OwnerShapedVault.ownersSize
        let (workspace, window) = try await ViewSwitchingWindow.open(shape, for: self)
        let quietWatch = MainThreadQuietWatch(window: window)
        _ = try await quietWatch.measure { workspace.preferences.library.presentation = .list }
        let rowsWithOpenFolders = try await Self.rowsOnceTheOpenFoldersAreListed(in: window)

        var toLibrary: [MainThreadQuietWatch.Measurement] = [], toList: [MainThreadQuietWatch.Measurement] = []
        for _ in 0..<Self.switchCount {
            toLibrary.append(try await quietWatch.measure { workspace.preferences.library.presentation = .library })
            toList.append(try await quietWatch.measure({ workspace.preferences.library.presentation = .list },
                                                       until: { Self.fileTreeRowCount(in: window) >= rowsWithOpenFolders }))
        }
        MainThreadQuietWatch.report(scenario: "list-to-library", shape: shape, measurements: toLibrary)
        MainThreadQuietWatch.report(scenario: "library-to-list", shape: shape, measurements: toList)
        try await measureNoteViewSwitches(workspace: workspace, quietWatch: quietWatch, shape: shape)
        try await measureTabSwitches(workspace: workspace, quietWatch: quietWatch, shape: shape)

        var toTags: [MainThreadQuietWatch.Measurement] = [], toFiles: [MainThreadQuietWatch.Measurement] = []
        for _ in 0..<Self.switchCount {
            toTags.append(try await quietWatch.measure { workspace.deviceDefaults.set(SidebarPanel.tags.rawValue, forKey: SidebarPanelSettingKey.panel) })
            toFiles.append(try await quietWatch.measure({ workspace.deviceDefaults.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel) },
                                                        until: { Self.fileTreeRowCount(in: window) >= rowsWithOpenFolders }))
        }
        MainThreadQuietWatch.report(scenario: "sidebar-files-to-tags", shape: shape, measurements: toTags)
        MainThreadQuietWatch.report(scenario: "sidebar-tags-to-files", shape: shape, measurements: toFiles)
    }

    private func measureNoteViewSwitches(workspace: WorkspaceModel, quietWatch: MainThreadQuietWatch, shape: OwnerShapedVault) async throws {
        let session = try XCTUnwrap(workspace.markdownSession, "The long lecture is in front.")
        var toReading: [MainThreadQuietWatch.Measurement] = [], toLivePreview: [MainThreadQuietWatch.Measurement] = []
        var toSource: [MainThreadQuietWatch.Measurement] = [], fromSource: [MainThreadQuietWatch.Measurement] = []
        for _ in 0..<Self.switchCount {
            toReading.append(try await quietWatch.measure { session.viewMode = .reading })
            toLivePreview.append(try await quietWatch.measure { session.viewMode = .livePreview })
            toSource.append(try await quietWatch.measure { session.viewMode = .source })
            fromSource.append(try await quietWatch.measure { session.viewMode = .livePreview })
        }
        MainThreadQuietWatch.report(scenario: "live-preview-to-reading", shape: shape, measurements: toReading)
        MainThreadQuietWatch.report(scenario: "reading-to-live-preview", shape: shape, measurements: toLivePreview)
        MainThreadQuietWatch.report(scenario: "live-preview-to-source", shape: shape, measurements: toSource)
        MainThreadQuietWatch.report(scenario: "source-to-live-preview", shape: shape, measurements: fromSource)
    }

    /// Between a short note's tab and the long lecture's, each shown once before.
    private func measureTabSwitches(workspace: WorkspaceModel, quietWatch: MainThreadQuietWatch, shape: OwnerShapedVault) async throws {
        let longLectureTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath(OwnerShapedVault.longLecturePath)))
        let shortNoteTab = try XCTUnwrap(workspace.layout.focusedGroup.tabs.first?.id)
        var toShortNote: [MainThreadQuietWatch.Measurement] = [], toLongLecture: [MainThreadQuietWatch.Measurement] = []
        for _ in 0..<Self.switchCount {
            toShortNote.append(try await quietWatch.measure { workspace.activateTab(shortNoteTab) })
            toLongLecture.append(try await quietWatch.measure { workspace.activateTab(longLectureTab) })
        }
        MainThreadQuietWatch.report(scenario: "tab-to-short-note", shape: shape, measurements: toShortNote)
        MainThreadQuietWatch.report(scenario: "tab-to-long-lecture", shape: shape, measurements: toLongLecture)
    }

    // MARK: The file tree

    /// The Mac's file tree once its three open folders are listed; the iPad's file list is SwiftUI's, which the watch
    /// times without asking for its rows.
    private static func rowsOnceTheOpenFoldersAreListed(in window: MainThreadQuietWatch.Window) async throws -> Int {
        #if os(macOS)
        try await waitUntil("the open folders are listed", timeoutSeconds: 60) { fileTreeRowCount(in: window) > 1_000 }
        #endif
        return fileTreeRowCount(in: window)
    }

    private static func fileTreeRowCount(in window: MainThreadQuietWatch.Window) -> Int {
        #if os(macOS)
        func fileTree(in view: NSView) -> FileTreeOutlineView? {
            (view as? FileTreeOutlineView) ?? view.subviews.lazy.compactMap(fileTree).first
        }
        return window.contentView.flatMap(fileTree)?.numberOfRows ?? 0
        #else
        return 0
        #endif
    }
}
