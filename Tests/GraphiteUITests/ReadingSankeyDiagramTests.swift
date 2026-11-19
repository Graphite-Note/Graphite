/**
 * File: ReadingSankeyDiagramTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The reading view's Sankey diagrams.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingSankeyDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func sankey(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .sankey)
    }

    func testASankeyDiagramIsLaidOutInTheNotesTextSize() throws {
        let diagram = try sankey("---\ntitle: Energy\n---\nsankey-beta\nCoal,Solid,75.571\nSolid,Industry,46.477")
        XCTAssertEqual(diagram.scene.font.size, 17)
        XCTAssertEqual(diagram.scene.texts(reading: "Energy").first?.block.fontSize, 17)
        XCTAssertEqual(diagram.scene.texts(reading: "Coal").first?.block.fontSize, 15, "Seven eighths of the text size, rounded")
        XCTAssertEqual(diagram.scene.shapes.filter { shape in if case .gradientFill = shape.painting { true } else { false } }.count, 2,
                       "Each link a band from its source's color to its target's.")
    }

    func testAScreenReaderHearsTheTitleAndEachFlow() throws {
        let diagram = try sankey("---\ntitle: Energy\n---\nsankey\nCoal,Solid,75.571\nSolid,Industry,46\nSolid,Waste,none")
        XCTAssertEqual(diagram.accessibility.label, "Energy")
        XCTAssertEqual(diagram.accessibility.summary, ["Coal to Solid: 75.57", "Solid to Industry: 46", "Solid to Waste"])
        XCTAssertNil(try sankey("sankey\na,b,1").accessibility.title)
    }

    func testCircularLinksAndOptionsNotDrawnYetShowTheSourceAndWhy() {
        XCTAssertEqual(ReadingDiagram(source: "sankey\na,b,1\nb,a,1", typography: typography).failure, .sankeyLayout(.circularLinks))
        XCTAssertEqual(ReadingDiagram(source: "---\nconfig:\n  sankey:\n    labelStyle: outlined\n---\nsankey\na,b,1", typography: typography).failure,
                       .sankeyLayout(.optionsNotDrawn))
    }

    func testASankeyDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "sankey\na,b,1\nc,d"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .expectedSankeyFields)))
        let failures: [MermaidDiagramPreparationFailure] = [.reading(.invalidSyntax(line: 1, problem: .expectedSankeyFields)),
                                                            .reading(.invalidSyntax(line: 1, problem: .expectedSeriesValues)),
                                                            .reading(.invalidSyntax(line: 1, problem: .unclosedQuotation))]
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
