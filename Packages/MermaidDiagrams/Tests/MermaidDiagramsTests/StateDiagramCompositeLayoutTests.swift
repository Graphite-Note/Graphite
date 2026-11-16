/**
 * File: StateDiagramCompositeLayoutTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Composite states laid out as boxes around their states, nested, in their own direction, and with
 *              their concurrent regions side by side between dashed lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class StateDiagramCompositeLayoutTests: XCTestCase {
    private func layout(_ source: String) throws -> StateDiagramLayout {
        try StateDiagramUniformLayout.layout(source)
    }

    private func frame(of name: String, in layout: StateDiagramLayout) throws -> CGRect {
        try XCTUnwrap(layout.states.first { state in state.name?.lines == [name] }, name).frame
    }

    func testACompositeIsABoxAroundItsStatesWithItsNameAlongItsTopAndIsNotDrawnAsAState() throws {
        let laidOut = try layout("stateDiagram-v2\n[*] --> Draft\nstate Review {\n  [*] --> Screening\n  Screening --> Decision\n}\nDraft --> Review\nReview --> [*]")
        XCTAssertEqual(laidOut.composites.count, 1)
        let box = laidOut.composites[0]
        XCTAssertEqual(box.title?.lines, ["Review"])
        XCTAssertEqual(box.depth, 0)
        XCTAssertNil(laidOut.states.first { state in state.name?.lines == ["Review"] }, "The composite is its box, not a state's box too.")
        for name in ["Screening", "Decision"] { XCTAssertTrue(box.frame.contains(try frame(of: name, in: laidOut)), name) }
        XCTAssertFalse(box.frame.intersects(try frame(of: "Draft", in: laidOut)))
        let title = try XCTUnwrap(box.title)
        XCTAssertTrue(box.frame.contains(title.frame))
        XCTAssertLessThan(title.frame.maxY, try frame(of: "Screening", in: laidOut).minY, "The name is in a band above the box's states.")
        // The start inside the box is the box's own, a second start of the diagram.
        XCTAssertEqual(laidOut.states.filter { state in state.kind == .start }.count, 2)
        XCTAssertEqual(laidOut.states.filter { state in state.kind == .start && box.frame.contains(state.frame) }.count, 1)
    }

    func testATransitionToACompositeEndsOnItsBoxAndOneFromItLeavesIt() throws {
        let laidOut = try layout("stateDiagram-v2\nDraft --> Review\nstate Review {\n  Screening --> Decision\n}\nReview --> Published")
        let box = try XCTUnwrap(laidOut.composites.first).frame
        let arriving = laidOut.transitions[0], leaving = laidOut.transitions[2]
        XCTAssertEqual(arriving.arrow.tip.y, box.minY, accuracy: 0.5, "The arrow stops on the box's top.")
        XCTAssertEqual(leaving.path.start.y, box.maxY, accuracy: 0.5, "The line leaves from the box's bottom.")
        XCTAssertLessThan(try frame(of: "Draft", in: laidOut).maxY, box.minY)
        XCTAssertGreaterThan(try frame(of: "Published", in: laidOut).minY, box.maxY)
    }

    func testNestedCompositesAreBoxesInsideBoxesOneDepthDeeperEach() throws {
        let laidOut = try layout("stateDiagram-v2\n[*] --> First\nstate First {\n  [*] --> Second\n  state Second {\n    [*] --> second\n"
                                 + "    second --> Third\n    state Third {\n      [*] --> third\n      third --> [*]\n    }\n  }\n}")
        XCTAssertEqual(laidOut.composites.map(\.depth), [0, 1, 2])
        XCTAssertEqual(laidOut.composites.map { box in box.title?.lines ?? [] }, [["First"], ["Second"], ["Third"]])
        XCTAssertTrue(laidOut.composites[0].frame.contains(laidOut.composites[1].frame))
        XCTAssertTrue(laidOut.composites[1].frame.contains(laidOut.composites[2].frame))
        XCTAssertTrue(laidOut.composites[2].frame.contains(try frame(of: "third", in: laidOut)))
        XCTAssertFalse(laidOut.composites[2].frame.contains(try frame(of: "second", in: laidOut)))
    }

    func testACompositeRunsInItsOwnDirection() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B\nB --> C\nstate B {\n  direction LR\n  a --> b\n}")
        let first = try frame(of: "a", in: laidOut), second = try frame(of: "b", in: laidOut)
        XCTAssertEqual(first.midY, second.midY, accuracy: 0.5, "Inside the box the states run across.")
        XCTAssertLessThan(first.maxX, second.minX)
        XCTAssertLessThan(try frame(of: "A", in: laidOut).maxY, laidOut.composites[0].frame.minY, "Outside it they run down.")
    }

    func testConcurrentRegionsSitSideBySideBetweenDashedLines() throws {
        let laidOut = try layout("stateDiagram-v2\n[*] --> Active\nstate Active {\n  [*] --> NumOff\n  NumOff --> NumOn\n  --\n"
                                 + "  [*] --> CapsOff\n  CapsOff --> CapsOn\n  --\n  [*] --> ScrollOff\n  ScrollOff --> ScrollOn\n}")
        let box = try XCTUnwrap(laidOut.composites.first).frame
        XCTAssertEqual(laidOut.regionDividers.count, 2)
        let columns = try ["NumOff", "CapsOff", "ScrollOff"].map { name in try frame(of: name, in: laidOut) }
        let dividerXs = laidOut.regionDividers.map(\.start.x).sorted()
        XCTAssertLessThan(columns[0].maxX, dividerXs[0])
        XCTAssertGreaterThan(columns[1].minX, dividerXs[0])
        XCTAssertLessThan(columns[1].maxX, dividerXs[1])
        XCTAssertGreaterThan(columns[2].minX, dividerXs[1])
        for divider in laidOut.regionDividers {
            guard case .line(let end) = divider.segments.first else { return XCTFail("A divider is a straight line.") }
            XCTAssertEqual(end.x, divider.start.x, "A divider runs down between regions side by side.")
            XCTAssertTrue(box.contains(divider.start) && box.contains(end))
        }
    }

    func testTheReaderKeepsTheRegionEachStateIsNamedIn() throws {
        let diagram = try StateDiagramReading.stateDiagram("stateDiagram-v2\nstate Active {\n  a --> b\n  --\n  c --> d\n}\nOutside")
        let regions = Dictionary(uniqueKeysWithValues: diagram.states.map { state in (state.identifier, state.regionIndex) })
        XCTAssertEqual(regions["a"], 0)
        XCTAssertEqual(regions["b"], 0)
        XCTAssertEqual(regions["c"], 1)
        XCTAssertEqual(regions["d"], 1)
        XCTAssertEqual(regions["Outside"], 0)
        XCTAssertEqual(diagram.composites.first?.regionCount, 2)
    }

    func testACompositeInsideItselfThroughItsStatesIsRefused() throws {
        XCTAssertThrowsError(try layout("stateDiagram-v2\nstate A {\n  B\n}\nstate B {\n  A\n}")) { error in
            XCTAssertEqual(error as? StateDiagramLayoutError, .compositeStatesNotLaidOut)
        }
    }

    func testTheDrawingPartsPaintTheBoxesAndTheDividers() throws {
        let laidOut = try layout("stateDiagram-v2\nstate Active {\n  a --> b\n  --\n  c --> d\n}")
        let parts = StateDiagramDrawingParts(layout: laidOut)
        XCTAssertEqual(parts.composites.fillsByDepth.count, 1)
        XCTAssertFalse(parts.composites.outlines.isEmpty)
        XCTAssertEqual(parts.composites.titles.count + parts.composites.crossedTitles.count, 1)
        XCTAssertFalse(parts.regionDividers.isEmpty)
    }

    func testTurnedToRunDownTurnsTheDiagramAndItsComposites() throws {
        let diagram = try StateDiagramReading.stateDiagram("stateDiagram\ndirection LR\nA --> B\nstate B {\n  direction LR\n  a --> b\n}")
        let turned = try XCTUnwrap(diagram.turnedToRunDown)
        XCTAssertEqual(turned.direction, .topToBottom)
        XCTAssertEqual(turned.composites.first?.direction, .topToBottom)
        XCTAssertNil(try StateDiagramReading.stateDiagram("stateDiagram\nA --> B").turnedToRunDown, "Nothing to turn in a diagram that runs down.")
        let wide = try StateDiagramUniformLayout.layout("stateDiagram\ndirection LR\nA --> B\nB --> C\nC --> D")
        let narrow = try StateDiagramLayoutEngine.layout(try XCTUnwrap(try StateDiagramReading.stateDiagram("stateDiagram\ndirection LR\nA --> B\nB --> C\nC --> D")
            .turnedToRunDown), nameText: UniformWidthTextMeasurer(), smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                                         font: UniformWidthLayout.font, limits: .standard)
        XCTAssertLessThan(narrow.size.width, wide.size.width)
    }
}
