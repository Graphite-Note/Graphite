/**
 * File: SearchTermCompletion.swift
 * --------------------------------
 * Layer: UI
 * Description: The vault's tags, property names and values the sidebar's search suggests while `tag:`, `[` or `[name:`
 *              is being typed, and the query each suggestion writes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation

/// What the search's last term is in the middle of typing, for the vault's suggestions beside the operators
/// (`Docs/Property-and-tag-completion-todo.md`, section 3).
enum SearchTermCompletion: Equatable {
    /// After `tag:` or `tag:#`: a tag, without its `#`.
    case tag(query: String)
    /// After `[`: a property's name.
    case propertyName(query: String)
    /// After `[name:`: that property's value.
    case propertyValue(name: String, query: String)

    /// The last term of `query`: an unclosed `[`, and what follows it, or the text after the last space.
    static func lastTermStart(in query: String) -> String.Index {
        if let bracket = query.lastIndex(of: "["), !query[bracket...].contains("]") { return bracket }
        return query.lastIndex(where: { character in character == " " }).map(query.index(after:)) ?? query.startIndex
    }

    /// What the query's last term is being typed as, or nil for anything else.
    init?(query: String) {
        let term = query[Self.lastTermStart(in: query)...]
        if term.hasPrefix("[") {
            let inside = term.dropFirst()
            if let colon = inside.firstIndex(of: ":") {
                let name = Self.unquoted(String(inside[..<colon]))
                guard !name.isEmpty else { return nil }
                self = .propertyValue(name: name, query: Self.unquoted(String(inside[inside.index(after: colon)...])))
            } else {
                self = .propertyName(query: Self.unquoted(String(inside)))
            }
            return
        }
        let lowercased = term.lowercased()
        guard lowercased.hasPrefix("tag:") else { return nil }
        var tag = term.dropFirst(4)
        if tag.hasPrefix("#") { tag = tag.dropFirst() }
        self = .tag(query: String(tag))
    }

    /// The query once `suggestion` is chosen: its last term written whole, ready for the next term or the value.
    func completion(of query: String, choosing suggestion: String) -> String {
        let prefix = query[..<Self.lastTermStart(in: query)]
        switch self {
        case .tag: return prefix + "tag:#" + suggestion + " "
        case .propertyName: return prefix + "[" + Self.quotedIfNeeded(suggestion) + ":"
        case .propertyValue(let name, _): return prefix + "[" + Self.quotedIfNeeded(name) + ":" + Self.quotedIfNeeded(suggestion) + "] "
        }
    }

    private static func unquoted(_ text: String) -> String {
        text.hasPrefix("\"") ? String(text.dropFirst()).replacingOccurrences(of: "\"", with: "") : text
    }

    /// A name or value in quotes when it holds a space or a character the search reads as syntax.
    static func quotedIfNeeded(_ text: String) -> String {
        text.contains(where: { character in " :[]()\"".contains(character) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "") + "\"" : text
    }
}
