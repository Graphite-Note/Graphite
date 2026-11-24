/**
 * File: PDFResizeZoomTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The zoom a PDF keeps across a resize, and the span its fitting zoom spreads across the view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import GraphiteUI

/// The zoom a PDF keeps across a resize (HUNT-378).
final class PDFResizeZoomTests: XCTestCase {
    func testTheFittedSpanIsTheWidestPageAsShownWithItsMargins() throws {
        // An A4 page upright, a landscape page and a narrow one: the landscape page is the widest.
        let span = try XCTUnwrap(PDFResizeZoom.fittedSpan(pageWidthsAsShown: [595.28, 841.89, 300], horizontalMargins: 8))
        XCTAssertEqual(span, 849.89, accuracy: 0.001)
        XCTAssertNil(PDFResizeZoom.fittedSpan(pageWidthsAsShown: [], horizontalMargins: 8))
        XCTAssertNil(PDFResizeZoom.fittedSpan(pageWidthsAsShown: [0], horizontalMargins: 8))
        XCTAssertEqual(PDFResizeZoom.fittedSpan(pageWidthsAsShown: [595.28], horizontalMargins: -4), 595.28)
    }

    func testAZoomThatFitsWithinTheToleranceIsLeftToPDFKitAndOneFurtherStays() {
        // Measured on an iPad simulator: PDFKit fitted 588 points at 0.97351, and the span is 603.28.
        let fitted = PDFResizeZoom(isScaledByPDFKit: false, scale: 0.97351, fittingScale: 588 / 603.28)
        XCTAssertTrue(fitted.fittedWidth)
        XCTAssertEqual(fitted.scaleAfterResize(fittingScale: 598 / 603.28), .fitsByPDFKit)

        let zoomedIn = PDFResizeZoom(isScaledByPDFKit: false, scale: 1.5, fittingScale: 1)
        XCTAssertFalse(zoomedIn.fittedWidth)
        guard case .scale(let scale) = zoomedIn.scaleAfterResize(fittingScale: 0.8) else { return XCTFail("A zoom past fitting keeps its own scale.") }
        XCTAssertEqual(scale, 1.2, accuracy: 0.0001)
    }
}
