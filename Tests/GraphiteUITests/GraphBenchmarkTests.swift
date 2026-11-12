/**
 * File: GraphBenchmarkTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Time and main-thread cost of the whole-vault graph on made-up vaults of 4,700 and 100,000 notes,
 *              with tags on and off: reading the graph, the first drawing, settling, pinching, panning and
 *              dragging a node.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */
import XCTest
import SwiftUI
@testable import GraphiteCore
import GraphiteIndex
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif
@testable import GraphiteUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The whole-vault graph on made-up vaults the size of the owner's (4,700 notes) and of a very
/// large one (100,000), with tags on and off, as `Docs/Graph-view-todo.md` section 4 asks:
/// the time from asking for the graph to its first drawing, the time from there to a settled
/// layout, and the cost of each frame meanwhile and while pinching, panning and dragging a
/// node. The graph is drawn by `GraphCanvasRenderer` and laid out by `GraphCanvasModel`, as
/// `GraphCanvas` does, in a window of the iPad Pro 11-inch's size.
///
/// They are benchmarks of `PerformanceBenchmarkTests` and run only when asked for, as those do:
/// `GRAPHITE_BENCHMARKS=1 swift test -c release -Xswiftc -enable-testing --filter "PerformanceBenchmarkTests/testTheGraph"`
/// on the Mac, and `TEST_RUNNER_GRAPHITE_BENCHMARKS=1` with
/// `-only-testing:GraphiteIntegrationTests/PerformanceBenchmarkTests/testTheGraphOfAVaultOfTheOwnersSizeWithTags`
/// (and the three others) for the iPad. Each prints `GRAPHITE-BENCH` lines; a frame's cost is measured as there.
extension PerformanceBenchmarkTests {
    private static let graphWindowSize = CGSize(width: 834, height: 1210)
    /// How long a layout may take to settle before the run says it did not.
    private static let graphSettlingLimit = Duration.seconds(120)
    private static let graphGestureFrameCount = 60

    // MARK: The owner's size

    func testTheGraphOfAVaultOfTheOwnersSizeWithTags() async throws {
        try await measureGraph(of: indexedVault(noteCount: 4_700), showsTags: true, runCount: 3)
    }

    func testTheGraphOfAVaultOfTheOwnersSizeWithoutTags() async throws {
        try await measureGraph(of: indexedVault(noteCount: 4_700), showsTags: false, runCount: 3)
    }

    // MARK: A very large vault

    /// The 100,000 notes' graph is made as the index would make it, without indexing them,
    /// which takes minutes; reading the graph from an index of this size is timed by
    /// `GraphiteBenchmarks 100000` (`Sources/GraphiteBenchmarks`).
    func testTheGraphOfAVeryLargeVaultWithTags() async throws {
        try await measureGraph(of: .inMemory(GeneratedCourseVault(noteCount: 100_000).linkGraph), showsTags: true, runCount: 1)
    }

    func testTheGraphOfAVeryLargeVaultWithoutTags() async throws {
        try await measureGraph(of: .inMemory(GeneratedCourseVault(noteCount: 100_000).linkGraph), showsTags: false, runCount: 1)
    }

    // MARK: Measuring

    /// Where a run's graph comes from: an index of the notes, read as the graph view reads it,
    /// or a graph already made.
    private enum GraphSource {
        case index(VaultIndex, noteCount: Int)
        case inMemory(LinkGraph)

        var noteCount: Int {
            switch self {
            case .index(_, let noteCount): noteCount
            case .inMemory(let graph): graph.counts.notes
            }
        }

        func vaultGraph() async throws -> LinkGraph {
            switch self {
            case .index(let index, _): try await index.linkGraph()
            case .inMemory(let graph): graph
            }
        }
    }

    private func indexedVault(noteCount: Int) async throws -> GraphSource {
        let directory = try TemporaryVault.make(prefix: "GraphBenchmark", for: self).root
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let vault = GeneratedCourseVault(noteCount: noteCount)
        for batchStart in stride(from: 0, to: vault.notes.count, by: 500) {
            let batch = vault.notes[batchStart..<min(batchStart + 500, vault.notes.count)].map { note in
                IndexedFile(path: note.path, size: note.markdown.utf8.count, modified: .now, markdown: note.markdown)
            }
            try await index.update(batch, generation: "graph-benchmark")
        }
        return .index(index, noteCount: noteCount)
    }

    private func measureGraph(of source: GraphSource, showsTags: Bool, runCount: Int) async throws {
        let label = "\(source.noteCount)-notes-tags-\(showsTags ? "on" : "off")"
        let filters = GraphFilterOptions(showsTags: showsTags)
        for run in 1...runCount {
            let stage = GraphBenchmarkStage()
            let window = try hostGraph(GraphBenchmarkCanvas(stage: stage))
            defer { closeGraph(window) }
            // The main thread's frames from the request to the first drawing, measured by a
            // timer beside the work, as the work itself runs in tasks.
            let firstDrawing = BenchmarkMeasurement(scenario: "graph-first-drawing-\(label)", run: run)
            let watch = MainThreadFrameWatch(measurement: firstDrawing)
            let requested = ContinuousClock.now
            let reading = BenchmarkMeasurement(scenario: "graph-read-\(label)", run: run)
            let vaultGraph = try await source.vaultGraph()
            let shownGraph = vaultGraph.filtered(by: filters)
            reading.finish()
            await stage.model.load(shownGraph, forces: GraphLayout.Forces(), previousPositions: [:], groupIndexByIdentifier: [:])
            try await waitUntil("the first drawing", timeoutSeconds: 60, pollingIntervalSeconds: 0.002) {
                self.layOutGraph(window)
                return stage.firstDrawingTime != nil
            }
            await watch.stop()
            firstDrawing.finish()
            let drawn = try XCTUnwrap(stage.firstDrawingTime)
            print("GRAPHITE-BENCH platform=\(PerformanceBenchmarkTests.platformNameForMeasurement) scenario=graph-first-drawing-time-\(label) run=\(run)"
                  + " nodes=\(shownGraph.nodes.count) edges=\(shownGraph.edges.count) " + String(format: "first_drawing_ms=%.0f", Self.graphMilliseconds(requested.duration(to: drawn))))

            let settling = BenchmarkMeasurement(scenario: "graph-settle-\(label)", run: run)
            let settlingDeadline = ContinuousClock.now + Self.graphSettlingLimit
            while !stage.model.isSettled, ContinuousClock.now < settlingDeadline {
                await settling.measureFrame { layOutGraph(window) }
            }
            settling.finish()
            print("GRAPHITE-BENCH platform=\(PerformanceBenchmarkTests.platformNameForMeasurement) scenario=graph-settled-time-\(label) run=\(run)"
                  + " settled=\(stage.model.isSettled) " + String(format: "settled_after_first_drawing_ms=%.0f", Self.graphMilliseconds(drawn.duration(to: .now))))

            let size = Self.graphWindowSize
            // A gesture stops the fit, as in `GraphCanvas`.
            stage.followsTheWholeGraph = false
            let pinching = BenchmarkMeasurement(scenario: "graph-pinch-\(label)", run: run)
            for _ in 0..<Self.graphGestureFrameCount {
                await pinching.measureFrame {
                    stage.viewport.zoom(to: stage.viewport.scale * 1.04, keepingInPlace: CGPoint(x: size.width / 2, y: size.height / 2), in: size)
                    layOutGraph(window)
                }
            }
            pinching.finish()
            let panning = BenchmarkMeasurement(scenario: "graph-pan-\(label)", run: run)
            for _ in 0..<Self.graphGestureFrameCount {
                await panning.measureFrame {
                    stage.viewport.move(by: SIMD2(6, 4))
                    layOutGraph(window)
                }
            }
            panning.finish()
            try await measureDragging(in: stage, window: window, label: label, run: run)
            stage.model.stop()
        }
    }

    /// Drags the best-linked note across the view, a frame at a time, as a finger does: the
    /// node is pinned where the finger is and the layout wakes around it.
    private func measureDragging(in stage: GraphBenchmarkStage, window: GraphBenchmarkWindow, label: String, run: Int) async throws {
        let graph = stage.model.graph
        let linkCounts = graph.linkCounts
        let dragged = try XCTUnwrap(graph.nodes.max { first, second in (linkCounts[first.id] ?? 0) < (linkCounts[second.id] ?? 0) })
        let start = try XCTUnwrap(stage.model.index(of: dragged.id).map { index in stage.model.positions[index] })
        let dragging = BenchmarkMeasurement(scenario: "graph-drag-\(label)", run: run)
        for frame in 0..<Self.graphGestureFrameCount {
            await dragging.measureFrame {
                stage.model.pin(dragged.id, at: start + SIMD2(Double(frame) * 3, Double(frame) * 2))
                layOutGraph(window)
            }
        }
        stage.model.unpin(dragged.id)
        dragging.finish()
    }

    private static func graphMilliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    // MARK: Platform

    #if canImport(UIKit)
    typealias GraphBenchmarkWindow = UIWindow

    private func hostGraph(_ view: some View) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.graphWindowSize)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        return window
    }

    private func closeGraph(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func layOutGraph(_ window: UIWindow) { window.layoutIfNeeded() }
    #else
    typealias GraphBenchmarkWindow = NSWindow

    private func hostGraph(_ view: some View) throws -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.graphWindowSize), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: AnyView(view))
        layOutGraph(window)
        return window
    }

    private func closeGraph(_ window: NSWindow) {
        window.contentView = nil
        window.close()
    }

    private func layOutGraph(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
    #endif
}

/// Measures the main thread's frames while work runs in tasks beside it: a 16 ms timer on the
/// main actor, each frame as late as the main thread was busy.
@MainActor
final class MainThreadFrameWatch {
    private var isStopped = false
    private var watching: Task<Void, Never>?

    init(measurement: BenchmarkMeasurement) {
        watching = Task { @MainActor [weak self] in
            while self?.isStopped == false { await measurement.measureFrame {} }
        }
    }

    func stop() async {
        isStopped = true
        await watching?.value
    }
}

/// What the benchmark's canvas draws: the graph's model, as `GraphCanvas` keeps it, and the
/// viewport the benchmark moves as a pinch or a pan would.
@MainActor @Observable
final class GraphBenchmarkStage {
    let model = GraphCanvasModel()
    var viewport = GraphViewport()
    /// Whether the view still fits the whole graph, as `GraphCanvas` does until a gesture.
    @ObservationIgnored var followsTheWholeGraph = true
    @ObservationIgnored private(set) var firstDrawingTime: ContinuousClock.Instant?

    func recordDrawing() {
        if firstDrawingTime == nil, !model.positions.isEmpty { firstDrawingTime = .now }
    }
}

/// The graph drawn as `GraphCanvas` draws it, by the same renderer, fitted as the layout
/// moves until the benchmark pinches or pans.
struct GraphBenchmarkCanvas: View {
    let stage: GraphBenchmarkStage

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let model = stage.model
                let emphasis = GraphEmphasis(focusedIndex: nil, openIndex: model.graph.nodes.isEmpty ? nil : 0, neighborIndexes: model.neighborIndexes)
                let look = GraphCanvasLook(display: GraphDisplayOptions(), palette: GraphPalette(appearance: .light, accent: ThemeColor(red: 0.3, green: 0.4, blue: 0.9)),
                                           accent: .blue, groupColoring: GraphGroupColoring(), showsArrows: false, alwaysShowsNames: false)
                GraphCanvasRenderer(model: model, viewport: stage.viewport, emphasis: emphasis, look: look).draw(in: &context, size: size)
                stage.recordDrawing()
            }
            .onChange(of: stage.model.positions) {
                guard stage.followsTheWholeGraph else { return }
                if let fitted = stage.model.fittingViewport(in: geometry.size, display: GraphDisplayOptions(), alwaysShowsNames: false) {
                    stage.viewport = fitted
                }
            }
        }
    }
}
