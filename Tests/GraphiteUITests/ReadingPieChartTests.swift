/**
 * File: ReadingPieChartTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The reading view's pie charts.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingPieChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func pieChart(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .pieChart)
    }

    func testAPieChartIsLaidOutInTheNotesTextSize() throws {
        let chart = try pieChart("pie title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Rats\" : 15")
        XCTAssertEqual(chart.scene.font.size, 17)
        XCTAssertEqual(chart.scene.texts(reading: "Pets").first?.block.fontSize, 17)
        XCTAssertEqual(chart.scene.texts(reading: "Dogs").first?.block.fontSize, 15, "Seven eighths of the text size, rounded")
        XCTAssertEqual(Set((0..<3).map { series in DiagramPaint.series(series) }).isSubset(of: Set(chart.scene.shapes.compactMap { shape in
            if case .fill(let paint) = shape.painting { paint } else { nil }
        })), true, "Each slice in its series color")
    }

    func testAScreenReaderHearsTheTitleAndEachSliceWithItsShare() throws {
        let chart = try pieChart("pie showData title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Tiny\" : 1")
        XCTAssertEqual(chart.accessibility.label, "Pets")
        XCTAssertNil(chart.accessibility.description)
        XCTAssertEqual(chart.accessibility.summary, ["Dogs [386] 82%", "Cats [85] 18%", "Tiny [1]"], "A slice under one percent is not drawn")
        let described = try pieChart("pie title Shown\naccTitle: Spoken\naccDescr: What it shows\n\"a\" : 1")
        XCTAssertEqual(described.accessibility.label, "Spoken")
        XCTAssertEqual(described.accessibility.value, "What it shows")
    }

    func testAPieChartThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "pie\n\"dogs\" : -1"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .negativeSliceValue(label: "dogs"))))
    }

    func testThePieChartsProblemsAreExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.expectedSliceValue, .negativeSliceValue(label: "dogs"), .unexpectedText("x"), .unclosedQuotation]
        let failures = problems.map { problem in MermaidDiagramPreparationFailure.reading(.invalidSyntax(line: 1, problem: problem)) }
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
