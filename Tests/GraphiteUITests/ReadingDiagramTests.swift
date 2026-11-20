/**
 * File: ReadingDiagramTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The reading view's mermaid blocks: diagrams prepared for drawing, unreadable diagrams, types not drawn yet.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.10
 * Date: 20/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    func testAFlowchartIsLaidOutInTheNotesTextSize() throws {
        let flowchart = try ReadingDiagram(source: "flowchart LR\n  A[Start] --> B{Done?}", typography: typography).drawn(as: .flowchart)
        XCTAssertEqual(flowchart.scene.font.size, 17)
        XCTAssertEqual(flowchart.scene.lineTexts, ["Start", "Done?"])
        XCTAssertEqual(flowchart.accessibility.summary, ["Start", "Done?"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let source = "---\ntitle: Front title\n---\nflowchart TD\naccDescr: How it goes\nA --> B"
        let flowchart = try ReadingDiagram(source: source, typography: typography).drawn(as: .flowchart)
        XCTAssertEqual(flowchart.accessibility.label, "Front title")
        XCTAssertEqual(flowchart.accessibility.value, "How it goes")
        let titled = try ReadingDiagram(source: "flowchart TD\naccTitle: Named\nA", typography: typography).drawn(as: .flowchart)
        XCTAssertEqual(titled.accessibility.label, "Named")
        let untitled = try ReadingDiagram(source: "flowchart TD\nA --> B", typography: typography).drawn(as: .flowchart)
        XCTAssertEqual(untitled.accessibility.label, "Flowchart", "Without a title, the type's name")
        XCTAssertEqual(untitled.accessibility.value, "A, B")
    }

    /// HUNT-236: a type not drawn yet was a bare code block, with no word that the diagram was meant to be drawn.
    func testATypeNotDrawnYetShowsTheSourceAndSaysSo() {
        let source = "zenuml\n  Alice->Bob: Hi"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("Shown with why") }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.unsupportedDiagramType(keyword: "zenuml")))
        XCTAssertTrue(failure.explanation.contains("zenuml"))
        XCTAssertTrue(failure.explanation.contains("not drawn yet"))
    }

    func testAFlowchartWithSubgraphsIsDrawnWithItsBoxes() throws {
        let source = "flowchart TD\nX --> one\nsubgraph one [The group]\nA --> B\nend"
        let flowchart = try ReadingDiagram(source: source, typography: typography).drawn(as: .flowchart)
        XCTAssertTrue(flowchart.scene.shapes.contains { shape in shape.part == .cluster }, "The group is a box")
        XCTAssertEqual(flowchart.accessibility.summary, ["X", "A", "B", "The group"], "The node standing for the group is its box, read by its title")
    }

    func testAFlowchartWithACollapsedGroupOrAnEdgeIntoItsGroupIsDrawn() throws {
        for source in ["flowchart TD\nsubgraph one\nA --> B\nend\none@{ view: collapsed }", "flowchart TD\nsubgraph one\nA\nend\nA --> one"] {
            XCTAssertNil(ReadingDiagram(source: source, typography: typography).failure, source)
            XCTAssertNoThrow(try ReadingDiagram(source: source, typography: typography).drawn(as: .flowchart), source)
        }
    }

    func testAFlowchartThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "flowchart TD\nA[never closed"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedShape(closingText: "]"))))
    }

    func testEveryFailureIsExplained() {
        let failures: [MermaidDiagramPreparationFailure] = [
            .reading(.noDiagram), .reading(.sourceTooLarge(limitBytes: 1)), .reading(.unsupportedDiagramType(keyword: "pie")),
            .reading(.tooManyNodes(limit: 1)), .reading(.tooManyEdges(limit: 1)), .flowchartLayout(.tooManyLayoutPoints(limit: 1)),
            .flowchartLayout(.subgraphsNotLaidOut), .stateDiagramLayout(.tooManyLayoutPoints(limit: 1)), .stateDiagramLayout(.compositeStatesNotLaidOut),
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

    /// A refusal Graphite has no sentence of its own for, as a type the package adds later brings, is worded by its kind,
    /// so a new type needs nothing here to say why it is not drawn.
    func testEveryKindOfRefusalHasAWordingOfItsOwn() {
        let categories: [MermaidDiagramPreparationFailure.Category] = [.unreadable, .typeNotDrawn, .notDrawnYet, .beyondLimits, .refusedContent]
        XCTAssertEqual(Set(categories.map(\.explanation)).count, categories.count)
        XCTAssertEqual(MermaidDiagramPreparationFailure.flowchartLayout(.tooManyLayoutPoints(limit: 1)).explanation,
                       MermaidDiagramPreparationFailure.Category.beyondLimits.explanation)
    }

    /// Every type is drawn through the one preparation and the one painter: a sample of each is drawn, and the screen
    /// reader hears the type's name where the diagram has no title.
    func testEveryTypeIsDrawnThroughThePreparation() throws {
        for sample in ReadingDiagramSamples.oneOfEachType {
            let prepared = try ReadingDiagram(source: sample.source, typography: typography).drawn(as: sample.kind)
            XCTAssertFalse(prepared.scene.items.isEmpty, "\(sample.kind)")
            XCTAssertFalse(prepared.accessibility.label.isEmpty)
        }
    }
}
