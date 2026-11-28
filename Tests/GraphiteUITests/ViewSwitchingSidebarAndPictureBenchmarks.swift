/**
 * File: ViewSwitchingSidebarAndPictureBenchmarks.swift
 * ----------------------------------------------------
 * Layer: Tests
 * Description: The two switches of views the Mac's switching benchmark left out: showing and hiding the right sidebar
 *              beside the long lecture, and opening a picture of the vault in a tab; and pressing the window's
 *              toolbar buttons as AppKit delivers a click, for them and the Mac's switching tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Timed as `testSwitchingViewsInAVaultOfTheOwnersSize` times the others, in the same window and vault:
/// `GRAPHITE_BENCHMARKS=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceBenchmarkTests/testShowingTheRightSidebar`.
extension PerformanceBenchmarkTests {
    func testShowingTheRightSidebarAndOpeningAPictureInAVaultOfTheOwnersSize() async throws {
        let shape = OwnerShapedVault.ownersSize
        let (workspace, window) = try await ViewSwitchingWindow.open(shape, for: self)
        let quietWatch = MainThreadQuietWatch(window: window)
        _ = try await quietWatch.measure { workspace.preferences.library.presentation = .list }

        var showSidebar: [MainThreadQuietWatch.Measurement] = [], hideSidebar: [MainThreadQuietWatch.Measurement] = []
        for _ in 0..<6 {
            showSidebar.append(try await quietWatch.measure({ try? ViewSwitchingWindow.pressToolbarButton(labelled: "Sidebar", in: window) },
                                                            until: { ViewSwitchingWindow.showsRightSidebar(window) }))
            hideSidebar.append(try await quietWatch.measure({ try? ViewSwitchingWindow.pressToolbarButton(labelled: "Sidebar", in: window) },
                                                            until: { !ViewSwitchingWindow.showsRightSidebar(window) }))
        }
        MainThreadQuietWatch.report(scenario: "right-sidebar-show", shape: shape, measurements: showSidebar)
        MainThreadQuietWatch.report(scenario: "right-sidebar-hide", shape: shape, measurements: hideSidebar)

        let longLectureTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath(OwnerShapedVault.longLecturePath)))
        var openPicture: [MainThreadQuietWatch.Measurement] = []
        for pictureNumber in 0..<6 {
            let picture = try VaultPath("Attachments/Batch 0/Pasted image \(pictureNumber).png")
            openPicture.append(try await quietWatch.measure({ Task { await workspace.open(picture, placement: .currentTab) } },
                                                            until: { workspace.selection == picture }))
            _ = try await quietWatch.measure { workspace.activateTab(longLectureTab) }
        }
        MainThreadQuietWatch.report(scenario: "open-picture", shape: shape, measurements: openPicture)
    }
}

extension ViewSwitchingWindow {
    /// Whether the right sidebar's column is shown: the note's editor then ends more than 200 points before the
    /// window's right edge, which needs no view of SwiftUI's.
    static func showsRightSidebar(_ window: NSWindow) -> Bool {
        guard let contentWidth = window.contentView?.bounds.width else { return false }
        func editors(in view: NSView) -> [NSView] { (view is NSTextView ? [view] : []) + view.subviews.flatMap(editors) }
        let editorEnds = (window.contentView.map(editors) ?? []).map { editor in editor.convert(editor.bounds, to: nil).maxX }
        return (editorEnds.max() ?? contentWidth) < contentWidth - 200
    }

    /// A press and release at the middle of the toolbar item SwiftUI names `label`, sent through the window. The right
    /// sidebar is the root view's own state, so its button is the way to show it.
    static func pressToolbarButton(labelled label: String, in window: NSWindow) throws {
        let item = try XCTUnwrap(window.toolbar?.items.first { item in item.label == label }, "no toolbar item labelled \(label)")
        let view = try XCTUnwrap(item.view)
        let location = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }
}
#endif
