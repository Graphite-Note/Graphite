/**
 * File: CalloutIconTitleTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A callout title that is one emoji alone is the Notion icon the importer writes; any other title is not.
 *              A `no-title` callout over a body has no title; a native callout without a title keeps its type's name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
@testable import GraphiteCore

final class CalloutIconTitleTests: XCTestCase {
    func testATitleOfOneEmojiIsAnIcon() {
        for title in ["💡", " 💡 ", "⚠️", "1️⃣", "👍🏽", "👩‍🔬", "🇨🇭"] {
            XCTAssertEqual(CalloutIconTitle.emoji(in: title), title.trimmingCharacters(in: .whitespaces), title)
        }
    }

    func testOtherTitlesAreNot() {
        for title in ["", "Tip", "💡 Tip", "💡💡", "1", "#", "©", "*"] {
            XCTAssertNil(CalloutIconTitle.emoji(in: title), title)
        }
    }

    func testNoTitleIsAMetadataWordAmongOthers() {
        XCTAssertTrue(CalloutIconTitle.hidesTitle(metadata: "no-title"))
        XCTAssertTrue(CalloutIconTitle.hidesTitle(metadata: "wide-2 No-Title"))
        XCTAssertTrue(CalloutIconTitle.hidesTitle(metadata: "wide-2,no-title"))
        XCTAssertFalse(CalloutIconTitle.hidesTitle(metadata: ""))
        XCTAssertFalse(CalloutIconTitle.hidesTitle(metadata: "no-titles wide-2"))
    }

    func testANoTitleCalloutOverABodyHasNoTitleAndANativeOneKeepsItsTypesName() {
        func title(_ note: String) -> String? {
            guard case .callout(_, let title, _, _) = NotePreviewDocument.blocks(from: note).first else { return nil }
            return title
        }
        XCTAssertEqual(title("> [!info|no-title]\n> Office hours on Tuesdays."), "")
        XCTAssertEqual(title("> [!info|wide-2 no-title] Written\n> Body."), "", "Hidden even when written, as the themes hide it.")
        XCTAssertEqual(title("> [!info]\n> Office hours on Tuesdays."), "Info", "A native callout without a title is titled by its type.")
        XCTAssertEqual(title("> [!info|no-title]"), "Info", "Without a body, the title shows.")
        XCTAssertEqual(title("> [!info|no-title]-\n> Body."), "Info", "A foldable one keeps the row it folds by.")
    }
}
