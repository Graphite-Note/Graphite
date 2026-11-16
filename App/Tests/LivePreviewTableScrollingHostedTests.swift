/**
 * File: LivePreviewTableScrollingHostedTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: On the iPad, scrolling a Live Preview note of 50 editable tables keeps its frame budget: the tables'
 *              editing layers and their "+" strips, which show only while a cell is edited or the pointer is over a
 *              table, add no work to a scroll.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The hosted workspace's own Live Preview of a note of 50 tables, scrolled down and back by a
/// display link as a fast finger scrolls, each frame's gap recorded.
@MainActor
final class LivePreviewTableScrollingHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    /// 50 sections, each a heading, a line of text and a table of a header and five rows.
    private static let note: String = (1...50).map { tableNumber in
        let rows = (1...5).map { rowNumber in "| Stage \(rowNumber) | \(Double(tableNumber * rowNumber) / 10) | **V** | load \(rowNumber * 2) |" }
        return "## Table \(tableNumber)\n\nThe values measured for circuit \(tableNumber).\n\n| Stage | Value | Unit | Note |\n| --- | ---: | :---: | --- |\n"
            + rows.joined(separator: "\n") + "\n"
    }.joined(separator: "\n")

    /// A fast scroll through the 50 tables, down to the end and back, keeps its median frame and
    /// at most one frame in six over 33 ms, and no frame freezes for 300 ms. Measured 2026-11-12
    /// on the iPad simulator with the strips and with them taken out of the tables' editing layer
    /// (Docs/Table-editing-todo.md, section 1): alone, the longest frame was 50 to 57 ms either
    /// way; within the full hosted suite one frame took 169 ms, so the longest frame alone is
    /// not a budget that holds under the suite's load.
    func testScrollingANoteOfFiftyTablesKeepsItsFrameBudget() async throws {
        try TimingBudgets.requireTheOwnersDevice()
        let textView = try await openNote(Self.note)
        try await waitUntil("the first tables are drawn") { self.blockViews(in: textView).count >= 2 }
        let measurement = ScrollFrameMeasurement(scrollView: textView, step: 45) { view in self.isViewOfHostingController(view) }
        let gaps = await measurement.run()
        XCTAssertGreaterThan(gaps.count, 100, "The scroll went through the note.")
        let sorted = gaps.sorted()
        let medianMilliseconds = sorted[sorted.count / 2] * 1_000
        let longestMilliseconds = (sorted.last ?? 0) * 1_000
        let slowFrameCount = gaps.filter { gap in gap > 1.0 / 30 }.count
        let report = "\(gaps.count) frames, median \(String(format: "%.1f", medianMilliseconds)) ms, longest \(Int(longestMilliseconds)) ms, " +
            "\(slowFrameCount) over 33 ms, \(measurement.tableViewsSeen) table views drawn"
        print("LivePreviewTableScrollingHostedTests timing: " + report)
        XCTAssertGreaterThanOrEqual(measurement.tableViewsSeen, 10, "Tables were drawn on the way: \(report).")
        XCTAssertLessThan(medianMilliseconds, 20, "Median frame while scrolling 50 tables: \(report).")
        XCTAssertLessThan(slowFrameCount * 6, gaps.count, "Frames over 33 ms while scrolling 50 tables: \(report).")
        XCTAssertLessThan(longestMilliseconds, 300, "Longest frame gap while scrolling 50 tables: \(report).")
    }

    // MARK: Finding things

    private func blockViews(in textView: UIView) -> [UIView] {
        textView.subviews.filter { subview in !subview.isHidden && isViewOfHostingController(subview) }
    }

    private func isViewOfHostingController(_ view: UIView) -> Bool {
        var responder = view.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if currentResponder is UIHostingController<AnyView> { return true }
            responder = currentResponder.next
        }
        return false
    }

    // MARK: Hosting

    private func openNote(_ text: String) async throws -> MarkdownTextView {
        let directory = try TemporaryVault.make(prefix: "TableScrolling", for: self).root
        try Data(text.utf8).write(to: directory.appendingPathComponent("Tables.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Tables.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        var editor: MarkdownTextView?
        try await waitUntil("the note is shown") {
            editor = self.descendants(of: controller.view, matching: MarkdownTextView.self).first { editor in
                editor.window != nil && editor.text == session.text && editor.bounds.width > 0
            }
            return editor != nil
        }
        return try XCTUnwrap(editor)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}

/// Scrolls a scroll view by `step` points each frame, down to its end and back to its top,
/// as a fast finger does, recording the gap before each frame and how many table views were
/// placed in it on the way.
@MainActor
private final class ScrollFrameMeasurement: NSObject {
    private let scrollView: UIScrollView
    private let step: CGFloat
    private let isBlockView: (UIView) -> Bool
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var gaps: [CFTimeInterval] = []
    private var isGoingBack = false
    private var seenTableViews: Set<ObjectIdentifier> = []
    private var continuation: CheckedContinuation<[CFTimeInterval], Never>?

    /// How many different rendered blocks' views were shown during the scroll.
    var tableViewsSeen: Int { seenTableViews.count }

    init(scrollView: UIScrollView, step: CGFloat, isBlockView: @escaping (UIView) -> Bool) {
        self.scrollView = scrollView
        self.step = step
        self.isBlockView = isBlockView
    }

    func run() async -> [CFTimeInterval] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        if let previousTimestamp { gaps.append(now - previousTimestamp) }
        previousTimestamp = now
        for subview in scrollView.subviews where !subview.isHidden && isBlockView(subview) {
            seenTableViews.insert(ObjectIdentifier(subview))
        }
        let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let next = scrollView.contentOffset.y + (isGoingBack ? -step : step)
        if !isGoingBack, next >= maximumOffset {
            isGoingBack = true
            scrollView.contentOffset.y = maximumOffset
        } else if isGoingBack, next <= 0 {
            scrollView.contentOffset.y = 0
            link.invalidate()
            displayLink = nil
            continuation?.resume(returning: gaps)
            continuation = nil
        } else {
            scrollView.contentOffset.y = next
        }
    }
}
#endif
