/**
 * File: PropertySuggestionQueryTimingTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The work a property or tag suggestion does at a keystroke, timed in an index of a vault of 32,843 made-up
 *              notes, the size of a large real one: one property's values and the tags filtered from those read once, and the
 *              names, values and tags read once for a field.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import XCTest
@testable import GraphiteIndex
import GraphiteCore
import GraphiteTestSupport

final class PropertySuggestionQueryTimingTests: XCTestCase {
    /// As many notes as a large real vault, each with properties and tags of a made-up course note.
    private static let noteCount = 32_843
    /// A keystroke's work must answer within a frame, so the suggestions follow the typing.
    private static let keystrokeBudgetSeconds = 1.0 / 60
    /// What is read once when a field opens (and kept until the index changes) may take a few frames.
    private static let readOnceBudgetSeconds = 0.5

    func testAKeystrokesQueriesAnswerWithinTheBudgetInAVaultOf32843Notes() async throws {
        let directory = try TemporaryVault.make(prefix: "PropertyTiming", for: self).root
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let courses = ["VLSI 3", "Computer Architecture", "Signals and Systems", "Analog Circuits", "Optics", "Databases"]
        var files: [IndexedFile] = []
        for number in 0..<Self.noteCount {
            let course = courses[number % courses.count]
            let markdown = "---\ncourse: \(course)\nweek: \(number % 14 + 1)\nstatus: \(number % 3 == 0 ? "done" : "open")\n"
                + "tags: [eth/course\(number % 40), week\(number % 14 + 1)]\n---\n\n# Note \(number)\n"
            files.append(IndexedFile(path: try VaultPath("Course \(number % 40)/Note \(number).md"), size: markdown.utf8.count, modified: .now,
                                     markdown: markdown))
            if files.count == 2_000 {
                try await index.update(files, generation: "timing")
                files.removeAll()
            }
        }
        try await index.update(files, generation: "timing")

        let (names, namesSeconds) = try await timed { try await index.propertyUsages() }
        let (allValues, readSeconds) = try await timed {
            try await index.propertyValues(of: "week", matching: "", limit: VaultIndex.maximumPropertyValuesKeptForSuggestions)
        }
        let (values, filterSeconds) = try await timed { VaultIndex.propertyValues(allValues, matching: "1", limit: 40) }
        let (allTags, tagsReadSeconds) = try await timed { try await index.tags(matching: "", limit: VaultIndex.maximumTagsKeptForSuggestions) }
        let (tags, tagsSeconds) = try await timed { VaultIndex.tags(allTags, matching: "eth/course1", limit: 30) }
        print("Property suggestion timing in \(Self.noteCount) notes: names \(namesSeconds) s, one property's values read \(readSeconds) s, "
              + "filtered at a keystroke \(filterSeconds) s, tags read \(tagsReadSeconds) s, filtered at a keystroke \(tagsSeconds) s")

        XCTAssertEqual(Set(names.map(\.key)), ["course", "week", "status", "tags"])
        XCTAssertEqual(allValues.count, 14)
        XCTAssertEqual(values.map(\.value), ["1", "10", "11", "12", "13", "14"])
        let queriedTags = try await index.tags(matching: "eth/course1")
        XCTAssertEqual(tags, queriedTags, "The tags filtered in memory are the ones the query gives.")
        // On a shared runner the times are printed, not checked: GitHub's macOS runners took over 16.7 ms for the tags' query.
        SharedRunner.assertWithinTimingBudget(filterSeconds, isLessThan: Self.keystrokeBudgetSeconds, "One property's values filtered at a keystroke")
        SharedRunner.assertWithinTimingBudget(tagsSeconds, isLessThan: Self.keystrokeBudgetSeconds, "The tags matching what is typed, at a keystroke")
        SharedRunner.assertWithinTimingBudget(tagsReadSeconds, isLessThan: Self.readOnceBudgetSeconds, "The vault's tags, read once for a field")
        SharedRunner.assertWithinTimingBudget(readSeconds, isLessThan: Self.readOnceBudgetSeconds, "A property's values, read once for a field")
        SharedRunner.assertWithinTimingBudget(namesSeconds, isLessThan: Self.readOnceBudgetSeconds, "The names, read once for a field")
    }

    private func timed<Value>(_ work: () async throws -> Value) async throws -> (Value, Double) {
        let start = ContinuousClock.now
        let value = try await work()
        let elapsed = ContinuousClock.now - start
        return (value, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }
}
