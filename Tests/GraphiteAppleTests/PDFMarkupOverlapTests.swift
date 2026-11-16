/**
 * File: PDFMarkupOverlapTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The rules for marking text a mark of the same kind is already on, with plain rectangles: a new mark,
 *              no change, a change of colour, or one mark joining the text and the marks it overlaps.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import CoreGraphics
import GraphiteApple

final class PDFMarkupOverlapTests: XCTestCase {
    /// One line of text 20 points high; a second line under it.
    private static func firstLine(from start: CGFloat, to end: CGFloat) -> CGRect { CGRect(x: start, y: 500, width: end - start, height: 20) }
    private static func secondLine(from start: CGFloat, to end: CGFloat) -> CGRect { CGRect(x: start, y: 478, width: end - start, height: 20) }

    private static func mark(_ lines: [CGRect], sameColor: Bool = false) -> PDFMarkupOverlap.ExistingMark {
        PDFMarkupOverlap.ExistingMark(lineBounds: lines, hasMarkingColor: sameColor)
    }

    func testTextWithNoMarkOnItGetsANewMark() {
        let lines = [Self.firstLine(from: 100, to: 180)]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: lines, over: []), .add(lineBounds: lines))
        let elsewhere = [Self.mark([Self.firstLine(from: 200, to: 260)]), Self.mark([Self.secondLine(from: 100, to: 180)])]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: lines, over: elsewhere), .add(lineBounds: lines),
                       "A mark further along the line, past a space, or on the next line is not touched.")
    }

    func testTextAMarkCoversInTheSameColourStaysAsItIs() {
        let existing = [Self.mark([Self.firstLine(from: 40, to: 300)], sameColor: true)]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 100, to: 180)], over: existing), .unchanged(markIndex: 0))
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 40, to: 300)], over: existing), .unchanged(markIndex: 0),
                       "The same text marked again is the same mark.")
    }

    func testTextAMarkCoversInAnotherColourRecoloursThatMark() {
        let existing = [Self.mark([Self.secondLine(from: 40, to: 300)]), Self.mark([Self.firstLine(from: 40, to: 300), Self.secondLine(from: 40, to: 60)])]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 100, to: 180)], over: existing), .recolor(markIndex: 1))
    }

    func testTextPartlyMarkedJoinsTheMarkIntoOneCoveringBoth() {
        let existing = [Self.mark([Self.firstLine(from: 40, to: 150)], sameColor: true)]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 120, to: 260)], over: existing),
                       .join(markIndices: [0], lineBounds: [Self.firstLine(from: 40, to: 260)]))
    }

    func testTextThatCoversAMarkJoinsIt() {
        let existing = [Self.mark([Self.firstLine(from: 120, to: 150)])]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 40, to: 260)], over: existing),
                       .join(markIndices: [0], lineBounds: [Self.firstLine(from: 40, to: 260)]))
    }

    func testTextRightAfterAMarkJoinsIt() {
        let existing = [Self.mark([Self.firstLine(from: 40, to: 100)])]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 100.5, to: 160)], over: existing),
                       .join(markIndices: [0], lineBounds: [Self.firstLine(from: 40, to: 160)]))
    }

    func testTextAcrossTwoMarksJoinsThemAllWithOneRectanglePerLine() {
        let existing = [
            Self.mark([Self.firstLine(from: 200, to: 300), Self.secondLine(from: 40, to: 80)]),
            Self.mark([Self.secondLine(from: 150, to: 300)]),
            Self.mark([CGRect(x: 40, y: 300, width: 100, height: 20)]),
        ]
        let outcome = PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 280, to: 320), Self.secondLine(from: 40, to: 160)], over: existing)
        XCTAssertEqual(outcome, .join(markIndices: [0, 1], lineBounds: [Self.firstLine(from: 200, to: 320), Self.secondLine(from: 40, to: 300)]),
                       "The mark lower on the page stays; the joined lines run top to bottom.")
    }

    func testTwoMarksStackedByAnOlderBuildAreJoinedIntoOne() {
        let line = Self.firstLine(from: 40, to: 300)
        let existing = [Self.mark([line], sameColor: true), Self.mark([line], sameColor: true)]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 100, to: 180)], over: existing),
                       .join(markIndices: [0, 1], lineBounds: [line]))
    }

    func testAMarkThatOnlyTouchesAJoinedMarkIsLeftAlone() {
        // Marks that already overlapped each other keep apart unless the new text reaches both.
        let existing = [Self.mark([Self.firstLine(from: 140, to: 200)]), Self.mark([Self.firstLine(from: 40, to: 150)])]
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 190, to: 260)], over: existing),
                       .join(markIndices: [0], lineBounds: [Self.firstLine(from: 140, to: 260)]))
    }

    func testLinesThatShareASliverOfHeightAreDifferentLines() {
        let tightLineUnder = CGRect(x: 40, y: 482, width: 260, height: 20)
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [Self.firstLine(from: 40, to: 300)], over: [Self.mark([tightLineUnder])]),
                       .add(lineBounds: [Self.firstLine(from: 40, to: 300)]))
    }

    func testTurnedTextRunsUpThePage() {
        // Two columns of text turned a quarter, side by side.
        let column = CGRect(x: 100, y: 40, width: 20, height: 200), nextColumn = CGRect(x: 118, y: 40, width: 20, height: 200)
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [nextColumn], over: [Self.mark([column])], runsVertically: true),
                       .add(lineBounds: [nextColumn]), "Upright, they would share their height and count as one line.")
        let lowerPart = CGRect(x: 100, y: 200, width: 20, height: 100)
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [lowerPart], over: [Self.mark([column])], runsVertically: true),
                       .join(markIndices: [0], lineBounds: [CGRect(x: 100, y: 40, width: 20, height: 260)]))
        XCTAssertEqual(PDFMarkupOverlap.outcome(ofMarking: [CGRect(x: 100, y: 60, width: 20, height: 50)], over: [Self.mark([column])], runsVertically: true),
                       .recolor(markIndex: 0))
    }
}
