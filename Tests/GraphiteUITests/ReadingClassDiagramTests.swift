/**
 * File: ReadingClassDiagramTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The reading view's class diagrams.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingClassDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func classDiagram(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .classDiagram)
    }

    func testAClassDiagramIsLaidOutInTheNotesTextSize() throws {
        let drawn = try classDiagram("classDiagram\n  class Square~Shape~\n  Animal <|-- Square")
        XCTAssertEqual(drawn.scene.font.size, 17)
        XCTAssertEqual(drawn.accessibility.summary, ["Square<Shape>", "Animal"])
        XCTAssertEqual(drawn.accessibility.value, "Square<Shape>, Animal")
        XCTAssertEqual(try classDiagram("classDiagram-v2\nclass A").accessibility.summary, ["A"])
    }

    /// Static members are underlined and abstract ones in italics, as Obsidian draws them.
    func testMembersKeepTheirStyle() throws {
        let drawn = try classDiagram("classDiagram\nclass Shape {\n  +String name\n  +count()$ int\n  +area()* double\n}")
        XCTAssertEqual(drawn.scene.texts(reading: "+area() : double").map(\.isItalic), [true])
        XCTAssertEqual(drawn.scene.texts(reading: "+String name").map(\.isItalic), [false])
        XCTAssertTrue(drawn.scene.texts(reading: "Shape").allSatisfy(\.isBold))
        XCTAssertTrue(drawn.scene.shapes.contains { shape in shape.part == .label && shape.painting == .stroke(.foreground, .rounded(lineWidth: 1)) },
                      "The static member is underlined.")
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try classDiagram("---\ntitle: Front title\n---\nclassDiagram\naccDescr: How it fits\nclass A")
        XCTAssertEqual(titled.accessibility.title, "Front title")
        XCTAssertEqual(titled.accessibility.description, "How it fits")
        XCTAssertEqual(try classDiagram("classDiagram\naccTitle: Named\nclass A").accessibility.label, "Named")
    }

    func testAClassDiagramWithNamespacesShowsTheSourceAndWhy() {
        let diagram = ReadingDiagram(source: "classDiagram\nnamespace Shapes {\n  class Triangle\n}", typography: typography)
        XCTAssertEqual(diagram.failure, .classDiagramLayout(.namespacesNotLaidOut))
    }

    func testAClassDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "classDiagram\nclass A {\n  +never closed"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedClassBody(identifier: "A"))))
    }

    func testEveryClassDiagramFailureIsExplainedApartFromTheOthers() {
        let earlier: [MermaidDiagramPreparationFailure] = [
            .reading(.noDiagram), .flowchartLayout(.tooManyLayoutPoints(limit: 1)), .flowchartLayout(.subgraphsNotLaidOut),
            .reading(.invalidSyntax(line: 1, problem: .unclosedShape(closingText: "]"))), .reading(.invalidSyntax(line: 1, problem: .unexpectedText("C"))),
        ]
        let classFailures: [MermaidDiagramPreparationFailure] = [.classDiagramLayout(.tooManyLayoutPoints(limit: 1)), .classDiagramLayout(.namespacesNotLaidOut)]
            + [MermaidSyntaxProblem.expectedName, .expectedRelationLine, .expectedQuotedText, .unclosedClassBody(identifier: "A"),
               .unclosedNamespace(identifier: "N"), .unclosedGenericType, .unclosedAnnotation].map { problem in
                .reading(.invalidSyntax(line: 1, problem: problem))
            }
        let explanations = (earlier + classFailures).map(\.explanation)
        XCTAssertEqual(Set(explanations).count, explanations.count)
    }
}
