/**
 * File: BaseRecordQueries.swift
 * -----------------------------
 * Layer: Index
 * Description: Answers bases' questions about files from the index.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 05/11/2026
 */

import Foundation
import GRDB
import GraphiteCore
import Synchronization

/// Base queries over the index: record loading with SQL pre-filtering, and a synchronous
/// lookup provider for the evaluator.
extension VaultIndex {
    /// Paths per `IN (…)` statement when loading related rows: records load in pages of
    /// this many files.
    private static let relatedRowChunkSize = 500
    /// Files a written link target may name before a `hasLink` requirement stops
    /// narrowing the query, which keeps the statement's argument list small.
    private static let maximumPrefilterLinkDestinations = 32

    /// Every file that can match a base, in path order, with what `contents` keeps of its
    /// properties, tags and links. There is no cap: the pre-filter narrows the files, and
    /// the evaluator checks every one loaded.
    public func baseRecords(matching prefilter: BaseRecordPrefilter, contents: BaseRecordContents = .everything) throws -> BaseRecordBatch {
        try readThroughTheWriter { database in
            let (whereClause, arguments) = try Self.sqlCondition(for: prefilter, in: database)
            let fileRows = try Row.fetchAll(database, sql: "SELECT path, size, modified, created FROM files WHERE \(whereClause) ORDER BY path", arguments: arguments)
                .map(IndexedFileRow.init)
            return BaseRecordBatch(records: try Self.records(for: fileRows, contents: contents, in: database))
        }
    }

    /// The property names of files that can match a base, at most `limit`, for the view
    /// editor's list of columns.
    public func basePropertyKeys(matching prefilter: BaseRecordPrefilter, limit: Int) throws -> [String] {
        try readThroughTheWriter { database in
            let (whereClause, arguments) = try Self.sqlCondition(for: prefilter, in: database)
            return try String.fetchAll(database, sql: "SELECT DISTINCT key FROM properties WHERE path IN (SELECT path FROM files WHERE \(whereClause)) LIMIT ?",
                                       arguments: arguments + [max(limit, 0)])
        }
    }

    /// One file's record, for `this` or a file outside the query.
    public func baseRecord(at path: VaultPath) throws -> BaseFileRecord? {
        try readThroughTheWriter { database in try Self.records(forPaths: [path.rawValue], in: database).first }
    }

    /// A provider for the evaluator. It reads the database synchronously, so use it
    /// only off the main actor (base queries run in a detached task).
    public nonisolated var baseRecordProvider: BaseIndexRecordProvider {
        BaseIndexRecordProvider(databasePool: databasePool)
    }

    // MARK: SQL

    private static func likePattern(escaping text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    /// SQLite's NOCASE and LIKE fold case only for ASCII, while the evaluator folds all
    /// letters. Requirements with other characters are skipped so the pre-filter stays
    /// a superset of the real result. Foundation's case-insensitive comparison also folds
    /// some stored non-ASCII text into ASCII (`straße` matches `strasse`, the Kelvin sign
    /// matches `k`), so each condition also lets through rows whose stored text is not
    /// ASCII (`storedTextIsNotASCII`).
    private static func isSafeForCaseInsensitiveSQL(_ texts: [String]) -> Bool {
        texts.allSatisfy { text in text.unicodeScalars.allSatisfy(\.isASCII) }
    }

    /// True for a row whose `column` holds a character outside ASCII: its UTF-8 byte
    /// length then exceeds its character length.
    private static func storedTextIsNotASCII(_ column: String) -> String {
        "length(CAST(\(column) AS BLOB)) <> length(\(column))"
    }

    private static func storedTextIsASCII(_ column: String) -> String {
        "length(CAST(\(column) AS BLOB)) = length(\(column))"
    }

    static func sqlCondition(for prefilter: BaseRecordPrefilter, in database: Database) throws -> (String, StatementArguments) {
        guard let superset = try BasePrefilterSQL.bounds(of: prefilter.condition, in: database).superset else { return ("1", StatementArguments()) }
        return (superset.text, superset.arguments)
    }

    /// SQL for every file that may meet `requirement`, or nil when the index cannot narrow it.
    static func supersetCondition(for requirement: BasePrefilterRequirement, in database: Database) throws -> BasePrefilterSQL.Fragment? {
        switch requirement {
        case .inAnyFolder(let folders):
            guard !folders.isEmpty, isSafeForCaseInsensitiveSQL(folders) else { return nil }
            return .init(text: "(" + folders.map { _ in "path LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + " OR \(storedTextIsNotASCII("path")))",
                         arguments: StatementArguments(folders.map { folder in likePattern(escaping: folder) + "/%" }))
        case .hasAnyTag(let tags):
            guard !tags.isEmpty, isSafeForCaseInsensitiveSQL(tags) else { return nil }
            let tagConditions = tags.map { _ in "tag = ? COLLATE NOCASE OR tag LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
            return .init(text: "path IN (SELECT path FROM tags WHERE \(tagConditions) OR \(storedTextIsNotASCII("tag")))",
                         arguments: StatementArguments(tags.flatMap { tag in [tag, likePattern(escaping: tag) + "/%"] }))
        case .hasAnyExtension(let fileExtensions):
            // A file without an extension has `file.ext == ""`, which no `%.` pattern matches.
            guard !fileExtensions.isEmpty, !fileExtensions.contains(where: \.isEmpty), isSafeForCaseInsensitiveSQL(fileExtensions) else { return nil }
            return .init(text: "(" + fileExtensions.map { _ in "path LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + ")",
                         arguments: StatementArguments(fileExtensions.map { fileExtension in "%." + likePattern(escaping: fileExtension) }))
        case .hasAnyProperty(let keys):
            guard !keys.isEmpty, isSafeForCaseInsensitiveSQL(keys) else { return nil }
            return .init(text: "path IN (SELECT path FROM properties WHERE " + keys.map { _ in "key = ? COLLATE NOCASE" }.joined(separator: " OR ")
                         + " OR \(storedTextIsNotASCII("key")))", arguments: StatementArguments(keys))
        case .linksTo(let destination):
            return try linkCondition(for: destination, in: database).map { linkClause, linkArguments in .init(text: linkClause, arguments: linkArguments) }
        case .inExactFolder(let folder):
            guard isSafeForCaseInsensitiveSQL([folder]) else { return nil }
            if folder == "/" { return .init(text: "(instr(path, '/') = 0 OR \(storedTextIsNotASCII("path")))", arguments: []) }
            let folderPattern = likePattern(escaping: folder) + "/%"
            return .init(text: "((path LIKE ? ESCAPE '\\' AND path NOT LIKE ? ESCAPE '\\') OR \(storedTextIsNotASCII("path")))",
                         arguments: [folderPattern, folderPattern + "/%"])
        case .hasAnyFileName(let names), .hasAnyBasename(let names):
            guard !names.isEmpty, isSafeForCaseInsensitiveSQL(names) else { return nil }
            var patterns: [String] = []
            for name in names {
                let escapedName = likePattern(escaping: name)
                patterns += [escapedName, "%/" + escapedName]
                // A basename is the file name without its last extension.
                if case .hasAnyBasename = requirement { patterns += [escapedName + ".%", "%/" + escapedName + ".%"] }
            }
            return .init(text: "(" + patterns.map { _ in "path LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + " OR \(storedTextIsNotASCII("path")))",
                         arguments: StatementArguments(patterns))
        }
    }

    /// SQL for every file whose property may equal the requirement's text.
    static func supersetCondition(for requirement: BasePropertyTextRequirement) -> BasePrefilterSQL.Fragment? {
        guard isSafeForCaseInsensitiveSQL([requirement.key, requirement.text]) else { return nil }
        // The stored node is the value's JSON. A value with `%` or non-ASCII text can
        // still equal the requirement once the evaluator decodes or normalizes it.
        return .init(text: "path IN (SELECT path FROM properties WHERE (key = ? COLLATE NOCASE OR \(storedTextIsNotASCII("key")))"
                     + " AND (node LIKE ? ESCAPE '\\' OR instr(node, '%') > 0 OR \(storedTextIsNotASCII("node"))))",
                     arguments: [requirement.key, "%" + likePattern(escaping: requirement.text) + "%"])
    }

    /// SQL for files that certainly meet `requirement` as the evaluator reads it exactly,
    /// or nil when the index cannot tell. Only text in ASCII is compared, byte for byte or
    /// ignoring ASCII case as the evaluator does, so no Unicode equivalence can differ.
    static func subsetCondition(for requirement: BasePrefilterRequirement) -> BasePrefilterSQL.Fragment? {
        switch requirement {
        case .inAnyFolder(let folders):
            // `file.inFolder` compares the file's folder exactly, with its subfolders.
            guard !folders.isEmpty, isSafeForCaseInsensitiveSQL(folders) else { return nil }
            return .init(text: "((" + folders.map { _ in "substr(path, 1, ?) = ?" }.joined(separator: " OR ") + ") AND \(storedTextIsASCII("path")))",
                         arguments: StatementArguments(folders.flatMap { folder -> [any DatabaseValueConvertible] in [folder.utf8.count + 1, folder + "/"] }))
        case .hasAnyTag(let tags):
            // `file.hasTag` ignores case, and takes nested tags.
            guard !tags.isEmpty, isSafeForCaseInsensitiveSQL(tags) else { return nil }
            let tagConditions = tags.map { _ in "tag = ? COLLATE NOCASE OR tag LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
            return .init(text: "path IN (SELECT path FROM tags WHERE (\(tagConditions)) AND \(storedTextIsASCII("tag")))",
                         arguments: StatementArguments(tags.flatMap { tag in [tag, likePattern(escaping: tag) + "/%"] }))
        case .hasAnyExtension, .hasAnyProperty, .linksTo, .inExactFolder, .hasAnyFileName, .hasAnyBasename:
            return nil
        }
    }

    /// Files with a link that may reach `destination`, or nil when the index cannot narrow
    /// them. The evaluator resolves a written target from each row's own folder, so a
    /// target is widened to every file it could name from any folder: every file with its
    /// file name, and every file that has it as an alias. A link reaches such a file by
    /// the file's path or a trailing part of it (`Sub/Note`), optionally rooted with `/`;
    /// by a relative path (`../Sub/Note`, `./Note`); by an alias; or, when it resolves
    /// nowhere, by its written text alone. Names and targets are compared through the
    /// index's folded columns, which ignore case for every letter as the evaluator does.
    static func linkCondition(for destination: BaseLinkDestination, in database: Database) throws -> (String, StatementArguments)? {
        var destinations: [VaultPath] = []
        var writtenTargets: [VaultPath] = []
        switch destination {
        case .path(let path):
            destinations = [path]
        case .target(let target):
            let writtenPath = WikiLinkResolver.pathPart(target).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            let pathReadings = Array(Set([writtenPath, writtenPath.removingPercentEncoding ?? writtenPath]))
            let fileNames = pathReadings.compactMap { reading in reading.split(separator: "/").last.map(String.init) }
            guard !fileNames.isEmpty, !fileNames.contains(where: \.isEmpty) else { return nil }
            let nameKeys = Set(fileNames.flatMap(WikiLinkResolver.fileNameVariants(for:)).map(foldedKey)).sorted()
            let aliasKeys = Set(pathReadings.filter { reading in !reading.contains("/") }.map(foldedKey)).sorted()
            var sql = "SELECT path FROM files WHERE folded_name IN (\(placeholders(count: nameKeys.count)))"
            var lookupArguments = StatementArguments(nameKeys)
            if !aliasKeys.isEmpty {
                sql += " UNION SELECT path FROM aliases WHERE folded_alias IN (\(placeholders(count: aliasKeys.count)))"
                lookupArguments += StatementArguments(aliasKeys)
            }
            destinations = try String.fetchAll(database, sql: sql + " LIMIT ?", arguments: lookupArguments + [maximumPrefilterLinkDestinations + 1]).map(VaultPath.init)
            // A target that names no file, or too many, leaves the evaluator to decide.
            guard !destinations.isEmpty, destinations.count <= maximumPrefilterLinkDestinations else { return nil }
            // A row where the target resolves to nothing matches by the written text.
            writtenTargets = pathReadings.flatMap(WikiLinkResolver.fileNameVariants(for:)).compactMap { variant in try? VaultPath(variant) }
        }
        var exactTargets = Set<String>()
        var fileNames = Set<String>()
        for path in destinations + writtenTargets where !path.rawValue.isEmpty {
            exactTargets.formUnion(trailingPathForms(of: path))
            fileNames.formUnion([path.name, path.stem].map(foldedKey))
        }
        if !destinations.isEmpty {
            let aliases = try String.fetchAll(database, sql: "SELECT folded_alias FROM aliases WHERE path IN (\(placeholders(count: destinations.count)))",
                                              arguments: StatementArguments(destinations.map(\.rawValue)))
            exactTargets.formUnion(aliases)
        }
        exactTargets.remove("")
        fileNames.remove("")
        guard !exactTargets.isEmpty, !fileNames.isEmpty else { return nil }
        let sortedExactTargets = exactTargets.sorted()
        // Targets starting with `.` are a range of the folded target index, so only
        // relative targets are compared by their ending.
        let endings = fileNames.sorted().map { fileName in "%/" + likePattern(escaping: fileName) }
        // A link that resolves nowhere still reaches `destination` when its text, without
        // surrounding spaces and slashes, names it (`[[Target ]]`). Such a target starts
        // with a space, a slash or one of the exact targets followed by spaces or slashes,
        // each a range of the index: both characters sort before `0`.
        let paddedTargetStarts = sortedExactTargets.filter { exactTarget in !exactTarget.hasPrefix("/") }
        let targetCondition = "folded_target IN (\(placeholders(count: sortedExactTargets.count)))"
            + " OR (folded_target >= '.' AND folded_target < '/' AND (" + endings.map { _ in "folded_target LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + "))"
            + " OR (trim(folded_target, ' /') IN (\(placeholders(count: sortedExactTargets.count))) AND (folded_target < '!' OR (folded_target >= '/' AND folded_target < '0')"
            + paddedTargetStarts.map { _ in " OR (folded_target > ? AND folded_target < ?)" }.joined() + "))"
        let targetArguments = StatementArguments(sortedExactTargets) + StatementArguments(endings) + StatementArguments(sortedExactTargets)
            + StatementArguments(paddedTargetStarts.flatMap { exactTarget in [exactTarget, exactTarget + "0"] })
        return ("path IN (SELECT source FROM links WHERE \(targetCondition) UNION SELECT path FROM property_links WHERE \(targetCondition))",
                targetArguments + targetArguments)
    }

    /// Every trailing part of `path`, from its whole path to its file name, with and
    /// without the extension, each also rooted with `/`, folded as the index stores link
    /// targets: `A/B/Note.md` gives `b/note`, `/a/b/note.md`, `note` and so on.
    private static func trailingPathForms(of path: VaultPath) -> [String] {
        let components = path.rawValue.split(separator: "/").map(String.init)
        var forms: [String] = []
        for firstComponent in components.indices {
            let trailingPath = components[firstComponent...].joined(separator: "/")
            for form in [trailingPath, (trailingPath as NSString).deletingPathExtension] { forms += [form, "/" + form] }
        }
        return forms.map(foldedKey)
    }

    static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    // MARK: Records

    /// A `files` row as a record needs it.
    struct IndexedFileRow {
        let path: String
        let size: Int
        let modifiedInterval: Double
        let createdInterval: Double?

        init(path: String, size: Int, modifiedInterval: Double, createdInterval: Double?) {
            self.path = path
            self.size = size
            self.modifiedInterval = modifiedInterval
            self.createdInterval = createdInterval
        }

        /// A row selected with at least `path, size, modified, created`.
        init(_ row: Row) {
            self.init(path: row["path"], size: row["size"], modifiedInterval: row["modified"], createdInterval: row["created"])
        }
    }

    static func records(forPaths paths: [String], contents: BaseRecordContents = .everything, in database: Database) throws -> [BaseFileRecord] {
        var fileRows: [IndexedFileRow] = []
        fileRows.reserveCapacity(paths.count)
        for chunk in chunked(paths) {
            for row in try Row.fetchAll(database, sql: "SELECT path, size, modified, created FROM files WHERE path IN (\(placeholders(count: chunk.count)))",
                                        arguments: StatementArguments(chunk)) {
                fileRows.append(IndexedFileRow(row))
            }
        }
        // `IN` returns rows in the index's order; the records keep the order asked for.
        let positions = Dictionary(paths.enumerated().map { position, path in (path, position) }, uniquingKeysWith: { first, _ in first })
        fileRows.sort { leftRow, rightRow in positions[leftRow.path, default: 0] < positions[rightRow.path, default: 0] }
        return try records(for: fileRows, contents: contents, in: database)
    }

    private static func chunked(_ paths: [String]) -> [ArraySlice<String>] {
        stride(from: 0, to: paths.count, by: relatedRowChunkSize).map { chunkStart in paths[chunkStart..<min(chunkStart + relatedRowChunkSize, paths.count)] }
    }

    /// Records for these rows, in their order, read a page of files at a time, with what
    /// `contents` keeps: a property it leaves out is not decoded, and tags or links it
    /// leaves out are not read.
    static func records(for fileRows: [IndexedFileRow], contents: BaseRecordContents, in database: Database) throws -> [BaseFileRecord] {
        guard !fileRows.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var propertiesByPath: [String: [BaseFrontmatterEntry]] = [:]
        var tagsByPath: [String: [String]] = [:]
        var linksByPath: [String: [BaseRecordLink]] = [:]
        for chunk in chunked(fileRows.map(\.path)) {
            let chunkPlaceholders = placeholders(count: chunk.count)
            let chunkArguments = StatementArguments(chunk)
            let propertyRows = try Row.fetchCursor(database, sql: "SELECT path, key, node FROM properties WHERE path IN (\(chunkPlaceholders)) ORDER BY path, position",
                                                   arguments: chunkArguments)
            while let row = try propertyRows.next() {
                let key: String = row["key"]
                guard contents.keepsProperty(named: key) else { continue }
                let encodedNode: String = row["node"]
                // A row that does not decode is a stale cache entry; the property is skipped
                // rather than failing the whole base.
                guard let node = decodedScalarNode(encodedNode) ?? (try? decoder.decode(BaseFrontmatterNode.self, from: Data(encodedNode.utf8))) else { continue }
                propertiesByPath[row["path"], default: []].append(BaseFrontmatterEntry(key: key, node: node))
            }
            if contents.keepsTags {
                for row in try Row.fetchAll(database, sql: "SELECT path, tag FROM tags WHERE path IN (\(chunkPlaceholders))", arguments: chunkArguments) {
                    tagsByPath[row["path"], default: []].append(row["tag"])
                }
            }
            if contents.keepsLinks {
                for row in try Row.fetchAll(database, sql: "SELECT source, target, isWiki, isEmbed FROM links WHERE source IN (\(chunkPlaceholders))", arguments: chunkArguments) {
                    linksByPath[row["source"], default: []].append(BaseRecordLink(target: row["target"], isEmbed: row["isEmbed"], isWiki: row["isWiki"]))
                }
            }
        }
        return try fileRows.map { fileRow in
            let modifiedDate = Date(timeIntervalSince1970: fileRow.modifiedInterval)
            return BaseFileRecord(path: try VaultPath(fileRow.path), size: max(fileRow.size, 0),
                                  createdDate: fileRow.createdInterval.map(Date.init(timeIntervalSince1970:)) ?? modifiedDate,
                                  modifiedDate: modifiedDate, properties: propertiesByPath[fileRow.path] ?? [],
                                  tags: Array(Set(tagsByPath[fileRow.path] ?? [])).sorted(), links: linksByPath[fileRow.path] ?? [])
        }
    }
}

/// Synchronous lookups for `BaseEvaluator`, backed by the index database. Every GRDB
/// database reader (a queue or a pool) is safe to share across threads.
///
/// One provider serves one run of a base. A base that asks about a few links reads them one by
/// one. One that asks about more, as a `file.backlinks` column does per row, loads the vault's
/// names and links once, so later answers cost no read: one read per link would be 31,748
/// rows scanned per partial path, and thousands of reads for a large base. Records of files
/// outside the rows are read together with their neighbours (`BaseRecordReadAhead`).
public struct BaseIndexRecordProvider: BaseRecordProvider {
    /// Lookups answered by reading the database, before the names and links are loaded.
    public static let lookupsBeforeLoadingLinks = 8

    let databasePool: any DatabaseReader
    /// `BaseRecordProvider` cannot throw, so a lookup whose database read fails answers
    /// "nothing" and keeps the error here; `throwIfLookupFailed()` reports it after the run.
    private let lookupFailure = BaseLookupFailure()
    private let linkMemory: BaseLinkMemory
    /// Nil only for a test comparing against reads of one file each.
    private let recordReadAhead: BaseRecordReadAhead?

    init(databasePool: any DatabaseReader, lookupsBeforeLoadingLinks: Int = BaseIndexRecordProvider.lookupsBeforeLoadingLinks, readsRecordsAhead: Bool = true) {
        self.databasePool = databasePool
        linkMemory = BaseLinkMemory(lookupsBeforeLoading: lookupsBeforeLoadingLinks)
        recordReadAhead = readsRecordsAhead ? BaseRecordReadAhead() : nil
    }

    /// Database reads the lookups made so far, which a test counts.
    var lookupReadCount: Int { linkMemory.readCount }
    /// Records read for files asked about, neighbours included, which a test counts.
    var recordsReadAheadCount: Int { recordReadAhead?.recordsReadCount ?? 0 }

    public func record(at path: VaultPath) -> BaseFileRecord? {
        if let rememberedRecord = recordReadAhead?.rememberedRecord(at: path) { return rememberedRecord }
        guard let recordReadAhead else {
            return read { database in try VaultIndex.records(forPaths: [path.rawValue], in: database).first } ?? nil
        }
        let fileCount = recordReadAhead.filesToReadForNextMiss()
        let records = read { database in
            try VaultIndex.records(forPaths: try recordReadAhead.pathsToRead(around: path, fileCount: fileCount, in: database), in: database)
        } ?? [] // Failed: the error is kept, and the run shows it.
        recordReadAhead.remember(records)
        return recordReadAhead.rememberedRecord(at: path)
    }

    public func resolveLinkTarget(_ target: String, from source: VaultPath, isWiki: Bool) -> VaultPath? {
        if let loadedLinks = loadedLinksAfterThisLookup() {
            let resolvedPaths = loadedLinks.resolver.resolve(target, from: source, isWiki: isWiki)
            // A stored path is a valid one; one that is not names nothing.
            return resolvedPaths.first.flatMap { path in try? VaultPath(path) } // Not valid: names nothing.
        }
        guard let resolvedPaths = read({ database in try VaultIndex.resolvedPaths(target, from: source, isWiki: isWiki, in: database) }),
              let closestPath = resolvedPaths.first else { return nil }
        return closestPath
    }

    public func backlinks(to path: VaultPath) -> [VaultPath] {
        if let loadedLinks = loadedLinksAfterThisLookup() { return loadedLinks.backlinks[path.rawValue] ?? [] }
        return read { database in try VaultIndex.backlinkSources(to: path, includesPropertyLinks: true, in: database) } ?? []
    }

    /// The vault's names and links once enough lookups asked for them; nil before, and when
    /// loading them failed, whose error is kept like a lookup's.
    private func loadedLinksAfterThisLookup() -> BaseLinkMemory.LoadedLinks? {
        linkMemory.loadedLinksAfterLookup {
            read { database in try BaseLinkMemory.LoadedLinks(database: database) }
        }
    }

    /// Throws the first database error a lookup met, so a base shows the failure
    /// instead of values computed from missing records, links or backlinks.
    public func throwIfLookupFailed() throws {
        if let error = lookupFailure.firstError { throw error }
    }

    private func read<Answer>(_ lookup: (Database) throws -> Answer) -> Answer? {
        linkMemory.countRead()
        do { return try databasePool.read(lookup) } catch {
            lookupFailure.record(error)
            return nil
        }
    }
}

/// The vault's names and links in memory for one run of a base, loaded once when the run asks
/// for enough of them, and let go with the provider. The evaluator may call from any thread.
final class BaseLinkMemory: Sendable {
    struct LoadedLinks: Sendable {
        let resolver: GraphLinkResolver
        /// The notes linking to each file, sorted, as `VaultIndex.backlinkSources` finds them.
        let backlinks: [String: [VaultPath]]

        init(database: Database) throws {
            let resolver = try GraphLinkResolver(database: database)
            self.resolver = resolver
            let rows = try Row.fetchAll(database,
                sql: "SELECT DISTINCT source, target, isWiki FROM links UNION SELECT DISTINCT path, target, 1 FROM property_links")
            var sourcesByDestination: [String: Set<VaultPath>] = [:]
            // A link resolves the same way from every note in one folder.
            var destinationsByLink: [String: [String]] = [:]
            for row in rows {
                guard let source = try? VaultPath(row["source"] as String) else { continue } // A row with no valid path links nothing.
                let target: String = row["target"]
                let isWiki: Bool = row["isWiki"]
                let linkKey = (isWiki ? "w" : "m") + source.parent.rawValue + "\u{0}" + target
                let destinations: [String]
                if let knownDestinations = destinationsByLink[linkKey] {
                    destinations = knownDestinations
                } else {
                    destinations = resolver.backlinkDestinations(ofTarget: target, from: source, isWiki: isWiki)
                    destinationsByLink[linkKey] = destinations
                }
                for destination in destinations { sourcesByDestination[destination, default: []].insert(source) }
            }
            backlinks = sourcesByDestination.mapValues { sources in sources.sorted() }
        }
    }

    private struct State {
        var lookupCount = 0
        var readCount = 0
        var loadedLinks: LoadedLinks?
        var hasFailedToLoad = false
    }

    private let lookupsBeforeLoading: Int
    private let state = Mutex(State())

    init(lookupsBeforeLoading: Int) {
        self.lookupsBeforeLoading = lookupsBeforeLoading
    }

    var readCount: Int { state.withLock { state in state.readCount } }

    func countRead() {
        state.withLock { state in state.readCount += 1 }
    }

    func loadedLinksAfterLookup(load: () -> LoadedLinks?) -> LoadedLinks? {
        let shouldLoad = state.withLock { state -> Bool in
            state.lookupCount += 1
            return state.loadedLinks == nil && !state.hasFailedToLoad && state.lookupCount > lookupsBeforeLoading
        }
        guard shouldLoad else { return state.withLock { state in state.loadedLinks } }
        let loadedLinks = load()
        state.withLock { state in
            state.loadedLinks = loadedLinks
            state.hasFailedToLoad = loadedLinks == nil
        }
        return loadedLinks
    }
}

/// The first error of a provider's lookups, shared by every copy of the provider. The
/// evaluator may call the provider from any thread, so the error sits behind a mutex.
final class BaseLookupFailure: Sendable {
    private let storedError = Mutex<(any Error)?>(nil)

    var firstError: (any Error)? { storedError.withLock { error in error } }

    func record(_ error: any Error) {
        storedError.withLock { storedError in
            if storedError == nil { storedError = error }
        }
    }
}

extension VaultIndex {
    /// Decodes the stored JSON of the most common property value, a scalar such as
    /// `{"scalar":{"text":"EE330","isPlain":true}}` (keys in either order), without
    /// `JSONDecoder`, which dominates record loading. The only escape it reads is `\/`,
    /// which `JSONEncoder` writes for every slash in a path or web address. Anything else,
    /// including any other escape or a control character, returns nil so the caller falls
    /// back to `JSONDecoder`; both paths decode identically.
    static func decodedScalarNode(_ encodedNode: String) -> BaseFrontmatterNode? {
        var remainder = encodedNode.utf8[...]
        func consume(_ literal: String) -> Bool {
            guard remainder.starts(with: literal.utf8) else { return false }
            remainder = remainder.dropFirst(literal.utf8.count)
            return true
        }
        guard consume("{\"scalar\":{") else { return nil }
        var text: String?
        var isPlain: Bool?
        for fieldIndex in 0..<2 {
            if fieldIndex > 0 { guard consume(",") else { return nil } }
            if text == nil, consume("\"text\":\"") {
                var textBytes: [UInt8] = []
                var isEscaped = false
                while let byte = remainder.popFirst() {
                    if isEscaped {
                        guard byte == UInt8(ascii: "/") else { return nil }
                        textBytes.append(byte)
                        isEscaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        isEscaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        text = String(decoding: textBytes, as: UTF8.self)
                        break
                    } else {
                        guard byte >= 0x20 else { return nil }
                        textBytes.append(byte)
                    }
                }
                guard text != nil else { return nil }
            } else if isPlain == nil, consume("\"isPlain\":") {
                if consume("true") { isPlain = true } else if consume("false") { isPlain = false } else { return nil }
            } else {
                return nil
            }
        }
        guard consume("}}"), remainder.isEmpty, let text, let isPlain else { return nil }
        return .scalar(text: text, isPlain: isPlain)
    }
}
