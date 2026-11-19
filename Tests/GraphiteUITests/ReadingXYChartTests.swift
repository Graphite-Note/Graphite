/**
 * File: ReadingXYChartTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The reading view's XY charts.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingXYChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func chart(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .xyChart)
    }

    func testAnXYChartIsLaidOutInTheNotesTextSize() throws {
        let chart = try chart("xychart\n  title \"Sales\"\n  x-axis [jan, feb]\n  line [1 \"low\", 2]")
        XCTAssertEqual(chart.scene.font.size, 17)
        XCTAssertEqual(chart.scene.texts(reading: "Sales").first?.block.fontSize, 17)
        XCTAssertEqual(chart.scene.texts(reading: "jan").first?.block.fontSize, 15, "Seven eighths of the text size, rounded")
        XCTAssertEqual(chart.scene.texts(reading: "low").first?.block.fontSize, 13, "Three quarters of the text size, rounded")
    }

    func testAScreenReaderHearsTheTitleAndEachSeriesWithItsValues() throws {
        let chart = try chart("xychart\n  title \"Sales\"\n  x-axis [jan, feb, mar]\n  bar \"Revenue\" [5000, 6000.5]\n  line [1, 2, 3]")
        XCTAssertEqual(chart.accessibility.label, "Sales")
        XCTAssertNil(chart.accessibility.description)
        XCTAssertEqual(chart.accessibility.summary, ["Revenue: jan 5000, feb 6000.5", "Line: jan 1, feb 2, mar 3"])
        XCTAssertEqual(try self.chart("xychart\n  bar [3, 4]").accessibility.summary, ["Bars: 3, 4"])
        let described = try self.chart("xychart\n  title \"Shown\"\n  accTitle: Spoken\n  accDescr: What it shows\n  bar [1]")
        XCTAssertEqual(described.accessibility.label, "Spoken")
        XCTAssertEqual(described.accessibility.value, "What it shows")
    }

    func testAnXYChartThatCannotBeReadOrLaidOutKeepsItsSourceAndWhy() throws {
        let source = "xychart\n  line [1, , 2]"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .expectedSeriesValues)))
        XCTAssertEqual(ReadingDiagram(source: "xychart\n  x-axis [a]", typography: typography).failure, .xyChartLayout(.noSeries))
    }

    func testTheXYChartsProblemsAreExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.expectedChartText, .expectedAxisRange, .expectedCategories, .expectedSeriesValues, .unexpectedText("x")]
        var failures = problems.map { problem in MermaidDiagramPreparationFailure.reading(.invalidSyntax(line: 1, problem: problem)) }
        failures += [.reading(.tooManyChartValues(limit: 5_000)), .reading(.tooManyNodes(limit: 5_000)), .xyChartLayout(.noSeries)]
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
