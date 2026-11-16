/**
 * File: SearchTermCompletionTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The sidebar search's suggestions of the vault's tags, property names and values: when each is offered and
 *              the query a choice writes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
@testable import GraphiteUI

final class SearchTermCompletionTests: XCTestCase {
    func testTagsAfterTagColonWithOrWithoutTheHash() {
        XCTAssertEqual(SearchTermCompletion(query: "exam tag:co"), .tag(query: "co"))
        XCTAssertEqual(SearchTermCompletion(query: "tag:#"), .tag(query: ""))
        XCTAssertEqual(SearchTermCompletion(query: "tag:#co")?.completion(of: "tag:#co", choosing: "course/math"), "tag:#course/math ")
        XCTAssertEqual(SearchTermCompletion(query: "lecture tag:co")?.completion(of: "lecture tag:co", choosing: "course"), "lecture tag:#course ")
        XCTAssertNil(SearchTermCompletion(query: "lecture notes"))
        XCTAssertNil(SearchTermCompletion(query: "path:tag"))
    }

    func testPropertyNamesAfterABracketAndValuesAfterTheColon() {
        XCTAssertEqual(SearchTermCompletion(query: "[cou"), .propertyName(query: "cou"))
        XCTAssertEqual(SearchTermCompletion(query: "[cou")?.completion(of: "[cou", choosing: "course"), "[course:")
        XCTAssertEqual(SearchTermCompletion(query: "exam [course:VL"), .propertyValue(name: "course", query: "VL"))
        XCTAssertEqual(SearchTermCompletion(query: "exam [course:VL")?.completion(of: "exam [course:VL", choosing: "VLSI 3"),
                       "exam [course:\"VLSI 3\"] ", "A value with a space is quoted, as the search reads it.")
        XCTAssertNil(SearchTermCompletion(query: "[course:VLSI] "), "A closed property term is done.")
    }
}
