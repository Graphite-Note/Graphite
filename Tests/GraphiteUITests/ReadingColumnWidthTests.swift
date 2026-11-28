/**
 * File: ReadingColumnWidthTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The reading view's readable column, the Live Preview column it lines up with, and a vault theme's line width.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import XCTest
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore
@testable import GraphiteUI

/// The reading view's column and the Live Preview column it must line up with: 730 points of
/// text with at least 33 points beside it, against the editor's 740-point column and the
/// 5-point padding of its text container and 28-point inset.
@MainActor
final class ReadingColumnWidthTests: XCTestCase {
    func testTheReadingColumnIsSevenHundredThirtyPointsWithAtLeastThirtyThreeBesideIt() {
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth, 730)
        XCTAssertEqual(ReadingConfiguration.minimumHorizontalMargin, 33)
    }

    func testTheReadingColumnIsTheEditorsColumnLessTheTextContainersPaddingOnBothSides() {
        let textContainerPadding = NSTextContainer().lineFragmentPadding
        XCTAssertEqual(textContainerPadding, 5)
        #if os(macOS)
        XCTAssertEqual(MarkdownMacTextView.graphiteReadableColumnWidth, 740)
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth, MarkdownMacTextView.graphiteReadableColumnWidth - 2 * textContainerPadding)
        XCTAssertEqual(MarkdownMacTextView.minimumHorizontalInset, 32, "The Mac editor's inset is 32, not the 28 of the iPad editor the reading margin follows.")
        #endif
        #if canImport(UIKit)
        XCTAssertEqual(MarkdownTextView.readableColumnWidth, 740)
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth, MarkdownTextView.readableColumnWidth - 2 * textContainerPadding)
        XCTAssertEqual(MarkdownTextView.minimumHorizontalInset, 28)
        XCTAssertEqual(ReadingConfiguration.minimumHorizontalMargin, MarkdownTextView.minimumHorizontalInset + textContainerPadding)
        #endif
    }

    func testAThemesLineWidthIsScaledByTheTextSizeOverSixteenAndNeverBelowAnElevenPointText() {
        var light = ThemeModeTokens()
        light.lineWidth = 640
        let style = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: light, dark: ThemeModeTokens()))
        XCTAssertEqual(style.readableColumnWidth(forTextSize: 16), 640)
        XCTAssertEqual(style.readableColumnWidth(forTextSize: 17), 640 * 17 / 16)
        XCTAssertEqual(style.readableColumnWidth(forTextSize: 8), 640 * 11 / 16, "A very small text size is treated as 11.")
        let withoutWidth = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: ThemeModeTokens(), dark: ThemeModeTokens()))
        XCTAssertNil(withoutWidth.readableColumnWidth(forTextSize: 16), "Without a theme width the reading view keeps its 730 points.")
    }

    // MARK: Zooming with the text

    func testTheZoomIsTheTextSizeOverSixteenNeverBelowElevenPoints() {
        XCTAssertEqual(NoteFontSize.zoomScale(forTextSize: 16), 1)
        XCTAssertEqual(NoteFontSize.zoomScale(forTextSize: 24), 1.5)
        XCTAssertEqual(NoteFontSize.zoomScale(forTextSize: 8), 11.0 / 16, "A very small text size is treated as 11, as a theme's column is.")
        XCTAssertEqual(NoteFontSize.zoomScale(forTextSize: .infinity), 1, "A size that is not a number does not zoom.")
        XCTAssertEqual(NoteFontSize.zoomScale(forTextSize: .nan), 1)
    }

    /// ⌘+ grew the text and left the column, and the pictures as wide as it, as they were.
    func testGraphitesColumnGrowsAndShrinksWithTheText() {
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth(forTextSize: 16), 730)
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth(forTextSize: 24), 1_095)
        XCTAssertEqual(ReadingConfiguration.readableColumnWidth(forTextSize: 12), 547.5)
    }

    func testTheEditorsColumnIsTheReadingColumnAtThisSizeAndTheTextContainersPadding() {
        var configuration = EditorConfiguration()
        configuration.textSize = 16
        XCTAssertEqual(configuration.readableColumnWidth, 740)
        #if os(macOS)
        XCTAssertEqual(configuration.readableColumnWidth, MarkdownMacTextView.graphiteReadableColumnWidth)
        #else
        XCTAssertEqual(configuration.readableColumnWidth, MarkdownTextView.readableColumnWidth)
        #endif
        XCTAssertEqual(EditorConfiguration.textContainerPadding, NSTextContainer().lineFragmentPadding)
        configuration.textSize = 20
        XCTAssertEqual(configuration.readableColumnWidth, 730 * 20 / 16 + 10, "Zoomed, the text lines up with the reading view's; the padding stays 5 points.")
        var light = ThemeModeTokens()
        light.lineWidth = 640
        configuration.theme = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: light, dark: ThemeModeTokens()))
        XCTAssertEqual(configuration.readableColumnWidth, 640 * 20 / 16 + 10, "The theme's width at this size, and 5 points each side.")
    }
}
