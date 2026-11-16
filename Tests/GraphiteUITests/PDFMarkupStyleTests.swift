/**
 * File: PDFMarkupStyleTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The highlight button's marks, the name each is kept under on the device, and what the menu offers.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
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
        for name in ["", "highlight", "highlight-", "highlight-orange", "highlight-#12345", "underline-", "Underline", "strikethrough"] {
            XCTAssertNil(PDFMarkupStyle(rawValue: name), name)
        }
    }

    func testAMarkOfAnyColourIsKeptUnderItsHexText() throws {
        let orange = try XCTUnwrap(PDFMarkupColor(hex: "#ff8000"))
        let styles = [PDFMarkupStyle.highlight(orange), PDFMarkupStyle(kind: .underline, color: .blue), PDFMarkupStyle(kind: .strikeOut, color: orange),
                      PDFMarkupStyle.highlight(.red)]
        XCTAssertEqual(styles.map(\.rawValue), ["highlight-#FF8000", "underline-blue", "strikeOut-#FF8000", "highlight-red"])
        for style in styles { XCTAssertEqual(PDFMarkupStyle(rawValue: style.rawValue), style, style.rawValue) }
        XCTAssertEqual(PDFMarkupStyle(kind: .underline, color: .blue).title, "Underline Blue")
        XCTAssertEqual(PDFMarkupStyle.highlight(orange).title, "#FF8000")
    }

    func testTheMenuWithSavedColoursOffersThemThenUnderlineAndStrikethrough() throws {
        let orange = try XCTUnwrap(PDFMarkupColor(hex: "#FF8000"))
        XCTAssertEqual(PDFMarkupStyle.choices(highlightColors: [.green, orange]), [.highlight(.green), .highlight(orange), .underline, .strikeOut])
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
