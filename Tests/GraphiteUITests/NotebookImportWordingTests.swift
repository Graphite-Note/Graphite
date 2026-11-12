/**
 * File: NotebookImportWordingTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: What a notebook import's report says about the typed text it converts into text boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

import XCTest
import NotebookImport
@testable import GraphiteUI

final class NotebookImportWordingTests: XCTestCase {
    private func sentence(_ kind: ImportReportEntryKind, count: Int = 2) -> String {
        NotebookImportWording.line(ImportReportSummaryLine(kind: kind, totalCount: count, occurrenceCount: count, pageNumbers: [3]))
    }

    /// HUNT-219: the report said text was left out until Graphite had text on PDF pages, which it has. The import now
    /// converts text into text boxes, and the report says only what the boxes could not keep.
    func testLeftOutTextIsNotBlamedOnGraphiteLackingTextOnPDFPages() {
        let textLines = [sentence(.elementsNotYetConverted(.textWithoutFrame)), sentence(.textStylesNotKept), sentence(.fontsReplaced),
                         sentence(.stickyNotesAsTextBoxes), sentence(.textBoxesNotPlaced)]
        for line in textLines {
            XCTAssertFalse(line.contains("until Graphite has"), line)
            XCTAssertFalse(line.contains("does not convert"), line)
        }
        XCTAssertEqual(sentence(.stickyNotesAsTextBoxes, count: 1),
                       "Sticky notes made text boxes with their colour, without their author's name: 1 note, page 3.")
        XCTAssertEqual(NotebookImportWording.reason(.noPages), "The notebook has no page Graphite can import.")
    }
}
