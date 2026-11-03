/**
 * File: ReadingDiagramStyleTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Checks that a flowchart's colors reach the reading view's shapes, and that diagrams whose styling is not drawn say so.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

/// HUNT-222: `classDef`, `style`, `linkStyle` and `:::class` were dropped without a word, so a diagram drawn in plain colors looked
/// complete next to Obsidian's.
final class ReadingDiagramStyleTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func flowchart(_ source: String) throws -> ReadingFlowchart {
        guard case .flowchart(let flowchart) = ReadingDiagram(source: source, typography: typography) else { throw NotAFlowchart() }
        return flowchart
    }

    private struct NotAFlowchart: Error {}

    func testAStyledNodeAndEdgeReachTheShapesWithTheirColors() throws {
        let flowchart = try flowchart("flowchart TD\nA[Start] --> B\nclassDef warm fill:#ff0000,stroke:#0000ff,color:#00ff00\nclass A warm\nlinkStyle 0 stroke:#00aa00,stroke-width:3px")
        XCTAssertEqual(flowchart.shapes.styledNodes.count, 1)
        XCTAssertEqual(flowchart.shapes.styledNodes[0].style.fill, DiagramColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(flowchart.shapes.styledNodes[0].textLines.map(\.text), ["Start"])
        XCTAssertEqual(flowchart.shapes.styledEdges.count, 1)
        XCTAssertEqual(flowchart.shapes.styledEdges[0].lineWidth, 3)
        XCTAssertEqual(flowchart.unappliedStatementCount, 0)
        XCTAssertEqual(flowchart.shapes.nodeTextLines.map(\.text), ["B"], "The styled node's text is painted with its own color")
    }

    func testAFlowchartWithoutStylingHasNoStyledShapes() throws {
        let flowchart = try flowchart("flowchart TD\nA --> B")
        XCTAssertTrue(flowchart.shapes.styledNodes.isEmpty)
        XCTAssertTrue(flowchart.shapes.styledEdges.isEmpty)
        XCTAssertEqual(ReadingDiagram(source: "flowchart TD\nA --> B", typography: typography).unappliedStatementCount, 0)
    }

    func testDiagramsWhoseStylingIsNotDrawnSayHowManyStatementsAreNotApplied() {
        XCTAssertEqual(ReadingDiagram(source: "flowchart TD\nA --> B\nclick A \"https://example.com\"", typography: typography).unappliedStatementCount, 1)
        XCTAssertGreaterThan(ReadingDiagram(source: "stateDiagram-v2\n[*] --> Still\nclassDef moving fill:#f00\nclass Still moving", typography: typography)
            .unappliedStatementCount, 0)
        XCTAssertGreaterThan(ReadingDiagram(source: "classDiagram\nclass Duck\nstyle Duck fill:#f00", typography: typography).unappliedStatementCount, 0)
        XCTAssertGreaterThan(ReadingDiagram(source: "erDiagram\nCUSTOMER ||--o{ ORDER : places\nstyle CUSTOMER fill:#f00", typography: typography)
            .unappliedStatementCount, 0)
        XCTAssertEqual(ReadingDiagram(source: "pie\n\"A\" : 1", typography: typography).unappliedStatementCount, 0)
    }

    func testAColorWrittenInAStatementIsTheSameColorOnScreen() {
        let swiftUIColor = Color(DiagramColor(red: 1, green: 0.5, blue: 0, alpha: 0.25))
        XCTAssertEqual(swiftUIColor, Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.25))
    }
}
