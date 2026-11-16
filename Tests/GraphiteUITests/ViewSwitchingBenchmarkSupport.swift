/**
 * File: ViewSwitchingBenchmarkSupport.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A made-up vault shaped as the owner's (about 33,000 files and 3,000 nested tags), the window's root view
 *              opened over it, and a watch that times how long a switch of views keeps the main thread busy, for the
 *              Mac's and the iPad's switching tests and benchmarks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import SwiftUI
import XCTest
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

/// A made-up vault with the owner's proportions (2026-11-10: 32,843 files, 1,372 notes, about 3,000 distinct tags):
/// course folders of lecture notes, each note carrying its course's tags and two tags nested in one of many subjects, a
/// long lecture full of tables, code and formulas, and a folder of pictures in batches of a thousand. Nothing in it comes
/// from a real note.
@MainActor
struct OwnerShapedVault {
    let noteCount: Int
    let pictureCount: Int
    let subjectCount: Int

    /// 1,400 notes, 31,400 pictures and 3,000 nested tags (with the course tags, 3,174 in all).
    static let ownersSize = OwnerShapedVault(noteCount: 1_400, pictureCount: 31_400, subjectCount: 1_000)
    /// Small enough to write and index in a few seconds, for the tests that always run.
    static let small = OwnerShapedVault(noteCount: 300, pictureCount: 2_000, subjectCount: 200)

    /// The folders a window shows expanded in its file tree, 1,183 rows under them at the owner's size.
    static let expandedFolders = ["Course 0", "Attachments", "Attachments/Batch 0"]
    static let longLecturePath = "Course 0/Long lecture.md"

    var description: String { "notes=\(noteCount) pictures=\(pictureCount) subjects=\(subjectCount)" }

    /// Writes the vault's files and returns the notes a window opens in tabs, the long lecture last.
    func write(into vault: URL) throws -> [VaultPath] {
        let generated = GeneratedCourseVault(noteCount: noteCount)
        let fileManager = FileManager.default
        for (noteNumber, note) in generated.notes.enumerated() {
            let nestedTags = (0..<2).map { tagOffset in
                let tagNumber = (noteNumber * 2 + tagOffset) % (subjectCount * 2)
                return "#subject-\(tagNumber / 2)/part-\(tagNumber % 2)"
            }
            let location = vault.appendingPathComponent(note.path.rawValue)
            try fileManager.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((note.markdown + "\n\n" + nestedTags.joined(separator: " ") + "\n").utf8).write(to: location)
        }
        let batchSize = 1_000
        for batch in 0..<((pictureCount + batchSize - 1) / batchSize) {
            let folder = vault.appendingPathComponent("Attachments/Batch \(batch)", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for pictureNumber in (batch * batchSize)..<min(pictureCount, (batch + 1) * batchSize) {
                try Self.onePixelPNG.write(to: folder.appendingPathComponent("Pasted image \(pictureNumber).png"))
            }
        }
        let longLecture = try VaultPath(Self.longLecturePath)
        try Data(PerformanceBenchmarkTests.longLectureNote(sectionCount: 20).utf8).write(to: vault.appendingPathComponent(longLecture.rawValue))
        return generated.notes.prefix(5).map(\.path) + [longLecture]
    }

    /// A one-pixel grey PNG, so the pictures are real pictures and cost almost no disk.
    private static let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4"
                                                        + "nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==") ?? Data()
}

/// Times a change from the moment it is made until the main thread has been quiet for a while and the window shows what
/// the change asked for. The watch polls every 5 ms and suspends in between, so SwiftUI's updates, layout, Core
/// Animation's commits and the main-actor tasks that bring background results (a folder's listing, the tags) all run;
/// a poll that comes much later than 5 ms means the main thread was busy meanwhile. Turning the run loop by hand
/// instead would hold the main actor, and those tasks would wait until the watch ended.
@MainActor
struct MainThreadQuietWatch {
    #if canImport(UIKit)
    typealias Window = UIWindow
    #else
    typealias Window = NSWindow
    #endif

    struct Measurement {
        /// From the change until the end of the last busy step.
        let busy: Duration
        /// From the change until the window showed what it asked for (the file tree's open folders, say).
        let shown: Duration
        /// The main thread's own processor time until the end of the last busy step.
        let mainThreadProcessor: Duration
        /// The longest single step, which the person sees as the window frozen.
        let longestStep: Duration
    }

    let window: Window
    /// How many quiet polls in a row end a measurement: 100, half a second without work after the window shows what was
    /// asked, for the switching benchmarks; the release pass, which measures hundreds of steps, waits less.
    var quietStepsToStop = 100
    private static let step = 0.005
    private static let busyStep = Duration.milliseconds(12)

    /// Makes `change`, then waits until `isShown` is true and the main thread has been quiet since.
    func measure(_ change: () -> Void, until isShown: () -> Bool = { true }) async throws -> Measurement {
        let start = ContinuousClock.now
        let processorStart = ProcessResourceUsage.mainThreadProcessorSeconds()
        change()
        var stepStart = ContinuousClock.now
        var lastBusyEnd = stepStart
        var processorAtLastBusy = ProcessResourceUsage.mainThreadProcessorSeconds()
        var longestStep = start.duration(to: stepStart)
        var quietSteps = 0
        var shownAt: ContinuousClock.Instant?
        try await waitUntil("the window shows what the switch asked for, then is quiet", timeoutSeconds: 60, pollingIntervalSeconds: Self.step) {
            layOut()
            let stepEnd = ContinuousClock.now
            let stepLength = stepStart.duration(to: stepEnd)
            stepStart = stepEnd
            longestStep = max(longestStep, stepLength)
            let showsIt = isShown()
            if showsIt { shownAt = shownAt ?? stepEnd } else { shownAt = nil }
            if stepLength > Self.busyStep {
                lastBusyEnd = stepEnd
                processorAtLastBusy = ProcessResourceUsage.mainThreadProcessorSeconds()
            }
            quietSteps = stepLength > Self.busyStep || !showsIt ? 0 : quietSteps + 1
            return quietSteps >= quietStepsToStop
        }
        return Measurement(busy: start.duration(to: lastBusyEnd), shown: start.duration(to: shownAt ?? .now),
                           mainThreadProcessor: .seconds(processorAtLastBusy - processorStart), longestStep: longestStep)
    }

    private func layOut() {
        #if canImport(UIKit)
        window.layoutIfNeeded()
        #else
        window.layoutIfNeeded()
        window.displayIfNeeded()
        #endif
    }

    /// One `GRAPHITE-SWITCH` line per scenario, each value per switch in order.
    static func report(scenario: String, shape: OwnerShapedVault, measurements: [Measurement]) {
        func milliseconds(_ duration: Duration) -> String {
            String(format: "%.0f", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        let busy = measurements.map { measurement in milliseconds(measurement.busy) }.joined(separator: "/")
        let shown = measurements.map { measurement in milliseconds(measurement.shown) }.joined(separator: "/")
        let processor = measurements.map { measurement in milliseconds(measurement.mainThreadProcessor) }.joined(separator: "/")
        let longest = measurements.map { measurement in milliseconds(measurement.longestStep) }.joined(separator: "/")
        print("GRAPHITE-SWITCH platform=\(PerformanceBenchmarkTests.platformNameForMeasurement) scenario=\(scenario) \(shape.description) "
              + "busy_ms=\(busy) shown_ms=\(shown) main_cpu_ms=\(processor) longest_step_ms=\(longest)")
    }
}

/// The window's root view over an `OwnerShapedVault` in Library mode, the library home shown over six notes in tabs, the
/// long lecture in front in Live Preview, and three folders open in the file tree: on the Mac in a window of its own with
/// its toolbar and title bridged as the app's scene does, on the iPad in a window of the iPad Pro 11-inch's size held
/// sideways. The window closes when the test ends.
@MainActor
enum ViewSwitchingWindow {
    /// - Parameter preparingVault: Writes more into the vault before it opens (a vault's community plugins, say).
    static func open(_ shape: OwnerShapedVault, for testCase: XCTestCase,
                     preparingVault: (URL) throws -> Void = { _ in }) async throws -> (WorkspaceModel, MainThreadQuietWatch.Window) {
        let device = try IsolatedWorkspaceDevice.make(for: testCase)
        let vault = try TemporaryVault.make(prefix: "ViewSwitching", for: testCase).root
        let notes = try shape.write(into: vault)
        try preparingVault(vault)
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .library
        try await workspace.openFolderAsVault(vault)
        try await waitUntil("the vault's index is built", timeoutSeconds: 300) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        for (tabNumber, path) in notes.enumerated() {
            await workspace.open(path, placement: tabNumber == 0 ? .currentTab : .newTab)
        }
        workspace.markdownSession?.viewMode = .livePreview
        workspace.expandedFolders.formUnion(try OwnerShapedVault.expandedFolders.map { folder in try VaultPath(folder) })
        let window = try host(GraphiteRootView(workspace: workspace), for: testCase)
        _ = try await MainThreadQuietWatch(window: window).measure {}
        return (workspace, window)
    }

    #if canImport(UIKit)
    private static func host(_ rootView: GraphiteRootView, for testCase: XCTestCase) throws -> UIWindow {
        let controller = UIHostingController(rootView: rootView)
        controller.traitOverrides.horizontalSizeClass = .regular
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_194, height: 834)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        testCase.addTeardownBlock { @MainActor in
            window.isHidden = true
            window.rootViewController = nil
        }
        return window
    }
    #else
    private static func host(_ rootView: GraphiteRootView, for testCase: XCTestCase) throws -> NSWindow {
        // As the app does before its first window.
        MacViewDrawing.drawLargeViewsWithoutTheMetalRenderer()
        let controller = NSHostingController(rootView: rootView)
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1_440, height: 900))
        window.showInvisibly()
        testCase.addTeardownBlock { @MainActor in
            window.contentViewController = nil
            window.close()
        }
        return window
    }
    #endif
}
