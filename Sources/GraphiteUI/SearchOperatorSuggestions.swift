/**
 * File: SearchOperatorSuggestions.swift
 * -------------------------------------
 * Layer: UI
 * Description: The search operators the sidebar's search field suggests, with what each finds, and when they are offered.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

/// An operator the search field suggests, with what it finds: Obsidian's operators, and
/// Graphite's own `folder:`. The summaries are the search's help, shown under each operator.
struct SearchOperatorSuggestion: Identifiable, Equatable {
    let syntax: String
    let summary: String
    var id: String { syntax }

    static let all = [
        SearchOperatorSuggestion(syntax: "path:", summary: "Find text in the file path"),
        SearchOperatorSuggestion(syntax: "file:", summary: "Find text in the file name"),
        SearchOperatorSuggestion(syntax: "folder:", summary: "Find folders by name, and the notes inside them"),
        SearchOperatorSuggestion(syntax: "tag:", summary: "Find notes with a tag"),
        SearchOperatorSuggestion(syntax: "line:", summary: "Find words on the same line"),
        SearchOperatorSuggestion(syntax: "section:", summary: "Find words under the same heading"),
        SearchOperatorSuggestion(syntax: "task-todo:", summary: "Find open tasks"),
        SearchOperatorSuggestion(syntax: "task-done:", summary: "Find completed tasks"),
        SearchOperatorSuggestion(syntax: "content:", summary: "Find text in note content only"),
        SearchOperatorSuggestion(syntax: "match-case:", summary: "Find text with the same capitals"),
        SearchOperatorSuggestion(syntax: "[", summary: "Find notes by property, as in [status:draft]"),
    ]

    /// The suggestions for the query as typed: all of them while the field is empty or after a
    /// space, where a new term begins; none in the middle of a word.
    static func offered(after query: String) -> [SearchOperatorSuggestion] {
        query.isEmpty || query.hasSuffix(" ") ? all : []
    }

    /// The query once the suggestion is chosen: the operator added after what is typed.
    func completion(after query: String) -> String {
        query + syntax
    }
}
