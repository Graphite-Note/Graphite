/**
 * File: PropertyValueQueriesTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The values one property takes across the vault, for suggestions: counts, the limit, list and text values,
 *              capitals and accents.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
@testable import GraphiteIndex
import GraphiteCore
import GraphiteTestSupport

final class PropertyValueQueriesTests: XCTestCase {
    private var index: VaultIndex!

    override func setUp() async throws {
        let directory = try TemporaryVault.make(prefix: "PropertyValues", for: self).root
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("One.md"), size: 1, modified: .now, markdown: "---\ncourse: VLSI 3\nteachers: [Ada, Grace]\n---\n"),
            IndexedFile(path: try VaultPath("Two.md"), size: 1, modified: .now, markdown: "---\nCourse: VLSI 3\nteachers:\n  - Ada\n---\n"),
            IndexedFile(path: try VaultPath("Three.md"), size: 1, modified: .now, markdown: "---\ncourse: Computer Architecture\n---\n"),
            IndexedFile(path: try VaultPath("Four.md"), size: 1, modified: .now, markdown: "---\ncourse: vlsi 3\nplace: Zürich\n---\n"),
            IndexedFile(path: try VaultPath("Five.md"), size: 1, modified: .now, markdown: "---\ncourse: Électronique\nplace: zurich\n---\n"),
        ], generation: "test")
    }

    func testAPropertysValuesAreCountedByNoteMostUsedFirstWhateverTheKeysCapitals() async throws {
        let values = try await index.propertyValues(of: "course", matching: "")
        XCTAssertEqual(values.map(\.value), ["VLSI 3", "Computer Architecture", "Électronique"],
                       "Spellings that differ in capitals are one value, written as most notes write it; then by name.")
        XCTAssertEqual(values.map(\.fileCount), [3, 1, 1])
    }

    func testEachItemOfAListIsAValue() async throws {
        let values = try await index.propertyValues(of: "teachers", matching: "")
        XCTAssertEqual(values.map(\.value), ["Ada", "Grace"])
        XCTAssertEqual(values.map(\.fileCount), [2, 1])
    }

    func testTheQueryMatchesInsideIgnoringCapitalsAndAccents() async throws {
        let architecture = try await index.propertyValues(of: "course", matching: "arch")
        XCTAssertEqual(architecture.map(\.value), ["Computer Architecture"])
        let electronics = try await index.propertyValues(of: "course", matching: "electro")
        XCTAssertEqual(electronics.map(\.value), ["Électronique"])
        let places = try await index.propertyValues(of: "place", matching: "zur")
        XCTAssertEqual(places.map(\.fileCount), [1, 1], "Zürich and zurich differ in more than capitals, so they are two values.")
    }

    func testTheLimitKeepsTheMostUsed() async throws {
        let values = try await index.propertyValues(of: "course", matching: "", limit: 1)
        XCTAssertEqual(values.map(\.value), ["VLSI 3"])
        let missing = try await index.propertyValues(of: "missing", matching: "")
        XCTAssertTrue(missing.isEmpty)
    }
}
