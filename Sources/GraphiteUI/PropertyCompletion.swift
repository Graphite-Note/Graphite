/**
 * File: PropertyCompletion.swift
 * ------------------------------
 * Layer: UI
 * Description: Suggestions of the vault's property names, their values and its tags while a note's frontmatter is typed,
 *              in the editor's suggestion list, and the same suggestions for the Properties panel's fields.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// The vault's property names, values and tags, as suggestions for what is being typed. Read from the index only, never
/// from notes, so an unindexed vault suggests nothing (`Docs/Property-and-tag-completion-todo.md`).
@MainActor
struct PropertySuggestions {
    /// The vault's tags containing a query, at most a count, with how many notes use each (`VaultIndex.tags`).
    let vaultTags: @MainActor (_ query: String, _ limit: Int) async -> [(tag: String, fileCount: Int)]
    /// A property's values containing a query, at most a count (`VaultIndex.propertyValues`).
    let vaultValues: @MainActor (_ name: String, _ query: String, _ limit: Int) async -> [(value: String, fileCount: Int)]
    /// The vault's property names with their types, kept until the index changes (`WorkspaceModel.propertySuggestions`).
    let vaultNames: @MainActor () async -> [PropertySummary]
    /// Suggestions listed at most.
    static let maximumCount = 40

    /// A suggested name or value: what is written when it is chosen, and how many notes use it.
    struct Suggestion: Equatable, Identifiable {
        let text: String
        let fileCount: Int
        let systemImage: String
        var id: String { text }
        var countText: String { fileCount == 1 ? "1 note" : "\(fileCount) notes" }
    }

    /// Whether `name` holds the vault's tags, as Obsidian treats `tags` (and its old spelling `tag`).
    static func holdsTags(_ name: String) -> Bool {
        ["tags", "tag"].contains(name.lowercased())
    }

    /// The vault's property names containing `query`, with their types' icons, leaving out those the note has.
    func names(matching query: String, leavingOut writtenNames: [String]) async -> [Suggestion] {
        let written = Set(writtenNames.map { name in name.lowercased() })
        let summaries = await vaultNames()
        let matching = summaries.filter { summary in
            !written.contains(summary.key.lowercased())
                && (query.isEmpty || summary.key.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
        return matching.sorted { left, right in
            left.fileCount != right.fileCount ? left.fileCount > right.fileCount : left.key.localizedStandardCompare(right.key) == .orderedAscending
        }.prefix(Self.maximumCount).map { summary in
            Suggestion(text: summary.key, fileCount: summary.fileCount, systemImage: summary.type.systemImage)
        }
    }

    /// The type the vault gives a property's name, for a new property taken from a suggestion.
    func type(ofName name: String) async -> PropertyType? {
        await vaultNames().first { summary in summary.key.caseInsensitiveCompare(name) == .orderedSame }?.type
    }

    /// The values the property `name` takes in the vault containing `query`, or the vault's tags for `tags`, leaving out
    /// the list's other items.
    func values(of name: String, matching query: String, leavingOut writtenValues: [String]) async -> [Suggestion] {
        let written = Set(writtenValues.map { value in value.lowercased() })
        if Self.holdsTags(name) {
            let tagQuery = query.hasPrefix("#") ? String(query.dropFirst()) : query
            let tags = await vaultTags(tagQuery, Self.maximumCount + written.count)
            return tags.filter { tagCount in !written.contains(tagCount.tag.lowercased()) && !written.contains("#" + tagCount.tag.lowercased()) }
                .prefix(Self.maximumCount)
                .map { tagCount in Suggestion(text: tagCount.tag, fileCount: tagCount.fileCount, systemImage: "number") }
        }
        let values = await vaultValues(name, query, Self.maximumCount + written.count)
        return values.filter { value in !written.contains(value.value.lowercased()) }.prefix(Self.maximumCount).map { value in
            Suggestion(text: value.value, fileCount: value.fileCount, systemImage: "text.alignleft")
        }
    }
}

/// The vault's property names as last read for suggestions, with the index version they were read at.
struct PropertySuggestionCache {
    let indexVersion: Int
    let summaries: [PropertySummary]
}

extension CompletionProvider {
    /// A property's name at the start of a frontmatter line: choosing one writes `name: ` with the cursor after it.
    func propertyNameItems(query: String, writtenNames: [String]) async -> [CompletionItem] {
        let names = await workspace.propertySuggestions.names(matching: query, leavingOut: writtenNames)
        return names.map { name in
            CompletionItem(id: "property-" + name.text, title: name.text,
                           titleHighlights: FuzzyMatcher.match(query, in: name.text)?.matchedRanges ?? [],
                           subtitle: name.countText, systemImage: name.systemImage) { context in
                guard case .propertyName(_, let range, _) = context else { return [] }
                let replacement = Self.yamlKey(name.text) + ": "
                return [MarkdownTextEdit(range: range, replacement: replacement,
                                         selectionAfter: NSRange(location: range.location + replacement.utf16.count, length: 0))]
            }
        }
    }

    /// A property's value, or a tag under `tags`: choosing one writes it in place of what was typed.
    func propertyValueItems(name: String, query: String, writtenValues: [String]) async -> [CompletionItem] {
        let values = await workspace.propertySuggestions.values(of: name, matching: query, leavingOut: writtenValues)
        return values.filter { value in value.text != query }.map { value in
            CompletionItem(id: "value-" + value.text, title: value.text,
                           titleHighlights: FuzzyMatcher.match(query, in: value.text)?.matchedRanges ?? [],
                           subtitle: value.countText, systemImage: value.systemImage) { context in
                guard case .propertyValue(_, _, let range, _) = context else { return [] }
                return [MarkdownTextEdit(range: range, replacement: value.text,
                                         selectionAfter: NSRange(location: range.location + value.text.utf16.count, length: 0))]
            }
        }
    }

    /// A name as a YAML key: quoted when it holds a character that would end or change the key.
    nonisolated static func yamlKey(_ name: String) -> String {
        let needsQuotes = name.contains { character in ":#[]{},\"'".contains(character) } || name.hasPrefix("-") || name.hasPrefix(" ")
        return needsQuotes ? "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\"" : name
    }
}

/// The vault's suggestions for the Properties panel, which has no workspace of its own: names, a property's values or the
/// vault's tags, and the type the vault gives a name.
struct PropertySuggestionLookup {
    let names: @MainActor (_ query: String, _ writtenNames: [String]) async -> [PropertySuggestions.Suggestion]
    let values: @MainActor (_ name: String, _ query: String, _ writtenValues: [String]) async -> [PropertySuggestions.Suggestion]
    let type: @MainActor (_ name: String) async -> PropertyType?

    /// The vault's suggestions, as the editor takes them.
    @MainActor init(suggestions: PropertySuggestions) {
        names = { query, writtenNames in await suggestions.names(matching: query, leavingOut: writtenNames) }
        values = { name, query, writtenValues in await suggestions.values(of: name, matching: query, leavingOut: writtenValues) }
        type = { name in await suggestions.type(ofName: name) }
    }

    init(names: @escaping @MainActor (String, [String]) async -> [PropertySuggestions.Suggestion],
         values: @escaping @MainActor (String, String, [String]) async -> [PropertySuggestions.Suggestion],
         type: @escaping @MainActor (String) async -> PropertyType?) {
        self.names = names
        self.values = values
        self.type = type
    }
}

extension EnvironmentValues {
    /// The vault's suggestions for the Properties panel of the reading view; Live Preview passes them in its environment.
    @Entry var propertySuggestionLookup: PropertySuggestionLookup? = nil
}
