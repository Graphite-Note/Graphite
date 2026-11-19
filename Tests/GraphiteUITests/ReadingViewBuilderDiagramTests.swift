/**
 * File: ReadingViewBuilderDiagramTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Mermaid blocks in the reading view's build.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.12
 * Date: 19/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block in the reading view: a diagram becomes a diagram block of its own, prepared with the other blocks
/// off the main actor; a type not drawn natively shows its source and why.
final class ReadingViewBuilderDiagramTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "DiagramVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    private func build(_ source: String, configuration: ReadingConfiguration = ReadingConfiguration()) async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: source, note: try VaultPath("Note.md"), root: vault, index: index, configuration: configuration)
    }

    func testAFlowchartBecomesADiagramBlockBetweenTheTextAroundIt() async throws {
        let blocks = try await build("Before\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\nAfter").blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, let diagram) = blocks[1] else { return XCTFail("The flowchart is a diagram block") }
        XCTAssertEqual(try diagram.drawn(as: .flowchart).accessibility.summary, ["A", "B"])
        guard case .markdown(_, let after) = blocks[2] else { return XCTFail("Text follows") }
        XCTAssertEqual(after.trimmingCharacters(in: .whitespacesAndNewlines), "After")
    }

    func testTheDiagramIsLaidOutAtTheNotesTextSize() async throws {
        var configuration = ReadingConfiguration()
        configuration.textSize = 22
        let blocks = try await build("```mermaid\ngraph TD\nA\n```", configuration: configuration).blocks
        guard case .diagram(_, let diagram) = blocks.first else { return XCTFail("Drawn") }
        XCTAssertEqual(try diagram.drawn(as: .flowchart).scene.font.size, 22)
    }

    func testATypeNotDrawnYetIsADiagramBlockThatShowsItsSourceAndSaysSo() async throws {
        let blocks = try await build("```mermaid\nrequirementDiagram\n  requirement test_req {\n  }\n```").blocks
        guard case .diagram(_, .unreadable(let source, let failure)) = blocks.first else { return XCTFail("Shown with why") }
        XCTAssertEqual(source, "requirementDiagram\n  requirement test_req {\n  }")
        XCTAssertEqual(failure, .reading(.unsupportedDiagramType(keyword: "requirementDiagram")))
    }

    func testASequenceDiagramBecomesADiagramBlockAndOneWithABoxShowsWhy() async throws {
        let drawn = try await build("Before\n\n```mermaid\nsequenceDiagram\n  Alice->>Bob: Hi\n```\n\nAfter").blocks
        XCTAssertEqual(drawn.count, 3)
        guard case .diagram(_, let sequence) = drawn[1] else { return XCTFail("The sequence diagram is a diagram block") }
        XCTAssertTrue(try sequence.drawn(as: .sequence).accessibility.value.hasPrefix("Alice, Bob."))
        let boxed = try await build("```mermaid\nsequenceDiagram\n  box Team\n  participant A\n  end\n```").blocks
        guard case .diagram(_, .unreadable(_, .sequenceLayout)) = boxed.first else { return XCTFail("A diagram with a box shows its source and why") }
    }

    func testAFlowchartWithSubgraphsBecomesADiagramBlockWithItsBoxes() async throws {
        let blocks = try await build("```mermaid\nflowchart LR\n  subgraph one [Group]\n    A --> B\n  end\n  B --> C\n```").blocks
        guard case .diagram(_, let diagram) = blocks.first else { return XCTFail("The flowchart is a diagram block") }
        let flowchart = try diagram.drawn(as: .flowchart)
        XCTAssertTrue(flowchart.scene.shapes.contains { shape in shape.part == .cluster })
        XCTAssertEqual(flowchart.scene.texts(reading: "Group").map(\.part), [.clusterLabel])
    }

    func testAFlowchartWithACollapsedGroupShowsItsSourceAndWhy() async throws {
        let source = "```mermaid\nflowchart TD\n  subgraph one\n    A\n  end\n  one@{ view: collapsed }\n```"
        guard case .diagram(_, .unreadable(_, let failure)) = try await build(source).blocks.first else { return XCTFail("Shown with why") }
        XCTAssertEqual(failure, .flowchartLayout(.subgraphsNotLaidOut))
    }

    func testAFlowchartInACalloutIsDrawnInsideIt() async throws {
        let blocks = try await build("> [!example] Flow\n> ```mermaid\n> flowchart TD\n> A --> B\n> ```").blocks
        guard case .callout(_, _, _, _, let body) = blocks.first, case .diagram = body.first else { return XCTFail("Drawn in the callout") }
    }

    func testAClassDiagramBecomesADiagramBlockAndOneWithNamespacesShowsWhy() async throws {
        let drawn = "```mermaid\nclassDiagram\n  Animal <|-- Duck\n```"
        let blocks = try await build(drawn + "\n\n```mermaid\nclassDiagram\nnamespace Shapes {\n  class Square\n}\n```").blocks
        XCTAssertEqual(blocks.count, 2)
        guard case .diagram(_, let classDiagram) = blocks[0] else { return XCTFail("The class diagram is a diagram block") }
        XCTAssertEqual(try classDiagram.drawn(as: .classDiagram).accessibility.summary.count, 2)
        guard case .diagram(_, .unreadable(_, let failure)) = blocks[1] else { return XCTFail("Shown with why") }
        XCTAssertEqual(failure, .classDiagramLayout(.namespacesNotLaidOut))
    }

    func testAnEntityRelationshipDiagramBecomesADiagramBlock() async throws {
        let blocks = try await build("Schema\n\n```mermaid\nerDiagram\n  CUSTOMER ||--o{ ORDER : places\n```").blocks
        XCTAssertEqual(blocks.count, 2)
        guard case .diagram(_, let diagram) = blocks[1] else { return XCTFail("The entity relationship diagram is a diagram block") }
        XCTAssertEqual(Array(try diagram.drawn(as: .entityRelationship).accessibility.summary.prefix(2)), ["CUSTOMER", "ORDER"])
    }

    func testTheFontOfTheDiagramChangesWhatTheReadingViewReloadsFor() {
        var configuration = ReadingConfiguration()
        let systemFontHash = configuration.hashValueForReload
        configuration.diagramFontPostScriptName = "Georgia"
        XCTAssertNotEqual(configuration.hashValueForReload, systemFontHash)
    }

    func testAStateDiagramBecomesADiagramBlockAndOneWithCompositeStatesToo() async throws {
        let blocks = try await build("```mermaid\nstateDiagram-v2\n  [*] --> Still\n  Still --> [*]\n```").blocks
        guard case .diagram(_, let diagram) = blocks.first else { return XCTFail("The state diagram is a diagram block") }
        XCTAssertEqual(try diagram.drawn(as: .stateDiagram).accessibility.summary, ["Still"])
        let composite = try await build("```mermaid\nstateDiagram-v2\n  state A {\n    a --> b\n  }\n```").blocks
        guard case .diagram(_, let boxed) = composite.first else { return XCTFail("The state diagram with a composite state is a diagram block") }
        let drawnBoxed = try boxed.drawn(as: .stateDiagram)
        XCTAssertTrue(drawnBoxed.scene.shapes.contains { shape in shape.part == .cluster })
        XCTAssertEqual(drawnBoxed.accessibility.summary, ["A", "a", "b"])
    }

    func testAnXYChartBecomesADiagramBlockAndOneWithoutSeriesShowsWhy() async throws {
        let blocks = try await build("```mermaid\nxychart-beta\n  x-axis [a, b]\n  bar [1, 2]\n```").blocks
        guard case .diagram(_, let chart) = blocks.first else { return XCTFail("The XY chart is a diagram block") }
        XCTAssertEqual(try chart.drawn(as: .xyChart).accessibility.summary, ["Bars: a 1, b 2"])
        let empty = try await build("```mermaid\nxychart\n  title \"Nothing\"\n```").blocks
        guard case .diagram(_, .unreadable(_, let failure)) = empty.first else { return XCTFail("Shown with why") }
        XCTAssertEqual(failure, .xyChartLayout(.noSeries))
    }

    func testASankeyDiagramBecomesADiagramBlockAndOneWithCircularLinksShowsWhy() async throws {
        let blocks = try await build("```mermaid\nsankey-beta\nCoal,Solid,75.571\nSolid,Industry,46.477\n```").blocks
        guard case .diagram(_, let sankey) = blocks.first else { return XCTFail("The Sankey diagram is a diagram block") }
        XCTAssertEqual(try sankey.drawn(as: .sankey).accessibility.summary.count, 2)
        let circular = try await build("```mermaid\nsankey\na,b,1\nb,a,1\n```").blocks
        guard case .diagram(_, .unreadable(_, let failure)) = circular.first else { return XCTFail("Shown with why") }
        XCTAssertEqual(failure, .sankeyLayout(.circularLinks))
    }
}
