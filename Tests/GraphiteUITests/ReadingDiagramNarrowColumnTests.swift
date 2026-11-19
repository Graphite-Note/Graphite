/**
 * File: ReadingDiagramNarrowColumnTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Wide diagrams laid out a second time for a narrow column, turned to run down, and which layout a
 *              column shows; diagrams with nothing to draw or too large to draw shown as their source with why.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
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

    private func drawn(_ source: String, as kind: MermaidDiagramKind) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: kind)
    }

    /// The reading view's column is laid out for the narrowest column the reading view has, an iPhone's in portrait.
    func testTheNarrowestColumnIsAPhonesInPortrait() {
        XCTAssertEqual(PreparedMermaidDiagram.standardNarrowestColumnWidth, 280)
    }

    func testTheColumnShowsTheNarrowLayoutOnlyWhereTheRegularOneDoesNotFitAndTheNarrowOneIsNarrower() throws {
        let flowchart = try drawn(Self.fourteenShapesInARow, as: .flowchart)
        let regularWidth = flowchart.scene.size.width
        let narrowWidth = try XCTUnwrap(flowchart.narrowScene).size.width
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: regularWidth + 1), "It fits.")
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: regularWidth - 1))
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: narrowWidth / 2), "Scaled down less.")
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: 0), "Not measured yet.")
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: regularWidth, scale: 1.2), "At a larger text size the regular one no longer fits.")
        XCTAssertFalse(try drawn("flowchart LR\n  A --> B", as: .flowchart).showsNarrowScene(inColumnWidth: 100), "No narrow layout.")
    }

    func testTheFourteenShapesInARowAreTurnedToRunDownWithTighterGapsForANarrowColumn() throws {
        let flowchart = try drawn(Self.fourteenShapesInARow, as: .flowchart)
        XCTAssertGreaterThan(flowchart.scene.size.width, 2_000)
        let narrow = try XCTUnwrap(flowchart.narrowScene)
        XCTAssertLessThan(narrow.size.width, 360, "It fits an iPhone's column without being scaled down.")
        let names = ["Rectangle", "Rounded", "Stadium", "Subroutine", "Database", "Circle", "Double circle", "Flag", "Diamond", "Hexagon"]
        let centers = names.compactMap { name in narrow.texts(reading: name).first?.block.center.y }
        XCTAssertEqual(centers.count, names.count)
        XCTAssertEqual(centers, centers.sorted(), "The shapes follow each other down.")
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: 700))
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: 350))
    }

    func testADiagramNarrowerThanTheNarrowestColumnIsLaidOutOnce() throws {
        let flowchart = try drawn("flowchart LR\n  A --> B", as: .flowchart)
        XCTAssertLessThanOrEqual(flowchart.scene.size.width, PreparedMermaidDiagram.standardNarrowestColumnWidth)
        XCTAssertNil(flowchart.narrowScene)
    }

    func testAWideFlowchartThatRunsDownIsStillTightenedForANarrowColumn() throws {
        let source = "flowchart TD\n  Root --> " + (1...8).map { child in "C\(child)[Child number \(child)]" }.joined(separator: " & ")
        let flowchart = try drawn(source, as: .flowchart)
        XCTAssertLessThan(try XCTUnwrap(flowchart.narrowScene).size.width, flowchart.scene.size.width)
    }

    func testGitGraphsTimelinesAndGraphsRunningAcrossAreTurnedToRunDown() throws {
        let commits = (1...14).map { commit in "  commit id: \"c\(commit)\"" }.joined(separator: "\n")
        let gitGraph = try drawn("gitGraph\n\(commits)", as: .gitGraph)
        let gitNarrow = try XCTUnwrap(gitGraph.narrowScene)
        XCTAssertLessThan(gitNarrow.size.width, gitGraph.scene.size.width)
        XCTAssertGreaterThan(gitNarrow.size.height, gitNarrow.size.width, "Commits follow each other down.")

        let periods = (2000...2010).map { year in "  \(year) : Event of \(year)" }.joined(separator: "\n")
        let timeline = try drawn("timeline\n\(periods)", as: .timeline)
        XCTAssertLessThan(try XCTUnwrap(timeline.narrowScene).size.width, timeline.scene.size.width)

        let chain = (1...6).map { state in "S\(state) --> S\(state + 1)" }.joined(separator: "\n")
        let states = try drawn("stateDiagram-v2\ndirection LR\n\(chain)", as: .stateDiagram)
        XCTAssertLessThan(try XCTUnwrap(states.narrowScene).size.width, states.scene.size.width)
        let entities = try drawn("erDiagram\ndirection LR\n" + (1...6).map { entity in "E\(entity) ||--o{ E\(entity + 1) : has" }.joined(separator: "\n"),
                                 as: .entityRelationship)
        XCTAssertLessThan(try XCTUnwrap(entities.narrowScene).size.width, entities.scene.size.width)
        let classes = try drawn("classDiagram\ndirection LR\n" + (1...6).map { node in "Class\(node) <|-- Class\(node + 1)" }.joined(separator: "\n"),
                                as: .classDiagram)
        XCTAssertLessThan(try XCTUnwrap(classes.narrowScene).size.width, classes.scene.size.width)
    }

    func testAStateDiagramRunningAcrossIsTurnedWithItsComposites() throws {
        let source = "stateDiagram-v2\ndirection LR\n[*] --> Idle\nIdle --> Working\nstate Working {\n  direction LR\n  Reading --> Writing\n  Writing --> Saving\n}\n"
            + "Working --> Done\nDone --> [*]"
        let diagram = try drawn(source, as: .stateDiagram)
        let narrow = try XCTUnwrap(diagram.narrowScene)
        XCTAssertLessThan(narrow.size.width, diagram.scene.size.width)
        XCTAssertTrue(narrow.shapes.contains { shape in shape.part == .cluster }, "The composite is still a box.")
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
