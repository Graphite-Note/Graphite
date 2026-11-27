/**
 * File: BaseDocumentModelRelations.swift
 * --------------------------------------
 * Layer: UI
 * Description: The notes a relation property of a base's row can link to, found in the vault's index, and the notes
 *              it links to now.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore

/// A note the relation picker offers, with why it is offered.
struct BaseRelationCandidate: Identifiable, Hashable {
    enum Source: Hashable {
        /// Notes the property already links to somewhere in the vault.
        case linked
        /// Other notes of those notes' folders.
        case sameFolder
        /// Notes the typed text finds.
        case search
    }

    let path: VaultPath
    let source: Source
    var id: VaultPath { path }
    var title: String { path.stem }
    /// The folder the note is in, empty at the vault's root.
    var folder: String { path.parent.rawValue }
}

/// A note the relation links to: its item as written in the note (`[[VLSI 3]]`) and the note it reaches, if any.
struct BaseRelationChoice: Identifiable, Hashable {
    let writtenItem: String
    let path: VaultPath?
    var id: String { writtenItem }
    var title: String { path?.stem ?? BaseLink.parse(writtenItem)?.displayText ?? writtenItem }
}

/// What a base's relation picker reads from the vault's index: its read port (Docs/solid/rewrite-foundations.md section
/// 3.3 rule 3), answered by `VaultIndex` (BaseEmbedding.swift).
protocol BaseRelationLookup: Sendable {
    /// The values the vault gives the property, the most frequent first.
    func relationValues(of key: String, limit: Int) async throws -> [String]
    /// The files a link target written in `source` names, the best first.
    func resolve(_ target: String, from source: VaultPath, isWiki: Bool) async throws -> [VaultPath]
    func notes(directlyInside folder: VaultPath, limit: Int) async throws -> [VaultPath]
}

extension BaseDocumentModel {
    /// Notes the picker lists at most, the linked, folder and found notes together.
    static let maximumRelationCandidates = 60
    /// Notes read from one folder at most.
    private static let maximumFolderNotes = 40
    /// Values of the property read from the index to find the notes it links to.
    private static let examinedRelationValueCount = 40

    /// Whether the property is a relation: its value holds a link to a note, or most of the values the vault gives it
    /// most often are links (`BaseRelation.isRelation`). Without an answer from the index it is not one.
    func isRelation(_ property: BasePropertyIdentifier, value: BaseValue?) async -> Bool {
        guard case .note(let name) = property else { return false }
        if let value, !BaseRelation.links(in: value).isEmpty { return true }
        let limit = BaseRelation.examinedVaultValueCount
        let vaultValues = (try? await relationLookup.relationValues(of: name, limit: limit)) ?? [] // No answer: not a relation.
        return BaseRelation.isRelation(value: value, vaultValues: vaultValues)
    }

    /// One link or a list, from the property's declared type and its value.
    func relationShape(_ property: BasePropertyIdentifier, value: BaseValue?) -> BaseRelationShape {
        BaseRelation.shape(declaredType: declaredTypes[property.name] ?? declaredTypes.first { entry in
            entry.key.caseInsensitiveCompare(property.name) == .orderedSame
        }?.value, value: value)
    }

    /// The notes the row's property links to now, each item as the note writes it when known (`writtenNode`).
    func relationChoices(of path: VaultPath, value: BaseValue?, writtenNode: BaseFrontmatterNode?) async -> [BaseRelationChoice] {
        let writtenItems: [String]
        switch writtenNode {
        case .scalar(let text, _)?: writtenItems = [text]
        case .sequence(let items)?:
            writtenItems = items.compactMap { item -> String? in
                if case .scalar(let text, _) = item { return text }
                return nil
            }
        case .mapping?, nil: writtenItems = (value.map(BaseRelation.links(in:)) ?? []).map { link in BasePropertyDraft.sourceText(.link(link)) }
        }
        var choices: [BaseRelationChoice] = []
        for item in writtenItems where !item.trimmingCharacters(in: .whitespaces).isEmpty {
            var reached: VaultPath?
            if let link = BaseLink.parse(item.trimmingCharacters(in: .whitespaces), source: path), !link.isExternal {
                reached = try? await relationLookup.resolve(link.target, from: path, isWiki: true).first // Unread: shown as written, unresolved.
            }
            choices.append(BaseRelationChoice(writtenItem: item, path: reached))
        }
        return choices
    }

    /// The notes the picker offers for the row's property: the notes the property links to in the vault, then the
    /// other notes of their folders, then what `query` finds, each once, never the row itself.
    func relationCandidates(for property: BasePropertyIdentifier, of path: VaultPath, query: String,
                            services: BaseNoteServices) async -> [BaseRelationCandidate] {
        guard case .note(let name) = property else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        var seen: Set<VaultPath> = [path]
        var candidates: [BaseRelationCandidate] = []
        func offer(_ notePath: VaultPath, _ source: BaseRelationCandidate.Source) {
            guard candidates.count < Self.maximumRelationCandidates, DocumentKind(path: notePath) == .markdown, seen.insert(notePath).inserted else { return }
            guard source == .search || trimmedQuery.isEmpty || Self.title(notePath.stem, contains: trimmedQuery) else { return }
            candidates.append(BaseRelationCandidate(path: notePath, source: source))
        }
        let linked = await linkedNotes(of: name, from: path)
        linked.forEach { notePath in offer(notePath, .linked) }
        var folders: [VaultPath] = []
        for notePath in linked where !folders.contains(notePath.parent) { folders.append(notePath.parent) }
        for folder in folders {
            let folderNotes = (try? await relationLookup.notes(directlyInside: folder, limit: Self.maximumFolderNotes)) ?? [] // Unread: the folder offers none.
            folderNotes.forEach { notePath in offer(notePath, .sameFolder) }
        }
        if !trimmedQuery.isEmpty {
            await services.searchNotes(trimmedQuery, Self.maximumRelationCandidates).forEach { notePath in offer(notePath, .search) }
        }
        return candidates
    }

    /// The notes the property's values link to across the vault, most linked first, resolved from the row's note.
    private func linkedNotes(of name: String, from path: VaultPath) async -> [VaultPath] {
        let values = (try? await relationLookup.relationValues(of: name, limit: Self.examinedRelationValueCount)) ?? [] // Unread: none linked.
        var notes: [VaultPath] = []
        for value in values {
            guard let link = BaseLink.parse(value.trimmingCharacters(in: .whitespaces)), !link.isExternal,
                  let notePath = try? await relationLookup.resolve(link.target, from: path, isWiki: true).first, // Unresolved: left out.
                  !notes.contains(notePath) else { continue }
            notes.append(notePath)
        }
        return notes
    }

    private nonisolated static func title(_ title: String, contains query: String) -> Bool {
        title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
