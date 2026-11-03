/**
 * File: VaultGraph.swift
 * ----------------------
 * Layer: Index
 * Description: Builds the graph view's data, and resolves links over names held in memory.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 01/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// Every file, the links between them (in note text and in properties, embeds
    /// included), links to files that do not exist, and each file's tags, for the graph view.
    /// Links resolve as they do everywhere else; a link that could mean several files is
    /// left out rather than drawn to one of them.
    ///
    /// Read on a reader connection of its own, so the whole-vault pass does not hold the
    /// index's writer from the saves and scans that wait for it.
    public nonisolated func linkGraph() async throws -> LinkGraph {
        try await databasePool.read { database in
            let resolver = try GraphLinkResolver(database: database)
            let files = resolver.paths.compactMap { path in try? VaultPath(path) }
            let rows = try Row.fetchAll(database, sql: "SELECT source, target, isWiki FROM links UNION SELECT path, target, 1 FROM property_links")
            var resolvedByKey: [String: [String]] = [:]
            var links: [(source: VaultPath, target: VaultPath)] = []
            var unresolvedLinks: [(source: VaultPath, target: String)] = []
            for row in rows {
                guard let source = try? VaultPath(row["source"] as String) else { continue }
                let target: String = row["target"]
                let isWiki: Bool = row["isWiki"]
                // Web pages and other apps' links are not notes.
                guard !target.isEmpty, !Self.isExternalLink(target) else { continue }
                // A link resolves the same way from every note in one folder.
                let cacheKey = (isWiki ? "w" : "m") + source.parent.rawValue + "\u{0}" + target
                let resolved: [String]
                if let cached = resolvedByKey[cacheKey] {
                    resolved = cached
                } else {
                    resolved = resolver.resolve(target, from: source, isWiki: isWiki)
                    resolvedByKey[cacheKey] = resolved
                }
                if let destination = resolved.first.flatMap({ path in try? VaultPath(path) }) {
                    links.append((source, destination))
                } else if resolved.isEmpty {
                    unresolvedLinks.append((source, target))
                }
            }
            let tags = try Row.fetchAll(database, sql: "SELECT path, tag FROM tags").compactMap { row -> (path: VaultPath, tag: String)? in
                guard let path = try? VaultPath(row["path"] as String) else { return nil }
                return (path, row["tag"])
            }
            return LinkGraph.build(files: files, links: links, unresolvedLinks: unresolvedLinks, tags: tags)
        }
    }

    /// The notes that embed any of `notes`, or embed a note that does, up to `levels` embeds
    /// away: what must draw again when these notes change. A superset, since an embed is matched
    /// by what it writes and not resolved; a note wrongly in it only draws once more.
    public nonisolated func notesEmbedding(_ notes: [VaultPath], throughLevels levels: Int) async throws -> Set<VaultPath> {
        try await databasePool.read { database in
            var embeddingNotes: Set<VaultPath> = []
            var notesThisLevel = notes
            for _ in 0..<levels where !notesThisLevel.isEmpty {
                var candidates: [String] = []
                for note in notesThisLevel { candidates += try Self.foldedLinkTargetCandidates(for: note, in: database) }
                let sources = try String.fetchAll(database,
                    sql: "SELECT DISTINCT source FROM links WHERE isEmbed = 1 AND folded_target IN (\(databaseQuestionMarks(count: candidates.count)))",
                                                  arguments: StatementArguments(candidates)).compactMap { source in
                    try? VaultPath(source) // A row with no valid path embeds nothing.
                }
                notesThisLevel = sources.filter { source in embeddingNotes.insert(source).inserted }
            }
            return embeddingNotes
        }
    }

    /// The resolver the graph uses, for tests that compare it with `resolve`.
    func graphLinkResolver() throws -> GraphLinkResolver {
        try databasePool.read { database in try GraphLinkResolver(database: database) }
    }

    static func isExternalLink(_ target: String) -> Bool {
        guard let colon = target.firstIndex(of: ":") else { return false }
        let scheme = target[..<colon]
        // `C:` alone is not a scheme worth treating as one, and schemes have no spaces.
        return scheme.count > 1 && scheme.allSatisfy { character in character.isLetter || character.isNumber || "+-.".contains(character) }
    }
}

/// `VaultIndex.resolvedPaths` over names held in memory: the graph resolves every link in
/// the vault, and a query per link takes seconds for a large vault. Names compare by the
/// folded keys the index stores (`VaultIndex.foldedKey`), ignoring case for every letter.
struct GraphLinkResolver: Sendable {
    /// Every file, sorted as SQLite sorts them.
    let paths: [String]
    private let pathsByFoldedPath: [String: [String]]
    private let pathsByFoldedName: [String: [String]]
    /// Files by the last component of their folded path, which a partial path's folded
    /// suffix shares with every path it matches.
    private let pathsByFoldedLastComponent: [String: [String]]
    private let pathsByFoldedAlias: [String: [String]]
    private let foldedPathsByPath: [String: String]

    init(database: Database) throws {
        var paths: [String] = []
        var pathsByFoldedPath: [String: [String]] = [:]
        var pathsByFoldedName: [String: [String]] = [:]
        var pathsByFoldedLastComponent: [String: [String]] = [:]
        var foldedPathsByPath: [String: String] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT path, folded_path, folded_name FROM files ORDER BY path") {
            let path: String = row["path"]
            let foldedPath = (row["folded_path"] as String?) ?? VaultIndex.foldedKey(path)
            let foldedName = (row["folded_name"] as String?) ?? VaultIndex.foldedKey((path as NSString).lastPathComponent)
            paths.append(path)
            foldedPathsByPath[path] = foldedPath
            pathsByFoldedPath[foldedPath, default: []].append(path)
            pathsByFoldedName[foldedName, default: []].append(path)
            pathsByFoldedLastComponent[Self.lastComponent(of: foldedPath), default: []].append(path)
        }
        var pathsByFoldedAlias: [String: [String]] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT alias, folded_alias, path FROM aliases") {
            let foldedAlias = (row["folded_alias"] as String?) ?? VaultIndex.foldedKey(row["alias"] as String)
            pathsByFoldedAlias[foldedAlias, default: []].append(row["path"])
        }
        self.paths = paths
        self.pathsByFoldedPath = pathsByFoldedPath
        self.pathsByFoldedName = pathsByFoldedName
        self.pathsByFoldedLastComponent = pathsByFoldedLastComponent
        self.pathsByFoldedAlias = pathsByFoldedAlias
        self.foldedPathsByPath = foldedPathsByPath
    }

    func resolve(_ target: String, from source: VaultPath, isWiki: Bool) -> [String] {
        for candidate in WikiLinkResolver.directCandidates(target: target, source: source, isWiki: isWiki) {
            // Files whose names differ only by case prefer the exact spelling, and are
            // otherwise returned together.
            let matches = Array((pathsByFoldedPath[VaultIndex.foldedKey(candidate.rawValue)] ?? []).prefix(50))
            guard !matches.isEmpty else { continue }
            let candidateKey = WikiLinkResolver.comparisonKey(candidate.rawValue)
            if let exactPath = matches.first(where: { path in WikiLinkResolver.comparisonKey(path) == candidateKey }) { return [exactPath] }
            return matches
        }
        let part = WikiLinkResolver.comparisonKey(VaultIndex.lookupPathPart(of: target, isWiki: isWiki))
        guard !part.isEmpty, !part.contains(":") else { return [] }
        for fileName in WikiLinkResolver.fileNameVariants(for: part) {
            var matches: Set<String> = []
            if part.contains("/") {
                // A partial path, such as `[[covers/Book cover.png]]`, names the end of a
                // path, or the whole path when it starts at the vault root (`[[/Folder/Note]]`).
                let isFromRoot = fileName.hasPrefix("/")
                let pathSuffix = VaultIndex.foldedKey(isFromRoot ? String(fileName.drop { character in character == "/" }) : fileName)
                for path in pathsByFoldedLastComponent[Self.lastComponent(of: pathSuffix)] ?? [] {
                    guard let foldedPath = foldedPathsByPath[path] else { continue }
                    // A path from the root names that path only, as the index resolves it.
                    if foldedPath == pathSuffix || (!isFromRoot && foldedPath.hasSuffix("/" + pathSuffix)) { matches.insert(path) }
                }
            } else {
                // A file's own name goes before another note's alias, as in the index.
                let namedPaths = pathsByFoldedName[VaultIndex.foldedKey(fileName)] ?? []
                if !namedPaths.isEmpty { return WikiLinkResolver.closestFirst(namedPaths, toNoteAt: source) }
                if isWiki { matches.formUnion(pathsByFoldedAlias[VaultIndex.foldedKey(part)] ?? []) }
            }
            if !matches.isEmpty { return WikiLinkResolver.closestFirst(Array(matches), toNoteAt: source) }
        }
        return []
    }

    /// The files a link counts as a backlink of, by the rules of `VaultIndex.backlinkSources`:
    /// a target that spells a file's whole path names it, from any folder, and any other target
    /// names the one file it resolves to.
    func backlinkDestinations(ofTarget target: String, from source: VaultPath, isWiki: Bool) -> [String] {
        let foldedTarget = VaultIndex.foldedKey(target)
        var destinations = pathsByFoldedPath[foldedTarget] ?? []
        if target.hasPrefix("/") { destinations += pathsByFoldedPath[VaultIndex.foldedKey(String(target.dropFirst()))] ?? [] }
        let resolvedPaths = resolve(target, from: source, isWiki: isWiki)
        destinations += resolvedPaths.prefix(1)
        return destinations
    }

    private static func lastComponent(of foldedPath: String) -> String {
        foldedPath.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? foldedPath
    }
}
