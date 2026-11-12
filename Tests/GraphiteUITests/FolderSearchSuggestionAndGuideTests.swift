/**
 * File: FolderSearchSuggestionAndGuideTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: The search field suggests `folder:` with the other operators, with what it finds, and the Guide's
 *              Search Your Vault topic describes it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

final class FolderSearchSuggestionAndGuideTests: XCTestCase {
    func testTheSearchFieldSuggestsFolderAfterFileWithWhatItFinds() throws {
        let syntaxes = SearchOperatorSuggestion.all.map(\.syntax)
        XCTAssertEqual(Array(syntaxes.prefix(4)), ["path:", "file:", "folder:", "tag:"])
        let folder = try XCTUnwrap(SearchOperatorSuggestion.all.first { suggestion in suggestion.syntax == "folder:" })
        XCTAssertEqual(folder.summary, "Find folders by name, and the notes inside them")
        XCTAssertEqual(Set(syntaxes).count, syntaxes.count, "Each operator is suggested once.")
    }

    func testSuggestionsAreOfferedWhereATermBeginsAndCompleteTheQuery() throws {
        XCTAssertEqual(SearchOperatorSuggestion.offered(after: ""), SearchOperatorSuggestion.all)
        XCTAssertEqual(SearchOperatorSuggestion.offered(after: "steak "), SearchOperatorSuggestion.all)
        XCTAssertEqual(SearchOperatorSuggestion.offered(after: "fol"), [], "Nothing in the middle of a word.")
        let folder = try XCTUnwrap(SearchOperatorSuggestion.offered(after: "steak ").first { suggestion in suggestion.syntax == "folder:" })
        XCTAssertEqual(folder.completion(after: "steak "), "steak folder:")
        // What the completion gives, once a name is typed after it, is a folder search.
        XCTAssertEqual(SearchQueryParser.parse(folder.completion(after: "") + "bati"), .scoped(.folder, .term(SearchTerm(text: "bati", kind: .word))))
    }

    func testEverySuggestedScopeParsesAsTheScopeItNames() {
        for suggestion in SearchOperatorSuggestion.all where suggestion.syntax.hasSuffix(":") {
            guard case .scoped = SearchQueryParser.parse(suggestion.syntax + "word") else {
                return XCTFail("“\(suggestion.syntax)word” is not read as a scope.")
            }
        }
    }

    func testTheGuidesSearchTopicDescribesFolderAndTheFilesFilter() {
        let content = GuideTopic.search.content
        let texts = content.steps.map(\.text)
        XCTAssertTrue(content.steps.contains { step in step.example?.contains("folder:bati") == true }, "The operators' example has folder:.")
        XCTAssertTrue(texts.contains { text in text.hasPrefix("**folder:** finds folders by part of their name") })
        XCTAssertTrue(texts.contains { text in text.contains("**Filter** at the top of the Files panel") })
        XCTAssertTrue(GuideTopic.search.matches("folder"), "The Guide's search finds the topic by folder.")
        XCTAssertEqual(GuideTopic.search.section, .organizing)
    }
}
