/**
 * File: ReadingEntityRelationshipDiagramTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The reading view's entity relationship diagrams.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingEntityRelationshipDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func drawn(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .entityRelationship)
    }

    func testAnEntityRelationshipDiagramIsLaidOutInTheNotesTextSize() throws {
        let diagram = try drawn("erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER {\n    int id PK\n  }")
        XCTAssertEqual(diagram.scene.font.size, 17)
        XCTAssertEqual(Array(diagram.accessibility.summary.prefix(2)), ["CUSTOMER", "ORDER"])
        XCTAssertEqual(diagram.scene.texts(reading: "id").count, 1, "The attribute's row is drawn.")
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try drawn("---\ntitle: Orders\n---\nerDiagram\naccDescr: Who orders what\nA")
        XCTAssertEqual(titled.accessibility.title, "Orders")
        XCTAssertEqual(titled.accessibility.description, "Who orders what")
        XCTAssertEqual(try drawn("erDiagram\naccTitle: Named\nA").accessibility.label, "Named")
        let summarized = try drawn("erDiagram\nc[CUSTOMER] {\n string name\n}\nc ||--o{ ORDER : places\nORDER ||--|| INVOICE : \"\"")
        XCTAssertNil(summarized.accessibility.description)
        XCTAssertEqual(summarized.accessibility.summary, ["CUSTOMER", "ORDER", "INVOICE", "CUSTOMER places ORDER", "ORDER INVOICE"])
    }

    func testADiagramWithSubgraphsShowsTheSourceAndWhy() {
        XCTAssertEqual(ReadingDiagram(source: "erDiagram\nsubgraph group\nA\nend", typography: typography).failure, .entityRelationshipLayout(.subgraphsNotLaidOut))
    }

    func testADiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "erDiagram\nCUSTOMER {\n string name"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedAttributeBlock(entity: "CUSTOMER"))))
    }

    func testEveryEntityRelationshipFailureIsExplained() {
        let failures: [MermaidDiagramPreparationFailure] = [
            .entityRelationshipLayout(.tooManyLayoutPoints(limit: 1)), .entityRelationshipLayout(.subgraphsNotLaidOut),
        ] + [MermaidSyntaxProblem.expectedRelationshipLine, .expectedCardinality, .expectedRelationshipLabel, .expectedAttribute,
             .unclosedAttributeBlock(entity: "BOOK")].map { problem in .reading(.invalidSyntax(line: 1, problem: problem)) }
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
        XCTAssertEqual(MermaidDiagramPreparationFailure.entityRelationshipLayout(.subgraphsNotLaidOut).explanation,
                       "Entity relationship diagrams with subgraphs are not drawn yet.")
        XCTAssertEqual(MermaidDiagramPreparationFailure.entityRelationshipLayout(.tooManyLayoutPoints(limit: 1)).explanation,
                       "This diagram is too large to lay out.", "Worded by its kind, as it was")
    }
}
