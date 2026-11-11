/**
 * File: PDFMarkupStyleTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The highlight button's marks, the name each is kept under on the device, and what the menu offers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
import GraphiteApple
@testable import GraphiteUI

final class PDFMarkupStyleTests: XCTestCase {
    func testEveryStyleOfTheMenuIsKeptAndReadBackUnderItsName() {
        for style in PDFMarkupStyle.choices {
            XCTAssertEqual(PDFMarkupStyle(rawValue: style.rawValue), style, style.rawValue)
        }
        XCTAssertEqual(PDFMarkupStyle.highlight(.green).rawValue, "highlight-green")
        XCTAssertEqual(PDFMarkupStyle.underline.rawValue, "underline")
        XCTAssertEqual(PDFMarkupStyle.strikeOut.rawValue, "strikeOut")
    }

    func testANameNoStyleHasIsNotReadAsAStyle() {
        for name in ["", "highlight", "highlight-", "highlight-red", "highlight-orange", "Underline", "strikethrough"] {
            XCTAssertNil(PDFMarkupStyle(rawValue: name), name)
        }
    }

    func testTheMenuOffersTheHighlightColoursThenUnderlineAndStrikethrough() {
        XCTAssertEqual(PDFMarkupStyle.choices, PDFMarkupColor.highlightColors.map(PDFMarkupStyle.highlight) + [.underline, .strikeOut])
        XCTAssertEqual(PDFMarkupStyle.choices.map(\.title), ["Yellow", "Green", "Blue", "Pink", "Purple", "Underline", "Strikethrough"])
        XCTAssertEqual(PDFMarkupStyle.default, .highlight(.yellow))
    }

    func testUnderlineAndStrikethroughAreRedAsTheIPadMakesThem() {
        XCTAssertEqual(PDFMarkupStyle.highlight(.blue).kind, .highlight)
        XCTAssertEqual(PDFMarkupStyle.highlight(.blue).color, .blue)
        XCTAssertEqual(PDFMarkupStyle.underline.kind, .underline)
        XCTAssertEqual(PDFMarkupStyle.underline.color, .red)
        XCTAssertEqual(PDFMarkupStyle.strikeOut.kind, .strikeOut)
        XCTAssertEqual(PDFMarkupStyle.strikeOut.color, .red)
    }
}
