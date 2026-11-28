/**
 * File: LibraryLargeVaultScrollingHostedTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The library of a made-up vault of 100,000 notes on the iPad: a folder of 10,000 notes scrolled as a quick
 *              finger scrolls it, each frame's gap measured, the app's memory and the previews kept for the tiles shown.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import Darwin
import Synchronization
import GraphiteCore
@testable import GraphiteUI

/// Docs/Notebook-library-and-new-file-todo.md, Verification: "A 100,000-file vault in the simulator: scrolling the library
/// stays smooth, memory stays within budget, no preview work for tiles not shown". The vault is 90 folders of 1,000 notes
/// and one of 10,000; the index reads it while the library scrolls, as it does when such a vault is first opened.
@MainActor
final class LibraryLargeVaultScrollingHostedTests: SettingsHostedTestCase {
    /// Points scrolled each frame: a quick flick's speed, 3,600 points a second at 60 frames a second.
    private static let step: CGFloat = 60
    /// Frames measured going down, then as many going back up.
    private static let framesEachWay = 600

    /// The library as a person without VoiceOver scrolls it: the base class switches the accessibility runtime on, which
    /// makes SwiftUI build every tile's accessibility element and actions as the tile appears.
    override func setUp() async throws {
        try await super.setUp()
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    func testScrollingAFolderOfTenThousandNotesInAVaultOfAHundredThousand() async throws {
        let folders = (0..<90).map { number in (String(format: "Folder %02d", number), 1_000) } + [("Ten thousand", 10_000)]
        let library = try await scroll("Ten thousand", inAVaultOf: folders)
        XCTAssertLessThan(library.visiblePreviews.count, 200, "Previews are kept for the tiles on screen only, not for the 10,000 notes.")
    }

    /// The same folder of 10,000 notes in a vault of only those, scrolled once the index has read them all: what the
    /// tiles cost by themselves, to tell their share of a late frame from the index's reading of a large vault.
    func testScrollingAFolderOfTenThousandNotesOnceTheIndexIsDone() async throws {
        _ = try await scroll("Ten thousand", inAVaultOf: [("Ten thousand", 10_000)], afterTheIndexScan: true)
    }

    /// Writes the vault, shows its library, opens `shownFolder` (after the index has read the vault, when asked) and scrolls it
    /// down and back, printing what was measured.
    private func scroll(_ shownFolder: String, inAVaultOf folders: [(name: String, noteCount: Int)],
                        afterTheIndexScan waitsForTheScan: Bool = false) async throws -> LibraryModel {
        let vault = try TemporaryVault.make(prefix: "LibraryLargeVault", for: self).root
        let writing = ContinuousClock.now
        try await Task.detached(priority: .userInitiated) { try Self.writeNotes(folders, in: vault) }.value
        let noteCount = folders.reduce(0) { total, folder in total + folder.noteCount }
        let shownNoteCount = try XCTUnwrap(folders.first { folder in folder.name == shownFolder }).noteCount
        print("LibraryLargeVaultScrollingHostedTests wrote \(noteCount) notes in \(ContinuousClock.now - writing)")

        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .library
        try await workspace.openFolderAsVault(vault)
        let library = LibraryModel()
        let libraryView = LibraryView(library: library, vault: workspace.libraryVault,
                                      actions: workspace.libraryActions(openFile: { _ in }, requestCreation: { _, _ in }),
                                      entries: workspace.libraryEntryPresentation { _, _ in })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let controller = try host(libraryView, size: scene.effectiveGeometry.coordinateSpace.bounds.size, horizontalSizeClass: .regular)
        // The view's own reload gives the library its vault; a folder shown before that would be listed from nothing.
        try await waitUntil("the vault's root is listed", timeoutSeconds: 60) { library.hasListedFolder && library.items.count == folders.count }
        if waitsForTheScan { try await waitUntil("the index has read the vault", timeoutSeconds: 300) { workspace.hasCompletedIndexScan } }
        let footprintBefore = Self.footprintMegabytes()

        let opening = ContinuousClock.now
        await library.show(try VaultPath(shownFolder))
        try await waitUntil("the folder is listed", timeoutSeconds: 60) { library.items.count == shownNoteCount }
        var grid: UIScrollView?
        try await waitUntil("the folder's grid is laid out", timeoutSeconds: 60) {
            grid = self.scrollViews(in: controller.view).max { first, second in first.contentSize.height < second.contentSize.height }
            return (grid?.contentSize.height ?? 0) > (grid?.bounds.height ?? 1) * 3
        }
        print("LibraryLargeVaultScrollingHostedTests the folder of \(shownNoteCount) notes listed and laid out in \(ContinuousClock.now - opening)")
        let scrolledGrid = try XCTUnwrap(grid)
        try await waitUntil("the first tiles' previews are drawn", timeoutSeconds: 30) { library.visiblePreviews.count >= 10 }
        attachWhatIsOnScreen(in: controller, named: "The folder of \(shownNoteCount) notes")

        let (gaps, mainThreadWork) = await FrameGapRecorder(scrollView: scrolledGrid, step: Self.step, framesEachWay: Self.framesEachWay).run()
        let footprintAfter = Self.footprintMegabytes()
        let late = gaps.filter { gap in gap > 0.0177 }.count, dropped = gaps.filter { gap in gap > 0.025 }.count
        let overHalfARefresh = mainThreadWork.filter { work in work > 0.0083 }.count
        print("LibraryLargeVaultScrollingHostedTests \(shownNoteCount) of \(noteCount) notes, \(gaps.count) frames: gaps \(Self.describe(gaps)), "
              + "\(late) over 17.7 ms, \(dropped) over 25 ms; the main thread's work in a frame \(Self.describe(mainThreadWork)), "
              + "\(overHalfARefresh) over 8.3 ms; memory \(footprintBefore) MB before opening the folder, \(footprintAfter) MB after the scroll; "
              + "\(library.visiblePreviews.count) previews kept for the tiles shown; index scan finished: \(workspace.hasCompletedIndexScan)")
        attachWhatIsOnScreen(in: controller, named: "After the scroll")
        XCTAssertEqual(gaps.count, Self.framesEachWay * 2, "Every frame of the scroll was measured.")
        return library
    }

    /// Median, 95th percentile and longest, in milliseconds.
    private static func describe(_ durations: [CFTimeInterval]) -> String {
        let sorted = durations.sorted()
        guard !sorted.isEmpty else { return "none" }
        let milliseconds = { (duration: CFTimeInterval) in String(format: "%.1f ms", duration * 1_000) }
        return "median \(milliseconds(sorted[sorted.count / 2])), 95th percentile \(milliseconds(sorted[sorted.count * 95 / 100])), "
            + "longest \(milliseconds(sorted[sorted.count - 1]))"
    }

    /// Each folder's notes, each a heading and a line.
    private nonisolated static func writeNotes(_ folders: [(name: String, noteCount: Int)], in vault: URL) throws {
        for (folderName, noteCount) in folders {
            let folder = vault.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for noteNumber in 0..<noteCount {
                let text = "# Made-up note \(noteNumber)\n\nA line of a large made-up vault.\n"
                try Data(text.utf8).write(to: folder.appendingPathComponent(String(format: "Made-up note %05d.md", noteNumber)))
            }
        }
    }

    /// The app's memory as the system counts it against the app (`phys_footprint`), in megabytes.
    private static func footprintMegabytes() -> Int {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(information.phys_footprint / 1_048_576) : -1
    }
}

/// Scrolls a scroll view by a display link, `step` points a frame down for `framesEachWay` frames and back, staying
/// between its top and its end, and records the gap before each frame and the main thread's work in it.
@MainActor
private final class FrameGapRecorder: NSObject {
    private let scrollView: UIScrollView
    private let step: CGFloat
    private let framesEachWay: Int
    private let awakeTime = MainThreadAwakeTime()
    private var observer: CFRunLoopObserver?
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var gaps: [CFTimeInterval] = []
    private var mainThreadWork: [CFTimeInterval] = []
    private var continuation: CheckedContinuation<([CFTimeInterval], [CFTimeInterval]), Never>?

    init(scrollView: UIScrollView, step: CGFloat, framesEachWay: Int) {
        self.scrollView = scrollView
        self.step = step
        self.framesEachWay = framesEachWay
    }

    /// The gap before each frame and the main thread's time awake since the frame before, in seconds.
    func run() async -> ([CFTimeInterval], [CFTimeInterval]) {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let awakeTime = self.awakeTime
            let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
            let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in awakeTime.note(activity) }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
            _ = awakeTime.take()
            let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let work = awakeTime.take()
        if let previousTimestamp {
            gaps.append(link.timestamp - previousTimestamp)
            mainThreadWork.append(work)
        }
        previousTimestamp = link.timestamp
        guard gaps.count < framesEachWay * 2 else {
            link.invalidate()
            displayLink = nil
            if let observer { CFRunLoopObserverInvalidate(observer) }
            observer = nil
            continuation?.resume(returning: (gaps, mainThreadWork))
            continuation = nil
            return
        }
        let isGoingBack = gaps.count >= framesEachWay
        let top = -scrollView.adjustedContentInset.top
        let bottom = max(top, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
        scrollView.contentOffset.y = min(bottom, max(top, scrollView.contentOffset.y + (isGoingBack ? -step : step)))
    }
}

/// The main thread's time awake in its run loop, from waking to going back to wait, added up until it is taken. The run
/// loop's observer reports on the main thread; the lock keeps the type free of any actor.
private final class MainThreadAwakeTime: Sendable {
    private struct Times {
        var wokeAt: CFTimeInterval?
        var awake: CFTimeInterval = 0
    }

    private let times = Mutex(Times(wokeAt: CACurrentMediaTime()))

    func note(_ activity: CFRunLoopActivity) {
        let now = CACurrentMediaTime()
        times.withLock { times in
            if activity == .afterWaiting {
                times.wokeAt = now
            } else if let wokeAt = times.wokeAt {
                times.awake += now - wokeAt
                times.wokeAt = nil
            }
        }
    }

    /// The time awake since the last take, counting the stretch the main thread is in now up to this moment.
    func take() -> CFTimeInterval {
        let now = CACurrentMediaTime()
        return times.withLock { times in
            let taken = times.awake + (times.wokeAt.map { wokeAt in now - wokeAt } ?? 0)
            times.awake = 0
            if times.wokeAt != nil { times.wokeAt = now }
            return taken
        }
    }
}
#endif
