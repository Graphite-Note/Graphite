/**
 * File: PDFMarkupToolbarTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The Mac markup row's tool, shown and hidden, and what letting go of the mouse does with each tool.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
@testable import GraphiteUI

@MainActor
final class PDFMarkupToolbarTests: XCTestCase {
    func testTheRowStartsHiddenWithTextSelection() {
        let toolbar = PDFMarkupToolbar()
        XCTAssertFalse(toolbar.isRowShown)
        XCTAssertEqual(toolbar.tool, .textSelection)
        XCTAssertFalse(toolbar.hasTextSelection)
    }

    func testHidingTheRowPutsTheHighlighterDown() {
        let toolbar = PDFMarkupToolbar()
        toolbar.toggleRow()
        toolbar.choose(.highlight)
        XCTAssertEqual(toolbar.tool, .highlight)

        toolbar.toggleRow()
        XCTAssertFalse(toolbar.isRowShown)
        XCTAssertEqual(toolbar.tool, .textSelection, "A hidden row never leaves the highlighter on.")

        toolbar.toggleRow()
        XCTAssertEqual(toolbar.tool, .textSelection, "Shown again, the row starts with text selection.")
    }

    func testChoosingAToolShowsTheRow() {
        let toolbar = PDFMarkupToolbar()
        toolbar.choose(.highlight)
        XCTAssertTrue(toolbar.isRowShown)
        XCTAssertEqual(toolbar.tool, .highlight)
    }

    func testTheSelectionIsReportedForTheMenuBar() {
        let toolbar = PDFMarkupToolbar()
        toolbar.textSelectionChanged(hasText: true)
        XCTAssertTrue(toolbar.hasTextSelection)
        toolbar.textSelectionChanged(hasText: false)
        XCTAssertFalse(toolbar.hasTextSelection)
    }

    func testOnlyTheHighlighterMarksTextWhenTheMouseIsLetGo() {
        let green = PDFMarkupStyle.highlight(.green)
        XCTAssertNil(PDFMarkupTool.textSelection.styleToApplyOnMouseUp(style: green, selectionHasText: true, clickChoseExistingMark: false))
        XCTAssertEqual(PDFMarkupTool.highlight.styleToApplyOnMouseUp(style: green, selectionHasText: true, clickChoseExistingMark: false), green)
        XCTAssertEqual(PDFMarkupTool.highlight.styleToApplyOnMouseUp(style: .underline, selectionHasText: true, clickChoseExistingMark: false), .underline)
        XCTAssertNil(PDFMarkupTool.highlight.styleToApplyOnMouseUp(style: green, selectionHasText: false, clickChoseExistingMark: false),
                     "A click without a selection marks nothing.")
        XCTAssertNil(PDFMarkupTool.highlight.styleToApplyOnMouseUp(style: green, selectionHasText: true, clickChoseExistingMark: true),
                     "A click that selected a mark does not mark its text again.")
    }
}
