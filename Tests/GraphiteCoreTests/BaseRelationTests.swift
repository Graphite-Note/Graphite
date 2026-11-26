/**
 * File: BaseRelationTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: What a relation property is in a base, how many notes it takes and what choosing notes writes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseRelationTests: XCTestCase {
    func testAPropertyIsARelationWhenItsValueOrMostOfTheVaultsValuesAreLinksToNotes() {
        XCTAssertTrue(BaseRelation.isRelation(value: .list([.link(BaseLink(target: "VLSI 3"))]), vaultValues: []))
        XCTAssertTrue(BaseRelation.isRelation(value: .null, vaultValues: ["[[VLSI 3]]", "[[Computer Architecture]]", "draft"]))
        XCTAssertFalse(BaseRelation.isRelation(value: .null, vaultValues: ["draft", "[[VLSI 3]]"]))
        XCTAssertFalse(BaseRelation.isRelation(value: .link(BaseLink(target: "https://example.com")), vaultValues: []))
        XCTAssertFalse(BaseRelation.isRelation(value: .string("open"), vaultValues: []))
    }

    func testTheShapeFollowsTheDeclaredTypeThenTheValue() {
        XCTAssertEqual(BaseRelation.shape(declaredType: .text, value: .list([])), .single)
        XCTAssertEqual(BaseRelation.shape(declaredType: .multitext, value: .link(BaseLink(target: "A"))), .list)
        XCTAssertEqual(BaseRelation.shape(declaredType: nil, value: .link(BaseLink(target: "A"))), .single)
        XCTAssertEqual(BaseRelation.shape(declaredType: nil, value: .null), .list)
        XCTAssertEqual(BaseRelation.shape(declaredType: nil, value: nil), .list)
    }

    func testChosenNotesAreWrittenAsOneLinkOrAListAndNoneClearsTheProperty() {
        XCTAssertEqual(BaseRelation.propertyValue(chosen: ["[[VLSI 3]]"], shape: .single), .text("[[VLSI 3]]"))
        XCTAssertEqual(BaseRelation.propertyValue(chosen: ["[[VLSI 3]]", "[[Lab]]"], shape: .single), .list(["[[VLSI 3]]", "[[Lab]]"]))
        XCTAssertEqual(BaseRelation.propertyValue(chosen: ["[[VLSI 3]]"], shape: .list), .list(["[[VLSI 3]]"]))
        XCTAssertEqual(BaseRelation.propertyValue(chosen: [" "], shape: .list), .empty)
        XCTAssertEqual(BaseRelation.writtenItem(target: "Courses/VLSI 3"), "[[Courses/VLSI 3]]")
    }

    func testTheLinksOfAValueLeaveOutAddressesAndOtherValues() {
        let links = BaseRelation.links(in: .list([.link(BaseLink(target: "A")), .string("[[B|Bee]]"), .number(2), .link(BaseLink(target: "https://x.org"))]))
        XCTAssertEqual(links.map(\.target), ["A", "B"])
    }
}
