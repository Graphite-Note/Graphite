/**
 * File: PieChartOptionsTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The pie chart options of the front matter applied: the percentages' position, the donut's hole and the
 *              legend's place, and values out of range left at their defaults.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class PieChartOptionsTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let slices = "pie\n  \"Dogs\" : 386\n  \"Cats\" : 85\n  \"Rats\" : 15"

    private func chart(options: String) throws -> PieChart {
        guard case .pieChart(let chart) = try MermaidDiagramReader.read("---\nconfig:\n  pie:\n\(options)\n---\n\(slices)", limits: .standard) else {
            XCTFail("A pie chart")
            return PieChart()
        }
        return chart
    }

    private func layout(options: String) throws -> PieChartLayout {
        PieChartLayoutEngine.layout(try chart(options: options), typography: typography)
    }

    func testOptionsAreReadAndValuesOutOfRangeKeepTheirDefaults() throws {
        let options = try chart(options: "    textPosition: 0.5\n    donutHole: 0.4\n    legendPosition: bottom").options
        XCTAssertEqual(options.percentagePosition, 0.5)
        XCTAssertEqual(options.holeShare, 0.4)
        XCTAssertEqual(options.legendPosition, .bottom)
        let wrong = try chart(options: "    textPosition: 3\n    donutHole: 0.95\n    legendPosition: sideways").options
        XCTAssertEqual(wrong, PieChartOptions())
        guard case .pieChart(let plain) = try MermaidDiagramReader.read(slices, limits: .standard) else { return XCTFail("A pie") }
        XCTAssertEqual(plain.options, PieChartOptions())
    }

    func testTheTextPositionPlacesThePercentagesThatShareOfTheRadiusOut() throws {
        let laidOut = try layout(options: "    textPosition: 0.5")
        let dogs = try XCTUnwrap(laidOut.slices.first)
        let distance = hypot(dogs.percentage.center.x - laidOut.center.x, dogs.percentage.center.y - laidOut.center.y)
        XCTAssertEqual(distance, laidOut.radius * 0.5, accuracy: 0.01)
    }

    func testADonutLeavesItsHoleUnpaintedAndPutsItsPercentagesInTheRing() throws {
        let laidOut = try layout(options: "    donutHole: 0.6")
        XCTAssertEqual(laidOut.innerRadius, laidOut.radius * 0.6, accuracy: 0.01)
        let dogs = try XCTUnwrap(laidOut.slices.first)
        XCTAssertEqual(hypot(dogs.percentage.center.x - laidOut.center.x, dogs.percentage.center.y - laidOut.center.y), laidOut.radius * 0.8, accuracy: 0.01)
        let parts = PieChartDrawingParts(layout: laidOut)
        XCTAssertFalse(parts.sliceEdges.contains(laidOut.center), "The hole is not inside any slice.")
        let ringPoint = CGPoint(x: laidOut.center.x, y: laidOut.center.y - laidOut.radius * 0.8)
        XCTAssertTrue(parts.seriesFills[0].contains(ringPoint), "The first slice fills the ring at the top.")
        let whole = PieChartDrawingParts.wedge(PieChartLayoutSlice(seriesIndex: 0, startAngle: 0, endAngle: 2 * .pi, percentage: dogs.percentage,
                                                                   percentagePlacement: .insideSlice), center: .zero, radius: 100, innerRadius: 50)
        XCTAssertFalse(whole.contains(.zero))
        XCTAssertTrue(whole.contains(CGPoint(x: 75, y: 0)))
    }

    func testTheLegendStandsWhereItsPositionSays() throws {
        let right = try layout(options: "    legendPosition: right")
        XCTAssertGreaterThan(try XCTUnwrap(right.legend.first).swatch.minX, right.center.x + right.radius)
        let left = try layout(options: "    legendPosition: left")
        XCTAssertLessThan(try XCTUnwrap(left.legend.first).text.frame.maxX, left.center.x - left.radius)
        let bottom = try layout(options: "    legendPosition: bottom")
        XCTAssertGreaterThan(try XCTUnwrap(bottom.legend.first).swatch.minY, bottom.center.y + bottom.radius)
        XCTAssertLessThan(bottom.size.width, right.size.width, "Below the pie, the legend takes no width beside it.")
        let top = try layout(options: "    legendPosition: top")
        XCTAssertLessThan(try XCTUnwrap(top.legend.last).swatch.maxY, top.center.y - top.radius)
        let none = try layout(options: "    legendPosition: none")
        XCTAssertTrue(none.legend.isEmpty)
        XCTAssertEqual(none.slices.count, 3)
        for laidOut in [right, left, bottom, top, none] {
            let pie = CGRect(x: laidOut.center.x - laidOut.radius, y: laidOut.center.y - laidOut.radius, width: 2 * laidOut.radius, height: 2 * laidOut.radius)
            XCTAssertTrue(CGRect(origin: .zero, size: laidOut.size).contains(pie))
            for entry in laidOut.legend {
                XCTAssertTrue(CGRect(origin: .zero, size: laidOut.size).contains(entry.text.frame))
                XCTAssertFalse(entry.text.frame.intersects(pie))
            }
        }
    }
}
