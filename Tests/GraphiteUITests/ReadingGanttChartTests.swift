/**
 * File: ReadingGanttChartTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The reading view's Gantt charts.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

/// The reading view's Gantt charts. Charts whose dates are all before the day the tests run lay out the same whatever
/// that day; the moment and time zone are given wherever they matter.
final class ReadingGanttChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private let chart = """
    gantt
        title Launch plan
        dateFormat YYYY-MM-DD
        section Build
        Design : a1, 2014-01-01, 10d
        Implement : after a1, 20d
    """

    private func ganttChart(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .ganttChart)
    }

    func testAGanttChartIsLaidOutInTheNotesTextSize() throws {
        let gantt = try ganttChart(chart)
        XCTAssertEqual(gantt.scene.font.size, 17)
        XCTAssertEqual(gantt.scene.texts(reading: "Design").first?.block.fontSize, 14, "Thirteen sixteenths of the text size, rounded")
    }

    func testAScreenReaderHearsTheTitleAndTheTasks() throws {
        let gantt = try ganttChart(chart)
        XCTAssertEqual(gantt.accessibility.label, "Launch plan")
        XCTAssertEqual(gantt.accessibility.summary, ["Design", "Implement"])
        let described = try ganttChart("gantt\naccTitle: Spoken\naccDescr: What it plans\nA : 2014-01-01, 1d")
        XCTAssertEqual(described.accessibility.label, "Spoken")
        XCTAssertEqual(described.accessibility.description, "What it plans")
    }

    /// Today's line is drawn on the moment the chart is prepared, in its time zone: inside the chart's days it is one more
    /// accent line than on a day after them.
    func testTodaysLineFollowsTheMomentAndTimeZoneGiven() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func accentStrokes(now: Date) throws -> Int {
            try MermaidDiagramPreparation.prepare(source: chart, typography: typography, now: now, timeZone: utc).scene.shapes.filter { shape in
                if case .stroke(let paint, _) = shape.painting { paint == .accent } else { false }
            }.count
        }
        XCTAssertGreaterThan(try accentStrokes(now: Date(timeIntervalSince1970: 1_389_182_400)), try accentStrokes(now: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    /// MermaidDiagrams 0.3.0 and 0.4.0 draw what 0.2.0 refused: a click statement, a vertical marker and a start date that
    /// `dateFormat` does not read but JavaScript's `Date` does, so none of them keeps its source any more.
    func testAChartWithAClickAVerticalMarkerOrAJavaScriptDateIsDrawn() {
        let sources = [
            "gantt\nA : a, 2014-01-01, 1d\nclick a href \"https://example.com\"",
            "gantt\nA : vert, 2014-01-01, 1d",
            "gantt\nA : March 7 2014, 1d",
        ]
        for source in sources {
            guard case .drawn = ReadingDiagram(source: source, typography: typography) else { return XCTFail("Not drawn: \(source)") }
        }
    }

    func testAChartThatCannotBeScheduledKeepsItsSourceAndWhy() throws {
        let source = "gantt\ndateFormat YYYY-MM-DD\nexcludes weekends,monday,tuesday,wednesday,thursday,friday\nForever : 2019-02-01, 7d"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .ganttLayout(.noDayLeftAfterExclusions(task: "Forever")))
        guard case .unreadable(_, .reading(.invalidSyntax(line: 2, problem: .expectedTaskData))) = ReadingDiagram(source: "gantt\nNo colon here",
                                                                                                                  typography: typography) else {
            return XCTFail("Why")
        }
    }

    func testTheGanttChartsFailuresAreExplainedApart() {
        let failures: [MermaidDiagramPreparationFailure] = [
            .ganttLayout(.statementNotDrawn(.click)), .ganttLayout(.unreadableDate("x")), .ganttLayout(.noDayLeftAfterExclusions(task: "A")),
            .ganttLayout(.tooManyScheduledDays(limit: 1)), .reading(.invalidSyntax(line: 1, problem: .expectedTaskData)),
            .reading(.invalidSyntax(line: 1, problem: .taskWithoutEnd(task: "A"))),
            .reading(.invalidSyntax(line: 1, problem: .taskWithTooManyFields(task: "A"))),
        ]
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }

    /// The chart's quieter colors sit between the page and the text, where Pele's own colors put them, unless a theme sets them.
    func testTheChartsColorsSitBetweenThePageAndTheTextWhereThemeLeavesThem() {
        let colors = ReadingDiagramColors(background: Color(.sRGB, red: 1, green: 1, blue: 1),
                                          foreground: Color(.sRGB, red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255))
        func red(_ color: Color) -> CGFloat {
            let resolved = color.resolve(in: EnvironmentValues()).cgColor
            guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return -1 }
            return (resolved.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components?.first ?? 0) * 255
        }
        XCTAssertEqual(red(colors.muted), 0x6E, accuracy: 1.5)
        XCTAssertEqual(red(colors.alternateSurface), 0xE6, accuracy: 1.5)
        XCTAssertEqual(red(colors.critical), 0xE4, accuracy: 1)
    }
}
