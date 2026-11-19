/**
 * File: ReadingMindmapTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The reading view's mindmaps.
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

final class ReadingMindmapTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func mindmap(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .mindmap)
    }

    func testAMindmapIsLaidOutInTheNotesTextSize() throws {
        let mindmap = try mindmap("mindmap\n  root((Plans))\n    Study\n    Rest")
        XCTAssertEqual(mindmap.scene.font.size, 17)
        XCTAssertEqual(mindmap.accessibility.summary, ["Plans", "Study", "Rest"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try mindmap("---\ntitle: Front title\n---\nmindmap\n  root\n  accDescr: How it branches")
        XCTAssertEqual(titled.accessibility.title, "Front title")
        XCTAssertEqual(titled.accessibility.description, "How it branches")
        XCTAssertEqual(try mindmap("mindmap\n  accTitle: Named\n  root").accessibility.title, "Named")
        XCTAssertNil(try mindmap("mindmap\n  root").accessibility.title)
        XCTAssertEqual(try mindmap("mindmap\n  root").accessibility.label, "Mindmap")
    }

    func testAMindmapThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "mindmap\n  root\n  second"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .secondRoot(text: "second"))))
    }

    func testTheMindmapsProblemsAreExplainedApartFromTheOthers() {
        let others: [MermaidSyntaxProblem] = [.unknownDirection("XY"), .expectedNode, .unclosedShape(closingText: "]"), .unclosedQuotation,
                                              .unclosedEdgeLabel, .unclosedAttributes, .unclosedAccessibilityDescription, .unclosedFrontMatter,
                                              .endWithoutSubgraph, .unclosedSubgraph(identifier: "one"), .unexpectedText("C")]
        let problems = others + [.secondRoot(text: "second"), .unclosedIcon]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
    }

    func testTheReadingViewBuildsAMindmapBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "MindmapVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\nmindmap\n  root\n    child\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, let diagram) = blocks[1] else { return XCTFail("The mindmap is drawn") }
        XCTAssertEqual(try diagram.drawn(as: .mindmap).accessibility.summary, ["root", "child"])
    }
}
