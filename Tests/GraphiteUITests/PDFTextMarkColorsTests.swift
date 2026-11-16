/**
 * File: PDFTextMarkColorsTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The colours saved for text marks on the device: the standard ones at first, a colour added once and
 *              kept in order, removed, read back from what was saved, and offered for each kind with a mark's own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import GraphiteApple
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

final class PDFTextMarkColorsTests: XCTestCase {
    private let orange = PDFMarkupColor(redLevel: 0xFF, greenLevel: 0x80, blueLevel: 0)

    func testNothingSavedOrSomethingUnreadableGivesTheStandardColours() {
        XCTAssertEqual(PDFTextMarkColors(decoding: nil).colors, PDFMarkupColor.highlightColors)
        XCTAssertEqual(PDFTextMarkColors(decoding: Data("not a list".utf8)).colors, PDFMarkupColor.highlightColors)
    }

    func testAColourIsAddedOnceAtTheEndAndRemovedAndTheListReadsBackAsSaved() {
        let added = PDFTextMarkColors.standard.adding(orange).adding(orange)
        XCTAssertEqual(added.colors, PDFMarkupColor.highlightColors + [orange])
        let removed = added.removing(.green)
        XCTAssertEqual(PDFTextMarkColors(decoding: removed.encoded), removed)
        XCTAssertEqual(String(decoding: removed.encoded ?? Data(), as: UTF8.self), ##"["yellow","blue","pink","purple","#FF8000"]"##)
        XCTAssertEqual(PDFTextMarkColors.standard.removing(.yellow).removing(.green).removing(.blue).removing(.pink).removing(.purple).colors, [],
                       "Every colour can be removed; an empty list stays empty.")
        XCTAssertEqual(PDFTextMarkColors(decoding: PDFTextMarkColors(colors: []).encoded).colors, [])
    }

    func testTheListIsBounded() {
        let many = (0..<40).map { level in PDFMarkupColor(redLevel: UInt8(level), greenLevel: 0, blueLevel: 0) }
        XCTAssertEqual(PDFTextMarkColors(colors: many).colors.count, PDFTextMarkColors.maximumColorCount)
    }

    func testAColourIsSavedOnTheDevice() throws {
        let preferences = try IsolatedDeviceState.make(prefix: "PDFTextMarkColors", for: self).preferences
        PDFTextMarkColors.save(orange, in: preferences)
        XCTAssertEqual(PDFTextMarkColors(decoding: preferences.data(forKey: PDFAnnotationPreferenceKey.textMarkColors)).colors.last, orange)
    }

    func testEachKindIsOfferedItsColoursWithAMarksOwnColourFirst() {
        let saved = PDFTextMarkColors(colors: [.yellow, .green])
        XCTAssertEqual(saved.offered(for: .highlight), [.yellow, .green])
        XCTAssertEqual(saved.offered(for: .underline), [.red, .yellow, .green], "Underlines start red.")
        XCTAssertEqual(saved.offered(for: .highlight, including: orange), [orange, .yellow, .green], "Another application's colour shows.")
        XCTAssertEqual(saved.offered(for: .highlight, including: .green), [.yellow, .green])
    }
}
