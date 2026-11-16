/**
 * File: WorkspaceTagsAndProperties.swift
 * --------------------------------------
 * Layer: UI
 * Description: The vault's tags and properties for the sidebar lists, and searching for one.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 17/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteIndex

/// A property used somewhere in the vault, as the Properties view lists it.
struct PropertySummary: Identifiable, Equatable {
    let key: String
    let fileCount: Int
    let type: PropertyType
    var id: String { key.lowercased() }
}

/// Obsidian's Tags view and Properties view over the whole vault.
extension WorkspaceModel {
    /// Every tag with the notes using it; with `nested`, every level of nested tags, each
    /// counting the notes under it.
    func vaultTags(nested: Bool) async throws -> [TagCount] {
        guard let index else { return [] }
        return nested ? try await index.nestedTagCounts() : try await index.tags(matching: "", limit: Self.maximumListedTags)
    }

    private static var maximumListedTags: Int { 100_000 }

    func vaultProperties() async throws -> [PropertySummary] {
        guard let index, let store else { return [] }
        let usages = try await index.propertyUsages()
        let declaredTypes = await store.propertyTypes()
        return usages.map { usage in
            PropertySummary(key: usage.key, fileCount: usage.fileCount,
                            type: NoteProperties.type(ofKey: usage.key, sampleValues: usage.sampleValues, declaredTypes: declaredTypes))
        }
    }

    /// The vault's property names, values and tags suggested while they are typed, read from the index. The workspace is
    /// held weakly: the suggestions live in editors and panels that the workspace outlives.
    var propertySuggestions: PropertySuggestions { propertySuggestions(linkingFrom: nil) }

    /// `propertySuggestions` whose `[[` links are written as the vault's link format writes them from `notePath`.
    func propertySuggestions(linkingFrom notePath: VaultPath?) -> PropertySuggestions {
        var suggestions = PropertySuggestions(vaultTags: { [weak self] query, limit in
            let tags = (try? await self?.index?.tags(matching: query, limit: limit)) ?? [] // No answer, no suggestions; typing goes on.
            return tags.map { tagCount in (tagCount.tag, tagCount.fileCount) }
        }, vaultValues: { [weak self] name, query, limit in
            let values = (try? await self?.index?.propertyValues(of: name, matching: query, limit: limit)) ?? [] // No answer, no suggestions.
            return values.map { value in (value.value, value.fileCount) }
        }, vaultNames: { [weak self] in
            await self?.cachedPropertySummaries() ?? []
        })
        suggestions.vaultNotes = { [weak self] query, limit in
            guard let self, !query.isEmpty else { return [] }
            let matches = (try? await self.index?.quickSwitcherMatches(for: query, limit: limit)) ?? [] // No answer, no notes.
            let settings = self.vaultSettings
            return matches.map { match in
                let name = VaultIndex.switcherName(match.path)
                let isNameUnique = matches.filter { other in VaultIndex.switcherName(other.path) == name }.count == 1
                let target = notePath.map { from in LinkCompletion.linkTarget(for: match.path, from: from, settings: settings, isNameUnique: isNameUnique) }
                    ?? (isNameUnique ? name : (DocumentKind(path: match.path) == .markdown ? String(match.path.rawValue.dropLast(3)) : match.path.rawValue))
                return (target, match.alias ?? name, DocumentKind(path: match.path).systemImage)
            }
        }
        return suggestions
    }

    /// `propertySuggestions` for the Properties panel and the Bases sheet.
    var propertySuggestionLookup: PropertySuggestionLookup { PropertySuggestionLookup(suggestions: propertySuggestions) }

    /// `propertySuggestionLookup` for a note's Properties panel, whose `[[` links name notes from `notePath`.
    func propertySuggestionLookup(linkingFrom notePath: VaultPath) -> PropertySuggestionLookup {
        PropertySuggestionLookup(suggestions: propertySuggestions(linkingFrom: notePath))
    }

    /// The vault's property names with their types, read once for each version of the index: the names change only when
    /// a note is indexed again, and reading them all takes longer than a keystroke's frame in a large vault.
    private func cachedPropertySummaries() async -> [PropertySummary] {
        let version = indexVersion
        if let cached = propertySuggestionCache, cached.indexVersion == version { return cached.summaries }
        guard let summaries = try? await vaultProperties() else { return [] } // No answer: no suggestions, nothing kept.
        propertySuggestionCache = PropertySuggestionCache(indexVersion: version, summaries: summaries)
        return summaries
    }

    /// Shows the notes with a tag, nested tags included, in the sidebar's search.
    func searchForTag(_ tag: String) {
        searchQuery = "tag:#" + tag
    }

    /// `searchForTag`, for a tag chosen outside the sidebar: the sidebar with the results comes forward.
    func searchForTagAndShowResults(_ tag: String) {
        searchForTag(tag)
        searchResultsRevealRequest += 1
    }

    /// Shows the notes with a property in the sidebar's search.
    func searchForProperty(_ key: String) {
        let needsQuotes = key.contains(where: { character in ":[]() ".contains(character) }) && !key.contains("\"")
        searchQuery = "[" + (needsQuotes ? "\"\(key)\"" : key) + "]"
    }

    /// Assigns a type in `.obsidian/types.json`, as Obsidian's Properties view does.
    func setPropertyType(_ type: PropertyType, forKey key: String) async {
        guard let store else { return }
        do {
            try await store.setPropertyType(type, forKey: key)
            propertyTypesVersion += 1
        } catch { errorMessage.report(error) }
    }

    /// Renames a property in every note that has it, changing only the name where it is
    /// written. Open notes change through their editors, so each can be undone there;
    /// other notes are written only if they did not change since they were read. Notes
    /// that could not be renamed are reported and left as they were.
    func renameProperty(_ key: String, to newKey: String) async {
        guard let store, let index else { return }
        let newName = newKey.trimmingCharacters(in: .whitespaces)
        // An alert's buttons cannot be disabled, so an empty name can reach here.
        guard !newName.isEmpty else { errorMessage = "A property needs a name."; return }
        guard newName != key else { return }
        do {
            try await saveOpenDocuments()
            let paths = try await index.paths(withPropertyKey: key)
            var renamedPaths: [VaultPath] = []
            var unchangedNotes: [(path: VaultPath, reason: String)] = []
            for path in paths {
                do {
                    if let session = openMarkdownSession(at: path) {
                        guard let edit = try PropertyRenaming.edit(renaming: key, to: newName, in: session.text, selection: session.selection) else { continue }
                        session.apply(edit)
                        // An editor applies the edit on its next update and autosaves it like
                        // typing; without one, the text has already changed.
                        if !session.isEditorAttached { try await session.save() }
                    } else {
                        let snapshot = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
                        // Decoded and written back as a note is, keeping a byte order mark the file has.
                        guard let decoded = NoteTextEncoding.decode(snapshot.data) else { throw GraphiteError.invalidFile("It is not UTF-8 text.") }
                        guard let edit = try PropertyRenaming.edit(renaming: key, to: newName, in: decoded.text) else { continue }
                        let renamedText = (decoded.text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                        _ = try await store.save(NoteTextEncoding.encode(renamedText, hasByteOrderMark: decoded.hasByteOrderMark), at: path,
                                                 expecting: .revision(snapshot.revision))
                    }
                    renamedPaths.append(path)
                } catch {
                    unchangedNotes.append((path, error.localizedDescription))
                }
            }
            if !renamedPaths.isEmpty {
                try await store.movePropertyType(from: key, to: newName)
                propertyTypesVersion += 1
                refreshIndex(for: renamedPaths)
            }
            if !unchangedNotes.isEmpty {
                let listed = unchangedNotes.prefix(5).map { note in "“\(note.path.stem)”: \(note.reason)" }.joined(separator: "\n")
                let more = unchangedNotes.count > 5 ? "\nand \(unchangedNotes.count - 5) more." : ""
                errorMessage = "“\(key)” was renamed in \(Self.noteCount(renamedPaths.count)), but not in \(Self.noteCount(unchangedNotes.count)):\n" + listed + more
            }
        } catch { errorMessage.report(error) }
    }

    private static func noteCount(_ count: Int) -> String { count == 1 ? "1 note" : "\(count) notes" }
}
