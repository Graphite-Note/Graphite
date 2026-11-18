/**
 * File: PDFViewDocumentAnalysisTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The switch that keeps PDFKit's page analysis out of embedded PDF views (HUNT-366).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
import PDFKit
@testable import GraphiteUI

@MainActor
final class PDFViewDocumentAnalysisTests: XCTestCase {
    /// PDFKit analyses the pages of a new view; turned off, it does not. This PDFKit has the switch, so the test fails if a
    /// later PDFKit renames it and embedded views would analyse their pages again.
    func testTheAnalysisIsOnInANewViewAndOffOnceTurnedOff() {
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        XCTAssertEqual(PDFViewDocumentAnalysis.isOn(in: view), true)
        PDFViewDocumentAnalysis.turnOff(in: view)
        XCTAssertEqual(PDFViewDocumentAnalysis.isOn(in: view), false)
    }
}
