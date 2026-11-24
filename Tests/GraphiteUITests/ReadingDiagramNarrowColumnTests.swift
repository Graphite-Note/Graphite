/**
 * File: ReadingDiagramNarrowColumnTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Wide diagrams laid out a second time for a narrow column, turned to run down, and which layout a
 *              column shows; diagrams with nothing to draw or too large to draw shown as their source with why.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import XCTest
import SwiftUI
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

    /// A diagram a little wider than the column is the regular one shrunk, not the one laid out for a phone's column;
    /// one that would have to be shrunk below the smallest readable scale is the narrow one (an XY chart configured 900
    /// points wide was drawn 230 points wide in a 750-point column).
    func testTheColumnShrinksTheRegularSceneUntilItWouldBeTooSmallToReadAndOnlyThenShowsTheNarrowOne() throws {
        let flowchart = try drawn(Self.fourteenShapesInARow, as: .flowchart)
        let regularWidth = flowchart.scene.size.width
        let narrow = try XCTUnwrap(flowchart.narrowScene)
        let smallest = ReadingDiagramPresentation.smallestReadableScale
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.shownScene(of: flowchart, inColumnWidth: regularWidth * 0.83, scaleAtNaturalWidth: 1).size,
                       flowchart.scene.size)
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.shownScene(of: flowchart, inColumnWidth: regularWidth * (smallest + 0.01), scaleAtNaturalWidth: 1).size,
                       flowchart.scene.size)
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.shownScene(of: flowchart, inColumnWidth: regularWidth * (smallest - 0.01), scaleAtNaturalWidth: 1).size,
                       narrow.size)
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.shownScene(of: flowchart, inColumnWidth: 700, scaleAtNaturalWidth: 1).size, narrow.size)
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.shownScene(of: flowchart, inColumnWidth: 0, scaleAtNaturalWidth: 1).size, flowchart.scene.size,
                       "Not measured yet.")
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

    /// Since MermaidDiagrams 0.7.0 the narrow scene is laid out the first time it is read. A diagram has it read where it is
    /// prepared, off the main actor, when a column 280 points wide or wider could show it, and only then: every column that
    /// shows a diagram's narrow scene is one this rule foresaw, so no view lays it out on the main actor.
    func testTheNarrowSceneIsReadWhenPreparedOnlyForADiagramThatSomeColumnCouldShowNarrow() throws {
        XCTAssertFalse(ReadingDiagram.narrowSceneMayBeShown(regularWidth: 466), "280 / 0.6 is 466.7 points.")
        XCTAssertTrue(ReadingDiagram.narrowSceneMayBeShown(regularWidth: 467))
        let diagrams = [try drawn(Self.fourteenShapesInARow, as: .flowchart), try drawn("flowchart LR\n  A[Start] --> B[Read] --> C[Done]", as: .flowchart),
                        try drawn("timeline\n  2020 : One\n  2021 : Two\n  2022 : Three\n  2023 : Four\n  2024 : Five", as: .timeline)]
        for diagram in diagrams {
            for columnWidth in stride(from: CGFloat(280), through: 2_400, by: 8)
            where ReadingScaledDiagram<EmptyView>.showsNarrowScene(of: diagram, inColumnWidth: columnWidth, scaleAtNaturalWidth: 1) {
                XCTAssertTrue(ReadingDiagram.narrowSceneMayBeShown(regularWidth: diagram.scene.size.width),
                              "A column \(columnWidth) wide shows the narrow scene of a diagram \(diagram.scene.size.width) wide.")
            }
        }
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
