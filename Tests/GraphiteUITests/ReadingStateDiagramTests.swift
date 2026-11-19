/**
 * File: ReadingStateDiagramTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The reading view's state diagrams.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

/// A ```mermaid block holding a state diagram, as the reading view builds it.
final class ReadingStateDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func stateDiagram(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .stateDiagram)
    }

    func testAStateDiagramIsLaidOutInTheNotesTextSize() throws {
        for keyword in ["stateDiagram", "stateDiagram-v2"] {
            let diagram = try stateDiagram("\(keyword)\n  [*] --> Still\n  Still --> Moving : push\n  Moving --> [*]")
            XCTAssertEqual(diagram.scene.font.size, 17)
            XCTAssertEqual(diagram.accessibility.summary, ["Still", "Moving"])
            XCTAssertEqual(diagram.scene.texts(reading: "push").count, 1)
        }
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try stateDiagram("---\ntitle: Front title\n---\nstateDiagram-v2\naccDescr: How it goes\n[*] --> A")
        XCTAssertEqual(titled.accessibility.title, "Front title")
        XCTAssertEqual(titled.accessibility.description, "How it goes")
        XCTAssertEqual(try stateDiagram("stateDiagram-v2\naccTitle: Named\nA").accessibility.label, "Named")
        XCTAssertNil(try stateDiagram("stateDiagram-v2\nA").accessibility.description)
    }

    func testAStateDiagramWithCompositeStatesIsDrawnWithItsBoxesAndItsNamesAreSpoken() throws {
        let diagram = try stateDiagram("stateDiagram-v2\n[*] --> Active\nstate Active {\n  [*] --> On\n  --\n  [*] --> Off\n}")
        XCTAssertTrue(diagram.scene.shapes.contains { shape in shape.part == .cluster }, "The composite state is a box.")
        XCTAssertEqual(diagram.accessibility.summary, ["Active", "On", "Off"])
    }

    func testAStateDiagramWhoseCompositeCannotBeLaidOutShowsTheSourceAndWhy() {
        for source in ["stateDiagram-v2\nstate First {\n  [*] --> second\n}\nFirst --> First", "stateDiagram-v2\nstate First {\n  a\n}\nnote left of First: aside"] {
            guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("Shown with why") }
            XCTAssertEqual(shownSource, source)
            XCTAssertEqual(failure, .stateDiagramLayout(.compositeStatesNotLaidOut))
            XCTAssertTrue(failure.explanation.hasSuffix("are not drawn yet."), failure.explanation)
        }
    }

    func testAStateDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "stateDiagram-v2\nA\nnote right of A\nnever ended"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .unclosedNote)))
    }
}
