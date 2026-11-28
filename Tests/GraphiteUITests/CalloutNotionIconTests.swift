/**
 * File: CalloutNotionIconTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: A callout titled with one emoji (`> [!tip] 💡`) is drawn as Notion draws its callouts: the emoji before
 *              the body and no title row, in the type's tint, as one whose title `no-title` hid shows its type's glyph. A
 *              foldable one, and any other title, keep the title row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class CalloutNotionIconTests: XCTestCase {
    /// The callouts here draw no file of a vault.
    private let root = URL(fileURLWithPath: "/")

    private func drawnHeight(title: String, folding: CalloutFolding = .notFoldable) throws -> CGFloat {
        let view = CalloutView(type: "tip", title: title, folding: folding, root: root, textSize: 16, navigate: { _, _ in }) {
            Text("Office hours on Tuesdays.").font(.system(size: 16))
        }
        .frame(width: 400)
        let renderer = ImageRenderer(content: view)
        return CGFloat(try XCTUnwrap(renderer.cgImage).height) / renderer.scale
    }

    func testAnEmojiTitleIsDrawnBesideTheBodyWithoutATitleRow() throws {
        let titled = try drawnHeight(title: "Office hours")
        let notion = try drawnHeight(title: "💡")
        XCTAssertLessThan(notion, titled - 16, "No title row: one line of body, not a title and a body (\(notion) against \(titled)).")
        XCTAssertGreaterThanOrEqual(notion, 16 + 24, "The body's line and the box's padding.")
    }

    func testAHiddenTitleShowsTheTypesGlyphBesideTheBody() throws {
        let hidden = try drawnHeight(title: ""), titled = try drawnHeight(title: "Office hours")
        XCTAssertLessThan(hidden, titled - 16, "No title row: one line of body with the glyph beside it (\(hidden) against \(titled)).")
    }

    func testAFoldableOneAndOtherTitlesKeepTheTitleRow() throws {
        let titled = try drawnHeight(title: "Office hours")
        XCTAssertEqual(try drawnHeight(title: "💡 Office hours"), titled, accuracy: 2)
        XCTAssertGreaterThan(try drawnHeight(title: "💡", folding: .expanded), titled - 4, "A fold needs its title row.")
    }
}
