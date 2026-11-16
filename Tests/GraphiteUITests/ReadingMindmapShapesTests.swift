import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingMindmapShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAMindmap: Error {}

    private func mindmap(_ source: String) throws -> ReadingMindmap {
        guard case .mindmap(let mindmap) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAMindmap() }
        return mindmap
    }

    func testEachBranchKeepsItsNumberLinksAndOutlines() throws {
        let mindmap = try mindmap("mindmap\n  root\n    a[Alpha]\n    b\n      leaf")
        XCTAssertEqual(mindmap.shapes.branches.map(\.branchIndex), [0, 1])
        XCTAssertEqual(mindmap.shapes.branches[0].nodeOutlines.boundingRect, mindmap.layout.nodes[1].frame)
        XCTAssertFalse(mindmap.shapes.branches[1].links.isEmpty)
        XCTAssertEqual(mindmap.shapes.rootOutline.boundingRect, mindmap.layout.nodes[0].frame)
    }

    func testEachLineOfTextIsPlacedAndTheTitleIsLastAndBold() throws {
        let mindmap = try mindmap("---\ntitle: Plan\n---\nmindmap\n  root\n    two<br>lines")
        let node = mindmap.layout.nodes[1].text
        let lines = mindmap.shapes.textLines.filter { line in line.text == "two" || line.text == "lines" }
        XCTAssertEqual(lines.map(\.text), ["two", "lines"])
        XCTAssertEqual(lines[0].center.x, node.center.x)
        XCTAssertEqual(lines[1].center.y - lines[0].center.y, node.lineHeight)
        XCTAssertEqual(mindmap.shapes.textLines.last?.text, "Plan")
        XCTAssertEqual(mindmap.shapes.textLines.last?.isBold, true)
    }

    func testBranchesTakeTheEightSeriesColorsInTurn() {
        let colors = ReadingDiagramColors(background: .white, foreground: .black)
        XCTAssertEqual(colors.series.count, 8)
        XCTAssertEqual(colors.seriesColor(8), colors.seriesColor(0))
        XCTAssertNotEqual(colors.seriesColor(1), colors.seriesColor(0))
    }
}
