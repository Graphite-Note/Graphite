/**
 * File: ReadingTimelineTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The reading view's timelines.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

final class ReadingTimelineTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func timeline(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .timeline)
    }

    func testATimelineIsLaidOutInTheNotesTextSize() throws {
        let timeline = try timeline("timeline\n  2002 : LinkedIn\n  2004 : Facebook : Google")
        XCTAssertEqual(timeline.scene.font.size, 17)
        XCTAssertEqual(timeline.accessibility.summary, ["2002: LinkedIn", "2004: Facebook, Google"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try timeline("timeline\n  title History\n  accDescr: Platforms by year\n  2002")
        XCTAssertEqual(titled.accessibility.title, "History")
        XCTAssertEqual(titled.accessibility.description, "Platforms by year")
        XCTAssertEqual(try timeline("timeline\n  accTitle: Named\n  title Shown\n  2002").accessibility.title, "Named")
        XCTAssertEqual(try timeline("timeline\n  2002").accessibility.summary, ["2002"])
    }

    func testATimelineThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "timeline\n  : early"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .eventWithoutPeriod)))
    }

    func testTheTimelinesProblemIsExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.unknownDirection("XY"), .expectedNode, .unclosedShape(closingText: "]"), .unclosedQuotation,
                                                .unclosedEdgeLabel, .unclosedAttributes, .unclosedAccessibilityDescription, .unclosedFrontMatter,
                                                .endWithoutSubgraph, .unclosedSubgraph(identifier: "one"), .unexpectedText("C"),
                                                .secondRoot(text: "second"), .unclosedIcon, .eventWithoutPeriod]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
    }

    /// A timeline written to run down (`timeline TD`) is laid out down, not as the same timeline across.
    func testTheReadingViewBuildsATimelineBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "TimelineVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\ntimeline TD\n  2002 : LinkedIn\n  2004 : Facebook\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, let diagram) = blocks[1] else { return XCTFail("The timeline is drawn") }
        let scene = try diagram.drawn(as: .timeline).scene
        let across = try timeline("timeline\n  2002 : LinkedIn\n  2004 : Facebook").scene
        XCTAssertNotEqual(scene.size, across.size)
    }
}
