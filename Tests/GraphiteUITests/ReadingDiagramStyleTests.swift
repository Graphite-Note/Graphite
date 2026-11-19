/**
 * File: ReadingDiagramStyleTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Checks that a flowchart's colors reach the reading view's painting, and that diagrams whose styling is not drawn say so.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

/// HUNT-222: `classDef`, `style`, `linkStyle` and `:::class` were dropped without a word, so a diagram drawn in plain colors looked
/// complete next to Obsidian's.
final class ReadingDiagramStyleTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func flowchart(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .flowchart)
    }

    /// The paints of the scene's shapes, their fills' and strokes' alike.
    private func paints(of scene: DiagramScene) -> [DiagramPaint] {
        scene.shapes.flatMap { shape -> [DiagramPaint] in
            switch shape.painting {
            case .fill(let paint), .stroke(let paint, _): [paint]
            case .fillAndStroke(let fill, let stroke, _): [fill, stroke]
            case .gradientFill(let gradient): [gradient.startPaint, gradient.endPaint]
            }
        }
    }

    func testAStyledNodeAndEdgeReachThePaintingWithTheirColors() throws {
        let flowchart = try flowchart("flowchart TD\nA[Start] --> B\nclassDef warm fill:#ff0000,stroke:#0000ff,color:#00ff00\nclass A warm\nlinkStyle 0 stroke:#00aa00,stroke-width:3px")
        let paints = paints(of: flowchart.scene)
        XCTAssertTrue(paints.contains(.color(DiagramColor(red: 1, green: 0, blue: 0))), "The node's fill")
        XCTAssertTrue(paints.contains(.color(DiagramColor(red: 0, green: 0, blue: 1))), "The node's outline")
        XCTAssertTrue(flowchart.scene.shapes.contains { shape in
            if case .stroke(let paint, let stroke) = shape.painting { paint == .color(DiagramColor(red: 0, green: 0xAA / 255, blue: 0)) && stroke.lineWidth == 3 } else { false }
        }, "The edge's own stroke and width")
        XCTAssertEqual(flowchart.scene.texts(reading: "Start").map(\.paint), [.color(DiagramColor(red: 0, green: 1, blue: 0))],
                       "The styled node's text is painted with its own color")
        XCTAssertEqual(flowchart.scene.texts(reading: "B").map(\.paint), [.foreground])
        XCTAssertEqual(flowchart.unappliedStatementCount, 0)
    }

    func testAFlowchartWithoutStylingHasNoWrittenColors() throws {
        let flowchart = try flowchart("flowchart TD\nA --> B")
        XCTAssertFalse(paints(of: flowchart.scene).contains { paint in if case .color = paint.source { true } else { false } })
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
        XCTAssertEqual(ReadingDiagram(source: "flowchart TD\nA[never closed", typography: typography).unappliedStatementCount, 0, "A source shown with why")
    }

    func testAColorWrittenInAStatementIsTheSameColorOnScreen() {
        let swiftUIColor = Color(DiagramColor(red: 1, green: 0.5, blue: 0, alpha: 0.25))
        XCTAssertEqual(swiftUIColor, Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.25))
    }
}
