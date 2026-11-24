/**
 * File: ReadingTextBlockCostHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: What the main thread spends making the reading view's blocks appear, apart from scrolling: a batch of
 *              headings and paragraphs, or one diagram at a time, shown in a window, the main thread's work from the
 *              change until it is idle.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

/// The cost of one block of the reading view coming on screen, measured apart from scrolling, so the frames a scroll
/// drops (`DiagramNoteScrollingHostedTests`) can be told apart by the work each block brings (Docs/Native-diagrams-todo.md,
/// Speed). Each test prints its numbers; a plain `Text` and the SwiftUI painting of diagrams are measured beside the
/// reading view's own blocks as yardsticks.
@MainActor
final class ReadingTextBlockCostHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    /// Blocks shown at once in each batch: a screen of the reading view holds about this many.
    private static let blocksPerBatch = 24
    private static let batches = 8

    func testMakingTheReadingViewsTextBlocks() async throws {
        let median = try await measureTextBlocks(.reading)
        XCTAssertGreaterThan(median, 0, "The blocks were made.")
    }

    func testMakingPlainTextsAsAYardstick() async throws {
        _ = try await measureTextBlocks(.plainText)
    }

    /// Each diagram of the scrolling note shown alone, prepared beforehand as the reading view's builder prepares it, as
    /// the reading view shows it: its picture (`ReadingDiagramPictures`).
    func testMakingEachDiagramAsTheReadingViewShowsIt() async throws {
        let total = try await measureDiagrams(paintedAsPictures: true)
        XCTAssertGreaterThan(total, 0)
    }

    /// The same diagrams painted as SwiftUI shapes and text, as Live Preview and paper show them.
    func testMakingEachDiagramAsSwiftUIViewsAsAYardstick() async throws {
        _ = try await measureDiagrams(paintedAsPictures: false)
    }

    // MARK: Measuring

    private func show(_ view: some View) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
    }

    /// The median work a block of a batch, in seconds.
    private func measureTextBlocks(_ kind: TextBlockKind) async throws -> CFTimeInterval {
        let model = BlockBatches()
        try show(TextBlockBatchView(model: model, root: try TemporaryVault.make(prefix: "TextBlockCost", for: self).root, kind: kind))
        let clock = MainThreadAwakeClock()
        _ = try await mainThreadWork(clock) {}
        let idle = try await mainThreadWork(clock) {}
        var perBlock: [CFTimeInterval] = []
        for batch in 1...Self.batches {
            let work = try await mainThreadWork(clock) { model.batch = batch }
            perBlock.append((work - idle) / Double(Self.blocksPerBatch))
        }
        let median = perBlock.sorted()[perBlock.count / 2]
        print("ReadingTextBlockCostHostedTests: \(kind) \(Self.blocksPerBatch) blocks a batch, idle \(String(format: "%.2f", idle * 1_000)) ms, per block "
              + perBlock.map { cost in String(format: "%.3f", cost * 1_000) }.joined(separator: ", ") + " ms, median \(String(format: "%.3f", median * 1_000)) ms")
        return median
    }

    /// The work of all diagrams together, in seconds, each shown alone after the one before is gone.
    private func measureDiagrams(paintedAsPictures: Bool) async throws -> CFTimeInterval {
        let model = BlockBatches()
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
        let diagrams = DiagramScrollingNote.diagrams.map { diagram in ReadingDiagram(source: diagram.source, typography: typography) }
        try show(DiagramBatchView(model: model, diagrams: diagrams, root: try TemporaryVault.make(prefix: "DiagramCost", for: self).root,
                                  paintsPictures: paintedAsPictures))
        let clock = MainThreadAwakeClock()
        _ = try await mainThreadWork(clock) {}
        let idle = try await mainThreadWork(clock) {}
        var costs: [String] = []
        var total: CFTimeInterval = 0
        for index in diagrams.indices {
            let work = try await mainThreadWork(clock) { model.batch = index + 1 }
            total += work - idle
            costs.append("\(DiagramScrollingNote.diagrams[index].title) \(String(format: "%.2f", (work - idle) * 1_000)) ms")
        }
        print("ReadingTextBlockCostHostedTests: diagrams \(paintedAsPictures ? "as pictures" : "as SwiftUI views"), idle \(String(format: "%.2f", idle * 1_000)) ms, "
              + "total \(String(format: "%.1f", total * 1_000)) ms: " + costs.joined(separator: "; "))
        return total
    }

    /// The main thread's work from `change` until 400 ms later, when what it showed has long been drawn.
    private func mainThreadWork(_ clock: MainThreadAwakeClock, _ change: () -> Void) async throws -> CFTimeInterval {
        clock.start()
        change()
        let end = Date.now.addingTimeInterval(0.4)
        try await waitUntil("400 ms went by") { Date.now >= end }
        return clock.stop()
    }
}

@MainActor @Observable
private final class BlockBatches {
    var batch = 0
}

private enum TextBlockKind { case reading, plainText }

/// A batch of headings and one-line paragraphs as the diagram note has them, each batch's words its own, so nothing
/// made for one batch is found again for the next.
private struct TextBlockBatchView: View {
    let model: BlockBatches
    let root: URL
    let kind: TextBlockKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<24, id: \.self) { blockIndex in
                block(blockIndex)
            }
        }
        .id(model.batch)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Even blocks are headings, odd ones paragraphs.
    private func markdown(_ blockIndex: Int) -> String {
        let number = model.batch * 100 + blockIndex
        return blockIndex.isMultiple(of: 2) ? "## \(number). Pipeline stages of batch \(model.batch)"
            : "The pipeline stages \(number) as drawn in the lecture of batch \(model.batch)."
    }

    @ViewBuilder private func block(_ blockIndex: Int) -> some View {
        switch kind {
        case .plainText:
            Text(markdown(blockIndex).replacingOccurrences(of: "## ", with: "")).font(blockIndex.isMultiple(of: 2) ? .title2 : .body)
        case .reading:
            ObsidianMarkdownText(markdown: markdown(blockIndex), root: root, textSize: 17, navigate: { _, _ in }, scrollToHeading: { _ in })
        }
    }
}

/// One diagram at a time, the one of the batch's number; none at 0. With pictures, as the reading view gives them.
private struct DiagramBatchView: View {
    let model: BlockBatches
    let diagrams: [ReadingDiagram]
    let root: URL
    let paintsPictures: Bool
    @State private var pictures = ReadingDiagramPictures()

    var body: some View {
        VStack {
            if model.batch > 0 {
                ReadingDiagramView(diagram: diagrams[model.batch - 1], textSize: 17, root: root, navigate: { _, _ in }, scrollToHeading: { _ in })
            }
        }
        .id(model.batch)
        .environment(\.readingDiagramPictures, paintsPictures ? pictures : nil)
        .padding(32)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The main thread's time awake in its run loop between `start` and `stop`.
@MainActor
private final class MainThreadAwakeClock {
    private var observer: CFRunLoopObserver?
    private var wokeAt: CFTimeInterval?
    private var work: CFTimeInterval = 0

    func start() {
        work = 0
        wokeAt = CACurrentMediaTime()
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.note(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func stop() -> CFTimeInterval {
        if let observer { CFRunLoopObserverInvalidate(observer) }
        observer = nil
        return work
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
