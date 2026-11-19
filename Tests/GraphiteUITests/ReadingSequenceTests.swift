/**
 * File: ReadingSequenceTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The reading view's sequence diagrams.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingSequenceTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func sequence(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .sequence)
    }

    func testASequenceDiagramIsLaidOutInTheNotesTextSize() throws {
        let sequence = try sequence("sequenceDiagram\n  participant A as Alice\n  A->>Bob: Hi")
        XCTAssertEqual(sequence.scene.font.size, 17)
        XCTAssertEqual(sequence.scene.lineTexts.filter { text in text == "Alice" }.count, 2, "Each participant above and below its lifeline.")
        XCTAssertEqual(sequence.accessibility.label, "Sequence diagram")
        XCTAssertTrue(sequence.accessibility.value.hasPrefix("Alice, Bob."), sequence.accessibility.value)
    }

    func testAccessibilityTextComesFromTheDiagramOrItsParticipantsAndMessages() throws {
        let described = try sequence("---\ntitle: Front title\n---\nsequenceDiagram\naccDescr: How it goes\nA->>B: Hi")
        XCTAssertEqual(described.accessibility.label, "Front title")
        XCTAssertEqual(described.accessibility.value, "How it goes")
        let titled = try sequence("sequenceDiagram\naccTitle: Named\ntitle Shown\nAlice->>Bob: Hello<br>there\nBob-->>Alice:")
        XCTAssertEqual(titled.accessibility.label, "Named")
        XCTAssertEqual(titled.accessibility.value, "Alice, Bob. Alice to Bob: Hello there. Bob to Alice")
    }

    func testADiagramWithStatementsNotLaidOutShowsTheSourceAndWhy() {
        for statement in ["box Team\nparticipant A\nend", "create participant C\nA->>C: Hi", "A-|\\B: Half", "link A: Wiki @ https://example.com",
                          "participant A@{ \"type\": \"database\" }", "A()->>B: Circle", "destroy A\nA->>B: Bye"] {
            guard case .unreadable(_, let failure) = ReadingDiagram(source: "sequenceDiagram\n\(statement)", typography: typography) else {
                XCTFail("Shown with why: \(statement)")
                continue
            }
            guard case .sequenceLayout(.statementsNotLaidOut(let statements)) = failure else { XCTFail("\(failure)"); continue }
            XCTAssertFalse(statements.isEmpty, statement)
            XCTAssertTrue(failure.explanation.hasSuffix("are not drawn yet."), failure.explanation)
        }
    }

    func testASequenceDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "sequenceDiagram\nloop forever\nA->>B: Hi"
        guard case .unreadable(let shownSource, let failure) = ReadingDiagram(source: source, typography: typography) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .sequence(.unclosedBlock(keyword: "loop")))))
    }
}
