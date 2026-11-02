/**
 * File: ReadingDiagramTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The reading view's mermaid blocks: flowcharts, unreadable diagrams, types not drawn yet.
 *
 * Authors: Félix Chevalier
 * Version: 0.8
 * Date: 01/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    func testAFlowchartIsLaidOutInTheNotesTextSize() throws {
        guard case .flowchart(let flowchart) = try XCTUnwrap(ReadingDiagram(source: "flowchart LR\n  A[Start] --> B{Done?}", typography: typography)) else {
            return XCTFail("A flowchart is drawn")
        }
        XCTAssertEqual(flowchart.layout.font.size, 17)
        XCTAssertEqual(flowchart.layout.nodes.count, 2)
        XCTAssertEqual(flowchart.nodeTexts, ["Start", "Done?"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let source = "---\ntitle: Front title\n---\nflowchart TD\naccDescr: How it goes\nA --> B"
        guard case .flowchart(let flowchart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { return XCTFail("Drawn") }
        XCTAssertEqual(flowchart.title, "Front title")
        XCTAssertEqual(flowchart.description, "How it goes")
        guard case .flowchart(let titled) = try XCTUnwrap(ReadingDiagram(source: "flowchart TD\naccTitle: Named\nA", typography: typography)) else {
            return XCTFail("Drawn")
        }
        XCTAssertEqual(titled.title, "Named")
    }

    /// HUNT-236: a type not drawn yet was a bare code block, with no word that the diagram was meant to be drawn.
    func testATypeNotDrawnYetShowsTheSourceAndSaysSo() {
        let source = "requirementDiagram\n  requirement test_req {\n  }"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("Shown with why") }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.unsupportedDiagramType(keyword: "requirementDiagram")))
        XCTAssertTrue(failure.explanation.contains("requirementDiagram"))
        XCTAssertTrue(failure.explanation.contains("not drawn yet"))
    }

    func testAFlowchartWithSubgraphsIsDrawnWithItsBoxes() throws {
        let source = "flowchart TD\nX --> one\nsubgraph one [The group]\nA --> B\nend"
        guard case .flowchart(let flowchart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("The flowchart is drawn")
        }
        XCTAssertEqual(flowchart.layout.clusters.count, 1)
        XCTAssertEqual(flowchart.layout.nodes.count, 3)
        XCTAssertEqual(flowchart.nodeTexts, ["X", "A", "B", "The group"], "The node standing for the group is its box, read by its title")
    }

    func testAFlowchartWhoseSubgraphsAreNotLaidOutShowsTheSourceAndWhy() {
        for source in ["flowchart TD\nsubgraph one\nA --> B\nend\none@{ view: collapsed }", "flowchart TD\nsubgraph one\nA\nend\nA --> one"] {
            guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("Shown with why") }
            XCTAssertEqual(shownSource, source)
            XCTAssertEqual(failure, .layout(.subgraphsNotLaidOut))
        }
    }

    func testAFlowchartThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "flowchart TD\nA[never closed"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedShape(closingText: "]"))))
    }

    func testEveryFailureIsExplained() {
        let failures: [ReadingDiagramFailure] = [
            .reading(.noDiagram), .reading(.sourceTooLarge(limitBytes: 1)), .reading(.unsupportedDiagramType(keyword: "pie")),
            .reading(.tooManyNodes(limit: 1)), .reading(.tooManyEdges(limit: 1)), .layout(.tooManyLayoutPoints(limit: 1)), .layout(.subgraphsNotLaidOut),
            .stateLayout(.tooManyLayoutPoints(limit: 1)), .stateLayout(.compositeStatesNotLaidOut),
        ] + [MermaidSyntaxProblem.unknownDirection("XY"), .expectedNode, .unclosedShape(closingText: "]"), .unclosedQuotation, .unclosedEdgeLabel,
             .unclosedAttributes, .unclosedAccessibilityDescription, .unclosedFrontMatter, .endWithoutSubgraph, .unclosedSubgraph(identifier: "one"),
             .unexpectedText("C"), .expectedState, .stateNameNotOneWord("two words"), .unclosedNote, .unclosedCompositeState(identifier: "one"),
             .closingBraceWithoutCompositeState].map { problem in .reading(.invalidSyntax(line: 1, problem: problem)) }
            + [.reading(.tooManyParticipants(limit: 1)), .reading(.tooManySequenceStatements(limit: 1))]
            + [SequenceSyntaxProblem.expectedParticipant, .expectedArrow, .expectedText, .expectedNotePlacement, .endWithoutBlock,
               .sectionOutsideItsBlock(keyword: "else"), .unclosedBlock(keyword: "loop"), .inactiveParticipantDeactivated(identifier: "Bob")]
                .map { problem in .reading(.invalidSyntax(line: 1, problem: .sequence(problem))) }
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
