/**
 * File: DiagramNoteScrollingHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Scrolling a note of 35 mermaid diagrams of 32 types, in the reading view and in Live Preview, on the iPad
 *              and the iPhone, each frame's gap and the main thread's work in it measured, and what the main thread spent
 *              the late frames in sampled every millisecond.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */
// arm64 only, as the main thread's sampler reads arm64 registers (MainThreadSampler).
#if os(iOS) && arch(arm64)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI

/// The hosted workspace's own reading view and Live Preview of a note full of diagrams (Docs/Native-diagrams-todo.md,
/// Speed: "scrolling a note full of diagrams with no dropped frames"), scrolled down to its end and back by a display link
/// as a quick finger scrolls, 30 points a frame.
@MainActor
final class DiagramNoteScrollingHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    /// Points scrolled each frame: 1,800 points a second at 60 frames a second, a quick flick's speed.
    private static let step: CGFloat = 30

    /// Every diagram of the note is read and laid out, so the scroll measures diagrams drawn, not their source shown.
    func testEveryDiagramOfTheNoteIsDrawn() {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
        var kinds: Set<String> = []
        for diagram in DiagramScrollingNote.diagrams {
            guard case .drawn(let prepared, _) = ReadingDiagram(source: diagram.source, typography: typography) else {
                XCTFail("\(diagram.title) is drawn"); continue
            }
            kinds.insert("\(prepared.kind)")
        }
        XCTAssertEqual(DiagramScrollingNote.diagrams.count, 35)
        XCTAssertEqual(kinds.count, 32, "Every type but the info diagram: \(kinds.sorted()).")
    }

    func testScrollingTheReadingViewOfANoteFullOfDiagrams() async throws {
        let measured = try await scroll(DiagramScrollingNote.text, in: .reading)
        report(measured, view: "reading view")
        XCTAssertGreaterThan(measured.gaps.count, 100, "The scroll went through the note: \(measured.summary).")
        try TimingBudgets.requireTheOwnersDevice()
        XCTAssertLessThan(measured.medianMilliseconds, 20, "Median frame scrolling the reading view: \(measured.summary).")
        XCTAssertLessThan(measured.longestMilliseconds, 300, "Longest frame scrolling the reading view: \(measured.summary).")
    }

    /// The same note with each diagram's fence a plain code block: what scrolling its headings, text and code costs
    /// without a diagram, to tell the diagrams' share of a late frame from the rest of the reading view's.
    func testScrollingTheReadingViewOfTheSameNoteWithItsDiagramsAsCode() async throws {
        let measured = try await scroll(DiagramScrollingNote.text.replacingOccurrences(of: "```mermaid", with: "```text"), in: .reading)
        report(measured, view: "reading view without diagrams")
        XCTAssertGreaterThan(measured.gaps.count, 100, "The scroll went through the note: \(measured.summary).")
    }

    func testScrollingLivePreviewOfANoteFullOfDiagrams() async throws {
        let measured = try await scroll(DiagramScrollingNote.text, in: .livePreview)
        report(measured, view: "Live Preview")
        XCTAssertGreaterThan(measured.gaps.count, 100, "The scroll went through the note: \(measured.summary).")
        try TimingBudgets.requireTheOwnersDevice()
        XCTAssertLessThan(measured.medianMilliseconds, 20, "Median frame scrolling Live Preview: \(measured.summary).")
        XCTAssertLessThan(measured.longestMilliseconds, 300, "Longest frame scrolling Live Preview: \(measured.summary).")
    }

    // MARK: Measuring

    private func report(_ measured: DiagramScrollMeasurement.Result, view: String) {
        print("DiagramNoteScrollingHostedTests \(view) on \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"): " + measured.summary)
        print("DiagramNoteScrollingHostedTests \(view) late frames: " + measured.lateFrames)
        print("DiagramNoteScrollingHostedTests \(view) work in the late frames, " + measured.lateFrameWork)
    }

    /// Opens the note in `mode`, waits for its first diagrams to be drawn and a second more, then scrolls it down and back.
    private func scroll(_ text: String, in mode: NoteViewMode) async throws -> DiagramScrollMeasurement.Result {
        let root = try await openNote(text, in: mode)
        try await settle(root, seconds: 3)
        let scroller = try XCTUnwrap(ReleaseVaultScrolling.pageScroller(in: root))
        XCTAssertGreaterThan(scroller.contentSize.height, scroller.bounds.height * 3, "The note is several screens long in the \(mode).")
        attachPicture(of: root, named: "\(mode) at the top")
        let measurement = DiagramScrollMeasurement(scrollView: scroller, step: Self.step)
        let measured = await measurement.run()
        attachPicture(of: root, named: "\(mode) back at the top")
        return measured
    }

    private func attachPicture(of view: UIView, named name: String) {
        let picture = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle(_ root: UIView, seconds: Double) async throws {
        let end = Date.now.addingTimeInterval(seconds)
        try await waitUntil("the window settled") {
            root.layoutIfNeeded()
            return Date.now >= end
        }
    }

    // MARK: Hosting

    private func openNote(_ text: String, in mode: NoteViewMode) async throws -> UIView {
        let directory = try TemporaryVault.make(prefix: "DiagramScrolling", for: self).root
        try Data(text.utf8).write(to: directory.appendingPathComponent("Diagrams.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Diagrams.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = mode
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        let root: UIView = controller.view
        if mode == .reading {
            try await waitUntil("the reading view laid out its blocks") { session.readingPosition.hasLaidOutBlocks }
        } else {
            try await waitUntil("the note's editor is shown") { ReleaseVaultViews.noteTextView(in: root) != nil }
        }
        return root
    }
}

/// Scrolls a scroll view by `step` points each frame, down to its end and back to its top, recording the gap before each
/// frame, where the view was then, the main thread's work in it, and what the main thread spent the late frames in
/// (`MainThreadSampler`).
@MainActor
private final class DiagramScrollMeasurement: NSObject {
    struct Result {
        let gaps: [CFTimeInterval]
        /// How long the main thread worked in each gap, between waking and going back to wait in its run loop: a gap
        /// that is late although the main thread worked less than a refresh was lost elsewhere (the render server, the
        /// Mac's load), not to Graphite's work.
        let mainThreadWork: [CFTimeInterval]
        /// The offset the frame before each gap left the view at, and which way the scroll was going.
        let offsets: [(offset: CGFloat, goingBack: Bool)]
        /// The functions the main thread was in during the frames over 17.7 ms (`MainThreadSampler`).
        let lateFrameWork: String

        var medianMilliseconds: Double { percentileMilliseconds(0.5) }
        var longestMilliseconds: Double { (gaps.max() ?? 0) * 1_000 }

        func percentileMilliseconds(_ share: Double) -> Double {
            let sorted = gaps.sorted()
            guard !sorted.isEmpty else { return 0 }
            return sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))] * 1_000
        }

        /// Frames over one refresh at 60 Hz, with a millisecond for the display link's own jitter, and those that took
        /// the time of two refreshes or more (a refresh dropped).
        var overOneRefresh: Int { gaps.filter { gap in gap > 0.0177 }.count }
        var droppedRefreshes: Int { gaps.filter { gap in gap > 0.025 }.count }
        /// Late frames in which the main thread worked more than a refresh.
        var lateWithMainThreadWork: Int { zip(gaps, mainThreadWork).filter { gap, work in gap > 0.0177 && work > 0.0167 }.count }
        var longestMainThreadWorkMilliseconds: Double { (mainThreadWork.max() ?? 0) * 1_000 }

        var summary: String {
            "\(gaps.count) frames, median \(String(format: "%.1f", medianMilliseconds)) ms, 95th percentile "
                + "\(String(format: "%.1f", percentileMilliseconds(0.95))) ms, 99th \(String(format: "%.1f", percentileMilliseconds(0.99))) ms, "
                + "longest \(String(format: "%.1f", longestMilliseconds)) ms, \(overOneRefresh) over 17.7 ms, \(droppedRefreshes) over 25 ms, "
                + "\(lateWithMainThreadWork) late with the main thread working over 16.7 ms, its longest work in a frame "
                + "\(String(format: "%.1f", longestMainThreadWorkMilliseconds)) ms"
        }

        /// Each frame over 17.7 ms: its length, the main thread's work in it and where the view was.
        var lateFrames: String {
            gaps.indices.filter { index in gaps[index] > 0.0177 }.map { index in
                "\(String(format: "%.1f", gaps[index] * 1_000)) ms (main thread \(String(format: "%.1f", mainThreadWork[index] * 1_000)) ms) "
                    + "at \(Int(offsets[index].offset))\(offsets[index].goingBack ? " up" : " down")"
            }.joined(separator: ", ")
        }
    }

    private let scrollView: UIScrollView
    private let step: CGFloat
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var gaps: [CFTimeInterval] = []
    private var offsets: [(offset: CGFloat, goingBack: Bool)] = []
    private var mainThreadWork: [CFTimeInterval] = []
    private let workClock = MainThreadWorkClock()
    private var isGoingBack = false
    private var sampler: MainThreadSampler?
    /// When each frame's callback ran, on `CACurrentMediaTime`'s clock, for the stretches the sampler is asked about.
    private var callbackTimes: [CFTimeInterval] = []
    private var continuation: CheckedContinuation<Result, Never>?

    init(scrollView: UIScrollView, step: CGFloat) {
        self.scrollView = scrollView
        self.step = step
    }

    func run() async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            sampler = MainThreadSampler()
            workClock.start()
            let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        let work = workClock.takeWork()
        callbackTimes.append(CACurrentMediaTime())
        if let previousTimestamp {
            gaps.append(now - previousTimestamp)
            mainThreadWork.append(work)
            offsets.append((scrollView.contentOffset.y, isGoingBack))
        }
        previousTimestamp = now
        let top = -scrollView.adjustedContentInset.top
        let maximumOffset = max(top, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
        let next = scrollView.contentOffset.y + (isGoingBack ? -step : step)
        if !isGoingBack, next >= maximumOffset {
            isGoingBack = true
            scrollView.contentOffset.y = maximumOffset
        } else if isGoingBack, next <= top {
            scrollView.contentOffset.y = top
            link.invalidate()
            displayLink = nil
            workClock.stop()
            sampler?.stop()
            // The gap before frame n + 1 ran from callback n to callback n + 1.
            let lateStretches = gaps.indices.filter { index in gaps[index] > 0.0177 }.map { index in callbackTimes[index]...callbackTimes[index + 1] }
            let lateFrameWork = lateStretches.isEmpty ? "no late frame" : sampler?.heaviestFunctions(in: lateStretches) ?? "not sampled"
            continuation?.resume(returning: Result(gaps: gaps, mainThreadWork: mainThreadWork, offsets: offsets, lateFrameWork: lateFrameWork))
            continuation = nil
        } else {
            scrollView.contentOffset.y = next
        }
    }
}
/// The main thread's time awake in its run loop, from waking to going back to wait, added up until it is taken.
@MainActor
private final class MainThreadWorkClock {
    private var observer: CFRunLoopObserver?
    private var wokeAt: CFTimeInterval?
    private var work: CFTimeInterval = 0

    func start() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.note(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
        wokeAt = CACurrentMediaTime()
    }

    func stop() {
        if let observer { CFRunLoopObserverInvalidate(observer) }
        observer = nil
    }

    /// The work since the last time it was taken, counting the stretch the main thread is in now up to this moment.
    func takeWork() -> CFTimeInterval {
        let now = CACurrentMediaTime()
        let taken = work + (wokeAt.map { woke in now - woke } ?? 0)
        work = 0
        if wokeAt != nil { wokeAt = now }
        return taken
    }

    private func note(_ activity: CFRunLoopActivity) {
        let now = CACurrentMediaTime()
        if activity == .afterWaiting {
            wokeAt = now
        } else if let woke = wokeAt {
            work += now - woke
            wokeAt = nil
        }
    }
}
#endif
