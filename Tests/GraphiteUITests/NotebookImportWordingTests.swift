/**
 * File: NotebookImportWordingTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: What a notebook import's report says about the text it does not convert.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import NotebookImport
@testable import GraphiteUI

final class NotebookImportWordingTests: XCTestCase {
    private func sentence(leaving kind: ImportElementKind) -> String {
        NotebookImportWording.line(ImportReportSummaryLine(kind: .elementsNotYetConverted(kind), totalCount: 2, occurrenceCount: 2, pageNumbers: [3]))
    }

    /// HUNT-219: the report said text was left out until Graphite had text on PDF pages, which it has.
    func testLeftOutTextIsNotBlamedOnGraphiteLackingTextOnPDFPages() {
        for kind in [ImportElementKind.textBox, .stickyNote, .typedText] {
            let line = sentence(leaving: kind)
            XCTAssertTrue(line.contains("does not convert"), line)
            XCTAssertFalse(line.contains("until Graphite has"), line)
        }
        XCTAssertEqual(sentence(leaving: .textBox), "Text boxes left out, as the import does not convert them yet: 2 text boxes, page 3.")
        XCTAssertFalse(NotebookImportWording.reason(.noPages).contains("waits for text on PDF pages"))
    }
}
