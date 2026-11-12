/**
 * File: MermaidDiagramSafetyTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Malformed, oversized and hostile diagram text is refused with a typed error or drawn within bounds, never
 *              a crash: every documentation example cut short and mutated, deep nesting on a small stack, style and size limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidDiagramSafetyTests: XCTestCase {
    /// What became of a text: refused while read, refused while laid out, or laid out at a size.
    private enum Outcome: Equatable {
        case readError(MermaidDiagramReadError)
        case layoutRefused
        case laidOut(CGSize)
    }

    private static func outcome(of source: String, typography: DiagramTypography) -> Outcome {
        let diagram: MermaidDiagram
        do { diagram = try MermaidDiagramReader.read(source, limits: .standard) } catch { return .readError(error) }
        do {
            return .laidOut(try size(of: diagram, typography: typography))
        } catch {
            return .layoutRefused
        }
    }

    private static func size(of diagram: MermaidDiagram, typography: DiagramTypography) throws -> CGSize {
        switch diagram {
        case .flowchart(let flowchart): try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard).size
        case .stateDiagram(let state): try StateDiagramLayoutEngine.layout(state, typography: typography, limits: .standard).size
        case .classDiagram(let classes): try ClassDiagramLayoutEngine.layout(classes, typography: typography, limits: .standard).size
        case .sequence(let sequence): try SequenceLayoutEngine.layout(sequence, typography: typography).size
        case .entityRelationship(let entities): try EntityRelationshipLayoutEngine.layout(entities, typography: typography, limits: .standard).size
        case .mindmap(let mindmap): MindmapLayoutEngine.layout(mindmap, typography: typography).size
        case .timeline(let timeline): TimelineLayoutEngine.layout(timeline, typography: typography).size
        case .pieChart(let chart): PieChartLayoutEngine.layout(chart, typography: typography).size
        case .ganttChart(let chart):
            try GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone, limits: .standard).size
        case .gitGraph(let graph): try GitGraphLayoutEngine.layout(graph, typography: typography).size
        case .userJourney(let journey): UserJourneyLayoutEngine.layout(journey, typography: typography).size
        case .quadrantChart(let chart): QuadrantChartLayoutEngine.layout(chart, typography: typography).size
        case .xyChart(let chart): try XYChartLayoutEngine.layout(chart, typography: typography).size
        case .sankey(let sankey): try SankeyLayoutEngine.layout(sankey, typography: typography).size
        }
    }

    private static func allDocumentationExamples() throws -> [String] {
        try [FlowchartCorpus.documentationExamples(), StateDiagramCorpus.documentationExamples(), ClassDiagramCorpus.documentationExamples(),
             SequenceCorpus.documentationExamples(), EntityRelationshipCorpus.documentationExamples(), MindmapCorpus.documentationExamples(),
             TimelineCorpus.documentationExamples(), PieChartCorpus.documentationExamples(), GanttChartCorpus.documentationExamples(),
             GitGraphCorpus.documentationExamples(), UserJourneyCorpus.documentationExamples(), QuadrantChartCorpus.documentationExamples(),
             XYChartCorpus.documentationExamples(), SankeyCorpus.documentationExamples()].flatMap { examples in examples }
    }

    /// Runs `work` on a thread with the 512 KiB stack of the threads the reading view's builder runs on, so that a
    /// recursion as deep as the text allows would overflow here as it would there.
    private func onSecondaryThreadStack(_ work: @escaping @Sendable () -> Void) {
        let finished = expectation(description: "the work finished")
        let thread = Thread {
            work()
            finished.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [finished], timeout: 600)
    }

    /// Every documentation example of every type, cut short at forty places and changed at twenty random places (a
    /// character removed, a bracket, quotation mark or arrow character added, or a run of text doubled), is either read
    /// and laid out at a finite size or refused with a typed error. About 30,000 texts.
    func testEveryExampleCutShortOrMutatedIsDrawnOrRefusedWithoutACrash() throws {
        let examples = try Self.allDocumentationExamples()
        XCTAssertEqual(examples.count, 332)
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        var generator = SeededGenerator(seed: 0x5EED)
        let insertedBytes = Array("[]{}()|\"'-->:;%`<>#\\".utf8)
        var laidOutCount = 0, refusedCount = 0
        func check(_ text: String) {
            switch Self.outcome(of: text, typography: typography) {
            case .laidOut(let size):
                XCTAssertTrue(size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0, text)
                laidOutCount += 1
            case .readError, .layoutRefused:
                refusedCount += 1
            }
        }
        for example in examples {
            let bytes = Array(example.utf8)
            for cut in stride(from: 1, to: bytes.count, by: max(1, bytes.count / 40)) { check(String(decoding: bytes[..<cut], as: UTF8.self)) }
            for _ in 0..<20 {
                var mutated = bytes
                let position = Int(generator.next() % UInt64(mutated.count))
                switch generator.next() % 3 {
                case 0: mutated.remove(at: position)
                case 1: mutated.insert(insertedBytes[Int(generator.next() % UInt64(insertedBytes.count))], at: position)
                default: mutated.insert(contentsOf: mutated[position...].prefix(30), at: position)
                }
                check(String(decoding: mutated, as: UTF8.self))
            }
        }
        XCTAssertGreaterThan(laidOutCount, 1_000)
        XCTAssertGreaterThan(refusedCount, 1_000)
    }

    /// Groups, composite states and mindmap branches nested as deep as the text limit allows are laid out on a secondary
    /// thread's stack without overflowing it, and their drawings are past the drawing limit, which a reader refuses.
    func testDeepNestingIsLaidOutOnASecondaryThreadStackAndIsPastTheDrawingLimit() {
        onSecondaryThreadStack {
            let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
            let depth = 2_400
            let flowchart = "flowchart TD\n" + (0..<depth).map { level in "subgraph s\(level)\n" }.joined() + "a --> b\n"
                + String(repeating: "end\n", count: depth)
            let states = "stateDiagram-v2\n" + (0..<depth).map { level in "state s\(level) {\n" }.joined() + "a --> b\n"
                + String(repeating: "}\n", count: depth)
            let mindmap = "mindmap\n" + (0..<280).map { level in String(repeating: " ", count: level + 1) + "n\(level)\n" }.joined()
            for source in [flowchart, states, mindmap] {
                XCTAssertLessThanOrEqual(source.utf8.count, MermaidDiagramLimits.standard.maximumSourceBytes)
                guard case .laidOut(let size) = Self.outcome(of: source, typography: typography) else {
                    XCTFail("Laid out: \(source.prefix(40))")
                    continue
                }
                XCTAssertFalse(MermaidDiagramLimits.standard.allowsDrawing(size), "\(size)")
            }
        }
    }

    func testTextPastTheSourceLimitAndDiagramsPastTheCountLimitsAreRefused() throws {
        let long = "flowchart TD\n" + String(repeating: "%% a comment that only takes room\n", count: 2_000)
        XCTAssertThrowsError(try MermaidDiagramReader.read(long, limits: .standard)) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .sourceTooLarge(limitBytes: 50_000))
        }
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 10
        limits.maximumEdgeCount = 10
        let cases: [(String, MermaidDiagramReadError)] = [
            ("flowchart TD\n" + (0..<11).map { node in "n\(node)\n" }.joined(), .tooManyNodes(limit: 10)),
            ("flowchart TD\nA & B & C & D --> E & F & G", .tooManyEdges(limit: 10)),
            ("stateDiagram-v2\n" + (0..<11).map { state in "s\(state)\n" }.joined(), .tooManyNodes(limit: 10)),
            ("pie\n" + (0..<11).map { slice in "\"s\(slice)\" : 1\n" }.joined(), .tooManyNodes(limit: 10)),
            ("mindmap\nroot\n" + (0..<11).map { node in "  n\(node)\n" }.joined(), .tooManyNodes(limit: 10))
        ]
        for (source, expected) in cases {
            XCTAssertThrowsError(try MermaidDiagramReader.read(source, limits: limits), source) { error in
                XCTAssertEqual(error as? MermaidDiagramReadError, expected, source)
            }
        }
    }

    func testTheDrawingLimitAllowsOnlyFiniteSizesWithinItsSide() {
        let limits = MermaidDiagramLimits.standard
        XCTAssertEqual(limits.maximumDrawingSideLength, 20_000)
        XCTAssertTrue(limits.allowsDrawing(CGSize(width: 800, height: 20_000)))
        XCTAssertFalse(limits.allowsDrawing(CGSize(width: 20_001, height: 10)))
        XCTAssertFalse(limits.allowsDrawing(CGSize(width: 10, height: CGFloat.infinity)))
        XCTAssertFalse(limits.allowsDrawing(CGSize(width: CGFloat.nan, height: 10)))
        XCTAssertFalse(limits.allowsDrawing(.zero))
    }

    func testADiagramDeclaringNothingHasNothingToDraw() throws {
        for source in ["flowchart LR", "stateDiagram-v2", "classDiagram", "sequenceDiagram", "erDiagram", "timeline", "pie", "gantt\ndateFormat YYYY",
                       "journey\ntitle Only a title"] {
            XCTAssertTrue(try MermaidDiagramReader.read(source, limits: .standard).hasNothingToDraw, source)
        }
        for source in ["flowchart LR\nA", "gitGraph", "quadrantChart", "pie\n\"a\" : 1", "classDiagram\nnote \"An aside\""] {
            XCTAssertFalse(try MermaidDiagramReader.read(source, limits: .standard).hasNothingToDraw, source)
        }
    }

    /// Only the properties a node's look has room for, with values in bounds, are applied: a line wider than 16 points,
    /// dashes that would draw a line as millions of pieces and every other property are left out and counted.
    func testStylesAreFilteredToBoundedValuesOfTheirKnownProperties() {
        let applied = DiagramElementStyle.reading("fill:#f9f,stroke:#333,stroke-width:4px,stroke-dasharray: 5 5,color:#fff")
        XCTAssertFalse(applied.hasUnappliedDeclaration)
        XCTAssertEqual(applied.style.strokeWidth, 4)
        XCTAssertEqual(applied.style.strokeDashLengths, [5, 5])
        for declarations in ["stroke-width:17px", "stroke-width:1e9", "stroke-dasharray: 0.001 0.001", "stroke-dasharray: 2000 2",
                             "stroke-dasharray: " + Array(repeating: "4", count: 17).joined(separator: " "), "background:url(https://example.com/x.png)",
                             "fill:expression(alert(1))", "font-size:900px"] {
            let read = DiagramElementStyle.reading(declarations)
            XCTAssertTrue(read.hasUnappliedDeclaration, declarations)
            XCTAssertTrue(read.style.isEmpty, declarations)
        }
    }

    /// Text is plain characters: HTML tags in a label are dropped (only `<br>` breaks a line), as Mermaid's sanitizer drops
    /// them, entity codes become their characters and are then never read as markup, and a `click` with a script link is
    /// counted and not applied.
    func testLabelsKeepMarkupAsTextAndClicksAreNotApplied() throws {
        guard case .flowchart(let flowchart) = try MermaidDiagramReader.read(
            "flowchart TD\nA[\"<img src=x onerror=alert(1)>Photo\"] --> B[\"&lt;b&gt;bold&lt;/b&gt;\"]\nclick A \"javascript:alert(1)\"",
            limits: .standard) else {
            return XCTFail("A flowchart")
        }
        XCTAssertEqual(flowchart.nodes[0].label.spokenText, "Photo")
        XCTAssertEqual(flowchart.nodes[1].label.spokenText, "<b>bold</b>", "Decoded once, drawn as its characters.")
        XCTAssertEqual(flowchart.unappliedStatementCount, 1)
    }
}

/// A repeatable sequence of pseudo-random numbers (SplitMix64), so that a failure found by the mutations is found again.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
