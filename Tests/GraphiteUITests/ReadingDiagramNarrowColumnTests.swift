/**
 * File: ReadingDiagramNarrowColumnTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Wide diagrams laid out a second time for a narrow column, turned to run down, and which layout a
 *              column shows; diagrams with nothing to draw or too large to draw shown as their source with why.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingDiagramNarrowColumnTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    /// Every classic shape in a row from left to right, which was 2,245 points wide and unreadable when scaled to an
    /// iPad's column.
    static let fourteenShapesInARow = """
        flowchart LR
          A[Rectangle] --> B(Rounded) --> C([Stadium]) --> D[[Subroutine]] --> E[(Database)] --> F((Circle)) --> G(((Double circle)))
          G --> H>Flag] --> I{Diamond} --> J{{Hexagon}} --> K[/Lean right/] --> L[\\Lean left\\] --> M[/Trapezoid\\] --> N[\\Inverted/]
        """

    func testTheColumnShowsTheNarrowLayoutOnlyWhereTheRegularOneDoesNotFitAndTheNarrowOneIsNarrower() {
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: 600, narrowWidth: 200, columnWidth: 700), .regular, "It fits.")
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: 600, narrowWidth: 200, columnWidth: 400), .narrow)
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: 600, narrowWidth: 500, columnWidth: 300), .narrow, "Scaled down less.")
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: 600, narrowWidth: 600, columnWidth: 300), .regular, "No narrower.")
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: 600, narrowWidth: nil, columnWidth: 300), .regular)
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: 600, narrowWidth: 200, columnWidth: 0), .regular, "Not measured yet.")
    }

    func testTheFourteenShapesInARowAreTurnedToRunDownWithTighterGapsForANarrowColumn() throws {
        guard case .flowchart(let flowchart) = ReadingDiagram(source: Self.fourteenShapesInARow, typography: typography) else {
            return XCTFail("A flowchart is drawn")
        }
        XCTAssertGreaterThan(flowchart.layout.size.width, 2_000)
        let narrow = try XCTUnwrap(flowchart.narrow).layout
        XCTAssertLessThan(narrow.size.width, 360, "It fits an iPhone's column without being scaled down.")
        let centers = narrow.nodes.map(\.frame.midY)
        XCTAssertEqual(centers, centers.sorted(), "The shapes follow each other down.")
        let gaps = zip(narrow.nodes, narrow.nodes.dropFirst()).map { upper, lower in lower.frame.minY - upper.frame.maxY }
        XCTAssertEqual(gaps.min() ?? 0, 32, accuracy: 0.5, "Ranks 32 points apart, tighter than the regular 48.")
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: flowchart.layout.size.width, narrowWidth: narrow.size.width, columnWidth: 700), .narrow)
        XCTAssertEqual(ReadingDiagramVariant.shown(regularWidth: flowchart.layout.size.width, narrowWidth: narrow.size.width, columnWidth: 350), .narrow)
    }

    func testADiagramNarrowerThanTheNarrowestColumnIsLaidOutOnce() {
        guard case .flowchart(let flowchart) = ReadingDiagram(source: "flowchart LR\n  A --> B", typography: typography) else { return XCTFail("Drawn") }
        XCTAssertLessThanOrEqual(flowchart.layout.size.width, ReadingDiagramVariant.narrowestColumnWidth)
        XCTAssertNil(flowchart.narrow)
    }

    func testAWideFlowchartThatRunsDownIsStillTightenedForANarrowColumn() throws {
        let source = "flowchart TD\n  Root --> " + (1...8).map { child in "C\(child)[Child number \(child)]" }.joined(separator: " & ")
        guard case .flowchart(let flowchart) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("Drawn") }
        let narrow = try XCTUnwrap(flowchart.narrow).layout
        XCTAssertLessThan(narrow.size.width, flowchart.layout.size.width)
    }

    func testGitGraphsTimelinesAndGraphsRunningAcrossAreTurnedToRunDown() throws {
        let commits = (1...14).map { commit in "  commit id: \"c\(commit)\"" }.joined(separator: "\n")
        guard case .gitGraph(let gitGraph) = ReadingDiagram(source: "gitGraph\n\(commits)", typography: typography) else { return XCTFail("Git graph") }
        let gitNarrow = try XCTUnwrap(gitGraph.narrow).layout
        XCTAssertLessThan(gitNarrow.size.width, gitGraph.layout.size.width)
        XCTAssertGreaterThan(gitNarrow.size.height, gitNarrow.size.width, "Commits follow each other down.")

        let periods = (2000...2010).map { year in "  \(year) : Event of \(year)" }.joined(separator: "\n")
        guard case .timeline(let timeline) = ReadingDiagram(source: "timeline\n\(periods)", typography: typography) else { return XCTFail("Timeline") }
        XCTAssertLessThan(try XCTUnwrap(timeline.narrow).layout.size.width, timeline.layout.size.width)

        let chain = (1...6).map { state in "S\(state) --> S\(state + 1)" }.joined(separator: "\n")
        guard case .stateDiagram(let states) = ReadingDiagram(source: "stateDiagram-v2\ndirection LR\n\(chain)", typography: typography) else {
            return XCTFail("State diagram")
        }
        XCTAssertLessThan(try XCTUnwrap(states.narrow).layout.size.width, states.layout.size.width)
        guard case .entityRelationship(let entities) = ReadingDiagram(
            source: "erDiagram\ndirection LR\n" + (1...6).map { entity in "E\(entity) ||--o{ E\(entity + 1) : has" }.joined(separator: "\n"),
            typography: typography) else { return XCTFail("Entity relationship diagram") }
        XCTAssertLessThan(try XCTUnwrap(entities.narrow).layout.size.width, entities.layout.size.width)
        guard case .classDiagram(let classes) = ReadingDiagram(
            source: "classDiagram\ndirection LR\n" + (1...6).map { node in "Class\(node) <|-- Class\(node + 1)" }.joined(separator: "\n"),
            typography: typography) else { return XCTFail("Class diagram") }
        XCTAssertLessThan(try XCTUnwrap(classes.narrow).layout.size.width, classes.layout.size.width)
    }

    func testAStateDiagramRunningAcrossIsTurnedWithItsComposites() throws {
        let source = "stateDiagram-v2\ndirection LR\n[*] --> Idle\nIdle --> Working\nstate Working {\n  direction LR\n  Reading --> Writing\n  Writing --> Saving\n}\n"
            + "Working --> Done\nDone --> [*]"
        guard case .stateDiagram(let diagram) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("State diagram") }
        let narrow = try XCTUnwrap(diagram.narrow).layout
        XCTAssertLessThan(narrow.size.width, diagram.layout.size.width)
        XCTAssertEqual(narrow.composites.count, 1)
    }

    func testADiagramWithNothingToDrawOrTooLargeToDrawShowsItsSourceAndWhy() {
        for source in ["flowchart LR", "stateDiagram-v2\n%% only a comment", "pie title Nothing yet", "gantt\n  dateFormat YYYY-MM-DD"] {
            guard case .unreadable(let shown, let failure) = ReadingDiagram(source: source, typography: typography) else {
                XCTFail("Shown with why: \(source)")
                continue
            }
            XCTAssertEqual(shown, source)
            XCTAssertEqual(failure, .nothingToDraw, source)
            XCTAssertEqual(failure.explanation, "This diagram has nothing to draw yet.")
        }
        let longChain = "flowchart LR\n" + (0..<260).map { node in "n\(node) --> n\(node + 1)" }.joined(separator: "\n")
        guard case .unreadable(_, let failure) = ReadingDiagram(source: longChain, typography: typography) else { return XCTFail("Shown with why") }
        XCTAssertEqual(failure, .tooLargeToDraw(maximumSideLength: 20_000))
        XCTAssertEqual(failure.explanation, "This diagram is too large to draw (more than 20000 points on a side).")
    }
}
