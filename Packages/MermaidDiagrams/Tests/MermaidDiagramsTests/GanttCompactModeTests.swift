/**
 * File: GanttCompactModeTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: `displayMode: compact`: tasks of a section that follow each other share a row; overlapping ones and
 *              other sections' tasks do not.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class GanttCompactModeTests: XCTestCase {
    private func laidOut(_ source: String) throws -> GanttLayout {
        let chart = try GanttChartReading.ganttChart(source)
        let zone = try GanttScheduling.zone("UTC")
        let moment = try GanttScheduling.now()
        let schedule = try GanttSchedule(chart: chart, now: moment, zone: zone, limits: .standard)
        let measurers = GanttMeasurers(title: UniformWidthTextMeasurer(), row: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20),
                                       axis: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))
        return GanttLayoutEngine.layout(chart, schedule: schedule.entries, now: moment, zone: zone, measurers: measurers, font: UniformWidthLayout.font)
    }

    private let tasks = """
    gantt
        dateFormat YYYY-MM-DD
        section Build
            Design  :a1, 2014-01-01, 10d
            Code    :a2, after a1, 10d
            Review  :2014-01-05, 3d
        section Ship
            Release :2014-01-25, 2d
    """

    private func rowMiddles(_ layout: GanttLayout) throws -> [CGFloat] {
        try XCTUnwrap(layout.plot).tasks.map(\.label.center.y)
    }

    func testCompactModeIsReadFromTheFrontMatter() throws {
        XCTAssertTrue(try GanttChartReading.ganttChart("---\nconfig:\n  gantt:\n    displayMode: compact\n---\n" + tasks).isCompact)
        XCTAssertFalse(try GanttChartReading.ganttChart(tasks).isCompact)
        XCTAssertFalse(try GanttChartReading.ganttChart("---\nconfig:\n  gantt:\n    displayMode: standard\n---\n" + tasks).isCompact)
    }

    func testTasksThatFollowEachOtherShareARowAndOverlappingOnesDoNot() throws {
        let standard = try laidOut(tasks)
        let compact = try laidOut("---\nconfig:\n  gantt:\n    displayMode: compact\n---\n" + tasks)
        XCTAssertEqual(Set(try rowMiddles(standard)).count, 4, "A row per task.")
        let middles = try rowMiddles(compact)
        XCTAssertEqual(middles[0], middles[1], "Code follows Design on its row.")
        XCTAssertNotEqual(middles[2], middles[0], "Review overlaps Design: a row of its own.")
        XCTAssertNotEqual(middles[3], middles[0], "Another section's task never shares a row with this one's.")
        XCTAssertNotEqual(middles[3], middles[2])
        let standardPlot = try XCTUnwrap(standard.plot), compactPlot = try XCTUnwrap(compact.plot)
        XCTAssertEqual(compactPlot.frame.height, standardPlot.frame.height * 3 / 4, accuracy: 0.01, "Three rows instead of four.")
        XCTAssertEqual(compactPlot.sectionNames.count, 2)
    }
}
