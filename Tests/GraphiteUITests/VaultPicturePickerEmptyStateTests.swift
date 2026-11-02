/**
 * File: VaultPicturePickerEmptyStateTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: What the Picture from Vault list says while it is empty.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteUI

/// HUNT-220: Picture from Vault said "Type part of its name" when a search found nothing.
final class VaultPicturePickerEmptyStateTests: XCTestCase {
    func testNothingTypedAsksForAName() {
        XCTAssertEqual(VaultPicturePicker.emptyState(forQuery: "", searchedQuery: ""), .promptToType)
    }

    func testASearchThatFoundNothingSaysSo() {
        XCTAssertEqual(VaultPicturePicker.emptyState(forQuery: "board", searchedQuery: "board"), .noMatch("board"))
    }

    func testAQueryNotAnsweredYetIsNotShownAsNothingFound() {
        XCTAssertEqual(VaultPicturePicker.emptyState(forQuery: "board", searchedQuery: "boa"), .searching)
        XCTAssertEqual(VaultPicturePicker.emptyState(forQuery: "board", searchedQuery: nil), .searching)
    }
}
