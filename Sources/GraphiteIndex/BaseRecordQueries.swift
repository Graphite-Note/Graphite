import Foundation
import GRDB
import GraphiteCore
import Synchronization

/// Base queries over the index: bounded record loading with SQL pre-filtering, and a
/// synchronous lookup provider for the evaluator.
extension VaultIndex {
    /// Records a base loads when its filters give the index nothing to narrow by.
    public static let defaultBaseRecordLimit = 5_000
    /// Upper bound for any caller-provided limit, to keep memory bounded.
    public static let maximumBaseRecordLimit = 20_000
    /// Paths per `IN (…)` statement when loading related rows.
    private static let relatedRowChunkSize = 500
    /// Files a written link target may name before a `hasLink` requirement stops
    /// narrowing the query, which keeps the statement's argument list small.
    private static let maximumPrefilterLinkDestinations = 32

    /// Files that can match a base, with their properties, tags and links. Loads at most
    /// `limit` records in path order; `BaseRecordBatch.isTruncated` reports when more
    /// files passed the pre-filter.
    public func baseRecords(matching prefilter: BaseRecordPrefilter, limit: Int = VaultIndex.defaultBaseRecordLimit) throws -> BaseRecordBatch {
        let boundedLimit = min(max(limit, 1), Self.maximumBaseRecordLimit)
        return try databasePool.read { database in
            let (whereClause, arguments) = try Self.sqlCondition(for: prefilter, in: database)
            let paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE \(whereClause) ORDER BY path LIMIT ?", arguments: arguments + [boundedLimit + 1])
            var candidateCount = paths.count
            if paths.count > boundedLimit {
                candidateCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files WHERE \(whereClause)", arguments: arguments) ?? paths.count
            }
            let records = try Self.records(forPaths: Array(paths.prefix(boundedLimit)), in: database)
            return BaseRecordBatch(records: records, candidateCount: candidateCount)
        }
    }

    /// One file's record, for `this` or a file outside the query.
    public func baseRecord(at path: VaultPath) throws -> BaseFileRecord? {
        try databasePool.read { database in try Self.records(forPaths: [path.rawValue], in: database).first }
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

    static func sqlCondition(for prefilter: BaseRecordPrefilter, in database: Database) throws -> (String, StatementArguments) {
        var clauses: [String] = []
        var arguments = StatementArguments()
        for requirement in prefilter.requirements {
            switch requirement {
            case .inAnyFolder(let folders):
                guard !folders.isEmpty, isSafeForCaseInsensitiveSQL(folders) else { continue }
                clauses.append("(" + folders.map { _ in "path LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + " OR \(storedTextIsNotASCII("path")))")
                arguments += StatementArguments(folders.map { folder in likePattern(escaping: folder) + "/%" })
            case .hasAnyTag(let tags):
                guard !tags.isEmpty, isSafeForCaseInsensitiveSQL(tags) else { continue }
                let tagConditions = tags.map { _ in "tag = ? COLLATE NOCASE OR tag LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
                clauses.append("path IN (SELECT path FROM tags WHERE \(tagConditions) OR \(storedTextIsNotASCII("tag")))")
                for tag in tags { arguments += [tag, likePattern(escaping: tag) + "/%"] }
            case .hasAnyExtension(let fileExtensions):
                // A file without an extension has `file.ext == ""`, which no `%.` pattern matches.
                guard !fileExtensions.isEmpty, !fileExtensions.contains(where: \.isEmpty), isSafeForCaseInsensitiveSQL(fileExtensions) else { continue }
                clauses.append("(" + fileExtensions.map { _ in "path LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + ")")
                arguments += StatementArguments(fileExtensions.map { fileExtension in "%." + likePattern(escaping: fileExtension) })
            case .hasAnyProperty(let keys):
                guard !keys.isEmpty, isSafeForCaseInsensitiveSQL(keys) else { continue }
                clauses.append("path IN (SELECT path FROM properties WHERE " + keys.map { _ in "key = ? COLLATE NOCASE" }.joined(separator: " OR ")
                               + " OR \(storedTextIsNotASCII("key")))")
                arguments += StatementArguments(keys)
            case .linksTo(let destination):
                guard let (linkClause, linkArguments) = try linkCondition(for: destination, in: database) else { continue }
                clauses.append(linkClause)
                arguments += linkArguments
            }
        }
        for requirement in prefilter.propertyTextRequirements {
            guard isSafeForCaseInsensitiveSQL([requirement.key, requirement.text]) else { continue }
            // The stored node is the value's JSON. A value with `%` or non-ASCII text can
            // still equal the requirement once the evaluator decodes or normalizes it.
            clauses.append("path IN (SELECT path FROM properties WHERE (key = ? COLLATE NOCASE OR \(storedTextIsNotASCII("key")))"
                           + " AND (node LIKE ? ESCAPE '\\' OR instr(node, '%') > 0 OR \(storedTextIsNotASCII("node"))))")
            arguments += [requirement.key, "%" + likePattern(escaping: requirement.text) + "%"]
        }
        return (clauses.isEmpty ? "1" : clauses.joined(separator: " AND "), arguments)
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

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    // MARK: Records

    static func records(forPaths paths: [String], in database: Database) throws -> [BaseFileRecord] {
        guard !paths.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var fileRows: [String: Row] = [:]
        var propertiesByPath: [String: [BaseFrontmatterEntry]] = [:]
        var tagsByPath: [String: [String]] = [:]
        var linksByPath: [String: [BaseRecordLink]] = [:]
        var chunkStart = 0
        while chunkStart < paths.count {
            let chunk = Array(paths[chunkStart..<min(chunkStart + relatedRowChunkSize, paths.count)])
            chunkStart += relatedRowChunkSize
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let chunkArguments = StatementArguments(chunk)
            for row in try Row.fetchAll(database, sql: "SELECT path, size, modified, created FROM files WHERE path IN (\(placeholders))", arguments: chunkArguments) {
                fileRows[row["path"]] = row
            }
            for row in try Row.fetchAll(database, sql: "SELECT path, key, node FROM properties WHERE path IN (\(placeholders)) ORDER BY path, position", arguments: chunkArguments) {
                let encodedNode: String = row["node"]
                // A row that does not decode is a stale cache entry; the property is skipped
                // rather than failing the whole base.
                guard let node = decodedScalarNode(encodedNode) ?? (try? decoder.decode(BaseFrontmatterNode.self, from: Data(encodedNode.utf8))) else { continue }
                propertiesByPath[row["path"], default: []].append(BaseFrontmatterEntry(key: row["key"], node: node))
            }
            for row in try Row.fetchAll(database, sql: "SELECT path, tag FROM tags WHERE path IN (\(placeholders))", arguments: chunkArguments) {
                tagsByPath[row["path"], default: []].append(row["tag"])
            }
            for row in try Row.fetchAll(database, sql: "SELECT source, target, isWiki, isEmbed FROM links WHERE source IN (\(placeholders))", arguments: chunkArguments) {
                linksByPath[row["source"], default: []].append(BaseRecordLink(target: row["target"], isEmbed: row["isEmbed"], isWiki: row["isWiki"]))
            }
        }
        return try paths.compactMap { pathText in
            guard let fileRow = fileRows[pathText] else { return nil }
            let modifiedDate = Date(timeIntervalSince1970: fileRow["modified"])
            let createdInterval: Double? = fileRow["created"]
            return BaseFileRecord(path: try VaultPath(pathText), size: max(fileRow["size"] as Int, 0),
                                  createdDate: createdInterval.map(Date.init(timeIntervalSince1970:)) ?? modifiedDate,
                                  modifiedDate: modifiedDate, properties: propertiesByPath[pathText] ?? [],
                                  tags: Array(Set(tagsByPath[pathText] ?? [])).sorted(), links: linksByPath[pathText] ?? [])
        }
    }
}

/// Synchronous lookups for `BaseEvaluator`, backed by the index database. Every GRDB
/// database reader (a queue or a pool) is safe to share across threads.
///
/// One provider serves one run of a base. A base that asks about a few links reads them one by
/// one. One that asks about more, as a `file.backlinks` column does per row, loads the vault's
/// names and links once, so later answers cost no read: one read per link would be 31,748
/// rows scanned per partial path, and thousands of reads for a large base.
public struct BaseIndexRecordProvider: BaseRecordProvider {
    /// Lookups answered by reading the database, before the names and links are loaded.
    public static let lookupsBeforeLoadingLinks = 8

    let databasePool: any DatabaseReader
    /// `BaseRecordProvider` cannot throw, so a lookup whose database read fails answers
    /// "nothing" and keeps the error here; `throwIfLookupFailed()` reports it after the run.
    private let lookupFailure = BaseLookupFailure()
    private let linkMemory: BaseLinkMemory

    init(databasePool: any DatabaseReader, lookupsBeforeLoadingLinks: Int = BaseIndexRecordProvider.lookupsBeforeLoadingLinks) {
        self.databasePool = databasePool
        linkMemory = BaseLinkMemory(lookupsBeforeLoading: lookupsBeforeLoadingLinks)
    }

    /// Database reads the lookups made so far, which a test counts.
    var lookupReadCount: Int { linkMemory.readCount }

    public func record(at path: VaultPath) -> BaseFileRecord? {
        read { database in try VaultIndex.records(forPaths: [path.rawValue], in: database).first } ?? nil
    }

    public func resolveLinkTarget(_ target: String, from source: VaultPath, isWiki: Bool) -> VaultPath? {
        if let loadedLinks = loadedLinksAfterThisLookup() {
            let resolvedPaths = loadedLinks.resolver.resolve(target, from: source, isWiki: isWiki)
            return resolvedPaths.count == 1 ? resolvedPaths.first.flatMap { path in try? VaultPath(path) } : nil
        }
        guard let resolvedPaths = read({ database in try VaultIndex.resolvedPaths(target, from: source, isWiki: isWiki, in: database) }),
              resolvedPaths.count == 1 else { return nil }
        return resolvedPaths.first
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
            let rows = try Row.fetchAll(database, sql: "SELECT DISTINCT source, target, isWiki FROM links UNION SELECT DISTINCT path, target, 1 FROM property_links")
            var sourcesByDestination: [String: Set<VaultPath>] = [:]
            // A link resolves the same way from every note in one folder.
            var destinationsByLink: [String: [String]] = [:]
            for row in rows {
                guard let source = try? VaultPath(row["source"] as String) else { continue }
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
