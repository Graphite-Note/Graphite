/**
 * File: VaultIndex.swift
 * ----------------------
 * Layer: Index
 * Description: The vault's SQLite index of files, text, links, tags and aliases, and how links resolve through it.
 *
 * Authors: Bahey Shalash
 * Version: 0.10
 * Date: 04/11/2026
 */

import Foundation
import CryptoKit
import GRDB
import GraphiteCore

public struct IndexedFile: Sendable {
    public let path: VaultPath
    public let size: Int
    public let modified: Date
    /// Creation date for `file.ctime` in bases; the modification date when unknown.
    public let created: Date?
    /// The file's text: a note's Markdown, or a canvas's JSON, which is read for its links only.
    public let markdown: String?
    /// The note was read and is not UTF-8 text. Its content cannot become searchable
    /// until the file changes, so an unchanged file is not read again on every scan.
    let isUnreadableAsText: Bool
    /// The file is in the cloud, so its text is unknown until it is downloaded.
    let isNotDownloaded: Bool
    public init(path: VaultPath, size: Int, modified: Date, markdown: String?) {
        self.init(path: path, size: size, modified: modified, created: nil, markdown: markdown)
    }
    public init(path: VaultPath, size: Int, modified: Date, created: Date?, markdown: String?) {
        self.init(path: path, size: size, modified: modified, created: created, markdown: markdown, isUnreadableAsText: false)
    }
    init(path: VaultPath, size: Int, modified: Date, created: Date?, markdown: String?, isUnreadableAsText: Bool, isNotDownloaded: Bool = false) {
        self.path = path; self.size = size; self.modified = modified; self.created = created; self.markdown = markdown
        self.isUnreadableAsText = isUnreadableAsText
        self.isNotDownloaded = isNotDownloaded
    }
}

/// The `files.contentIndexed` column: whether a note's text is in the search table.
enum IndexedContentState: Int {
    /// Not read: not a note, too large, or reading failed. A readable note in this state is
    /// read again by the next scan.
    case notRead = 0
    case indexed = 1
    /// Read, but not UTF-8 text.
    case unreadableAsText = 2
    /// Read as text, but a canvas Graphite cannot read (damaged, or beyond its bounds): its
    /// links are unknown, so it has no link rows and a move looks for moved paths in its bytes.
    case unreadableCanvas = 3
    /// In the cloud at this size and date. A scan asks about it again only once the file system
    /// no longer marks it as a placeholder, not of the file provider on every launch.
    case notDownloaded = 4
}

public struct IndexingReport: Sendable {
    public let discoveredFiles: Int
    /// Files this scan listed and looked at, which a scan of one folder keeps to that folder's.
    public let examinedFiles: Int
    public let updatedFiles: Int
    public let pendingContentFiles: Int
    public let failedPaths: [String]
    /// Rows of files no longer in the vault, removed by the scan.
    public let prunedFiles: Int
    /// Whether what the index answers can differ from before the scan.
    public var changedAnything: Bool { updatedFiles > 0 || prunedFiles > 0 }
}

/// What the index asks about a file in the cloud. The answers come through the file provider,
/// so a test gives its own to count them.
public struct CloudFileStatus: Sendable {
    /// Whether the file is in the cloud and not downloaded; asked of the file provider, which
    /// inspects the item. Reading such a file would start a download.
    let isNotDownloaded: @Sendable (URL) -> Bool
    /// Whether the file system still marks the file as a placeholder without its contents. One
    /// system call per file, which the provider does not hear of.
    let isDatalessPlaceholder: @Sendable (URL) -> Bool

    public init(isNotDownloaded: @escaping @Sendable (URL) -> Bool, isDatalessPlaceholder: @escaping @Sendable (URL) -> Bool) {
        self.isNotDownloaded = isNotDownloaded
        self.isDatalessPlaceholder = isDatalessPlaceholder
    }

    public static let live = CloudFileStatus(isNotDownloaded: { location in
        (try? location.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .notDownloaded
    }, isDatalessPlaceholder: { location in
        var fileStatus = stat()
        return lstat(location.path, &fileStatus) == 0 && fileStatus.st_flags & UInt32(SF_DATALESS) != 0
    })
}

/// SQLite is an inventory and search cache. It never writes the user's documents.
public actor VaultIndex {
    /// Larger notes stay in the inventory but are not read for full-text search.
    public static let maximumIndexedNoteBytes = 8 * 1_048_576
    /// A write batch is flushed once it holds this much note text, as well as after
    /// `maximumBatchFileCount` files, so a folder of large notes keeps memory bounded.
    static let maximumBatchContentBytes = 4 * 1_048_576
    static let maximumBatchFileCount = 64
    /// Readers at the same time beside the writer: long reads such as a graph or a base leave
    /// a link tap or the quick switcher a reader of its own.
    static let maximumReaderCount = 4
    /// Page cache of each connection. A reader serves short reads, and there are several.
    private static let writerCacheKilobytes = 8192
    private static let readerCacheKilobytes = 2048
    /// One writer and concurrent readers. Internal so the base record queries in
    /// `BaseRecordQueries.swift` share it.
    nonisolated let databasePool: DatabasePool
    private let cloudFileStatus: CloudFileStatus
    private var isScanning = false
    /// The generation of the scan in progress, which the rows it writes carry.
    private var activeScanGeneration: String?
    /// Files `refresh` wrote or removed during the scan in progress, with the modification
    /// date it wrote (`distantFuture` for a removal). The scan may have read such a file
    /// earlier into a batch it has not written yet; that older reading must not replace them,
    /// and a note saved during a scan is not pruned when the scan ends.
    private var pathsRefreshedDuringScan: [String: Date] = [:]
    /// Tables holding one or more rows per file, keyed by the file's path.
    static let perFileTables = ["aliases", "tags", "headings", "properties", "property_links"]
    /// Deletes one file's search row. By row identity: the search table has no ordinary index on
    /// its path column, so deleting by path would read every row of it.
    static let searchRowDeletion = "DELETE FROM search WHERE rowid = (SELECT rowid FROM files WHERE path = ?)"

    /// How long, in seconds, a write waits for another connection's lock before it fails.
    static let busyTimeout: TimeInterval = 5

    public init(databaseURL: URL, cloudFileStatus: CloudFileStatus = .live) throws {
        self.cloudFileStatus = cloudFileStatus
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        // Another process may hold the write lock for a moment (a second copy of the app, or
        // later the share extension): wait for it rather than fail with "database is locked".
        configuration.busyMode = .timeout(Self.busyTimeout)
        configuration.maximumReaderCount = Self.maximumReaderCount
        configuration.prepareDatabase { database in
            let cacheKilobytes = database.configuration.readonly ? Self.readerCacheKilobytes : Self.writerCacheKilobytes
            try database.execute(sql: "PRAGMA cache_size = -\(cacheKilobytes)")
            database.add(function: RegularExpressionFunction.function)
        }
        databasePool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("inventory-and-links-1") { database in
            try database.execute(sql: """
                CREATE TABLE files (
                  path TEXT PRIMARY KEY, basename TEXT NOT NULL, title TEXT NOT NULL,
                  size INTEGER NOT NULL, modified REAL NOT NULL, generation TEXT NOT NULL,
                  contentIndexed INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX files_basename ON files(basename COLLATE NOCASE);
                CREATE VIRTUAL TABLE search USING fts5(path, title, body, tokenize='unicode61 remove_diacritics 2');
                CREATE TABLE links (source TEXT NOT NULL, target TEXT NOT NULL, isWiki INTEGER NOT NULL, isEmbed INTEGER NOT NULL);
                CREATE INDEX links_source ON links(source);
                CREATE INDEX links_target ON links(target COLLATE NOCASE);
                CREATE TABLE aliases (alias TEXT NOT NULL, path TEXT NOT NULL);
                CREATE INDEX aliases_name ON aliases(alias COLLATE NOCASE);
                CREATE TABLE tags (tag TEXT NOT NULL, path TEXT NOT NULL);
                CREATE INDEX tags_name ON tags(tag COLLATE NOCASE);
                CREATE TABLE headings (heading TEXT NOT NULL, path TEXT NOT NULL);
                """)
        }
        migrator.registerMigration("bounded-update-lookups-2") { database in
            try database.execute(sql: """
                CREATE INDEX aliases_path ON aliases(path);
                CREATE INDEX tags_path ON tags(path);
                CREATE INDEX headings_path ON headings(path);
                """)
        }
        migrator.registerMigration("filename-search-and-row-identities-3") { database in
            try database.execute(sql: """
                CREATE VIRTUAL TABLE rebuilt_search USING fts5(path, title, body, tokenize='unicode61 remove_diacritics 2');
                INSERT INTO rebuilt_search(rowid, path, title, body)
                  SELECT files.rowid, files.path, search.title, search.body FROM files JOIN search ON files.path = search.path;
                DROP TABLE search;
                ALTER TABLE rebuilt_search RENAME TO search;
                """)
        }
        migrator.registerMigration("vault-path-markdown-link-targets-4") { database in
            // Link targets are stored differently now. The index is a disposable cache,
            // so it is emptied and the next scan rebuilds it from the vault.
            for table in ["search", "links", "aliases", "tags", "headings", "files"] { try database.execute(sql: "DELETE FROM \(table)") }
        }
        migrator.registerMigration("base-properties-and-creation-dates-5") { database in
            // Frontmatter for bases is stored as parsed YAML structure (JSON), not as
            // typed values: `.obsidian/types.json` can change without a rescan.
            try database.execute(sql: """
                CREATE TABLE properties (path TEXT NOT NULL, position INTEGER NOT NULL, key TEXT NOT NULL, node TEXT NOT NULL);
                CREATE INDEX properties_path ON properties(path);
                CREATE INDEX properties_key ON properties(key COLLATE NOCASE);
                CREATE TABLE property_links (path TEXT NOT NULL, target TEXT NOT NULL);
                CREATE INDEX property_links_path ON property_links(path);
                CREATE INDEX property_links_target ON property_links(target COLLATE NOCASE);
                ALTER TABLE files ADD COLUMN created REAL;
                """)
            // Rows written before this migration lack properties and creation dates. An
            // impossible size makes the next scan re-read every file, while existing
            // search rows keep working until then.
            try database.execute(sql: "UPDATE files SET size = -1")
        }
        migrator.registerMigration("unicode-name-keys-6") { database in
            // Names are matched by a normalized key, so a link finds a file whatever
            // Unicode form its name is stored in. Rows gain keys on the next scan.
            try database.execute(sql: """
                ALTER TABLE files ADD COLUMN path_key TEXT;
                ALTER TABLE files ADD COLUMN name_key TEXT;
                CREATE INDEX files_path_key ON files(path_key COLLATE NOCASE);
                CREATE INDEX files_name_key ON files(name_key COLLATE NOCASE);
                UPDATE files SET size = -1;
                """)
        }
        migrator.registerMigration("search-whole-note-text-7") { database in
            // Search now reads the whole note, properties included, and match positions
            // are positions in the file. Every note is read again on the next scan.
            try database.execute(sql: "UPDATE files SET size = -1")
        }
        migrator.registerMigration("case-folded-link-keys-8") { database in
            // SQLite's NOCASE and LIKE fold ASCII letters only, so `[[éclair]]` missed
            // `Éclair.md`. Keys folded in Swift (`foldedKey`) are stored and indexed for
            // exact lookups. Existing rows get them here, without a rescan. The NOCASE
            // indexes on `path_key` and `name_key` served only the lookups these replace,
            // so they are dropped rather than kept up to date on every write.
            database.add(function: Self.foldedKeyFunction)
            defer { database.remove(function: Self.foldedKeyFunction) }
            try database.execute(sql: """
                ALTER TABLE files ADD COLUMN folded_path TEXT;
                ALTER TABLE files ADD COLUMN folded_name TEXT;
                ALTER TABLE aliases ADD COLUMN folded_alias TEXT;
                ALTER TABLE links ADD COLUMN folded_target TEXT;
                ALTER TABLE property_links ADD COLUMN folded_target TEXT;
                UPDATE files SET folded_path = \(Self.foldedKeyFunctionName)(path), folded_name = \(Self.foldedKeyFunctionName)(basename);
                UPDATE aliases SET folded_alias = \(Self.foldedKeyFunctionName)(alias);
                UPDATE links SET folded_target = \(Self.foldedKeyFunctionName)(target);
                UPDATE property_links SET folded_target = \(Self.foldedKeyFunctionName)(target);
                CREATE INDEX files_folded_path ON files(folded_path);
                CREATE INDEX files_folded_name ON files(folded_name);
                CREATE INDEX aliases_folded_alias ON aliases(folded_alias);
                CREATE INDEX links_folded_target ON links(folded_target);
                CREATE INDEX property_links_folded_target ON property_links(folded_target);
                DROP INDEX files_path_key;
                DROP INDEX files_name_key;
                """)
        }
        migrator.registerMigration("markdown-link-written-targets-9") { database in
            // Markdown links are now stored as written (decoded) unless they are relative
            // to the note, so shortest and absolute-format links find their files. Every
            // note is read again on the next scan.
            try database.execute(sql: "UPDATE files SET size = -1")
        }
        migrator.registerMigration("unreadable-canvas-state-10") { database in
            // Canvases Graphite cannot read have their own content state; every canvas is read
            // again on the next scan to set it.
            try database.execute(sql: "UPDATE files SET size = -1 WHERE path LIKE '%.canvas'")
        }
        migrator.registerMigration("finished-scan-fact-11") { database in
            try database.execute(sql: "CREATE TABLE index_facts (name TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL)")
        }
        Self.registerNaturalFileNameOrderMigration(in: &migrator)
        try migrator.migrate(databasePool)
    }

    private static let finishedScanFact = "finishedScan"

    /// Whether a scan of the whole vault ended since the index was made or emptied, on this launch
    /// or an earlier one: the index is complete but for what changed since.
    public nonisolated func hasFinishedAScan() async throws -> Bool {
        try await readOnAReader { database in try Self.hasFinishedScanFact(in: database) }
    }

    private static func hasFinishedScanFact(in database: Database) throws -> Bool {
        try Bool.fetchOne(database, sql: "SELECT 1 FROM index_facts WHERE name = ?", arguments: [finishedScanFact]) ?? false
    }

    /// Text for matching names the way Obsidian does: ignoring case for every letter, not
    /// only ASCII, and whatever Unicode form the name is stored in.
    static func foldedKey(_ text: String) -> String {
        WikiLinkResolver.caseFoldedKey(text)
    }

    static let foldedKeyFunctionName = "graphite_folded_key"
    static let foldedKeyFunction = DatabaseFunction(foldedKeyFunctionName, argumentCount: 1, pure: true) { values in
        String.fromDatabaseValue(values[0]).map(foldedKey)
    }

    public static func cacheURL(for root: URL) throws -> URL {
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let identifier = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("Graphite/Indexes/\(identifier).sqlite")
    }

    /// Where a vault's index lives: named after the vault's identifier in the vault list,
    /// so it survives the app's folder moving, as iOS may do on an update. An index named
    /// after `legacyRoot`'s path, as earlier versions named it, is moved there once, and
    /// indexes left unused for 30 days (by vaults removed or moved) are deleted.
    public static func cacheURL(forVault vaultIdentifier: UUID, legacyRoot: URL, in cachesDirectory: URL? = nil) throws -> URL {
        let caches = try cachesDirectory ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = caches.appendingPathComponent("Graphite/Indexes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let location = directory.appendingPathComponent(vaultIdentifier.uuidString + ".sqlite")
        let legacyName = SHA256.hash(data: Data(legacyRoot.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let legacyLocation = directory.appendingPathComponent(legacyName + ".sqlite")
        if !FileManager.default.fileExists(atPath: location.path), FileManager.default.fileExists(atPath: legacyLocation.path) {
            // The database and its journal move together, or not at all.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: legacyLocation.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try? FileManager.default.moveItem(at: source, to: URL(fileURLWithPath: location.path + suffix))
            }
        }
        removeUnusedIndexes(in: directory, keeping: location)
        return location
    }

    /// Deletes a vault's index, as when it is removed from the vault list; it is a cache.
    public static func removeIndex(forVault vaultIdentifier: UUID, in cachesDirectory: URL? = nil) {
        guard let caches = cachesDirectory ?? (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) else { return }
        let location = caches.appendingPathComponent("Graphite/Indexes/" + vaultIdentifier.uuidString + ".sqlite")
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: location.path + suffix) }
    }

    private static func removeUnusedIndexes(in directory: URL, keeping keptLocation: URL, unusedFor age: TimeInterval = 30 * 86_400) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let locations = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let cutoff = Date.now.addingTimeInterval(-age)
        for databaseLocation in locations where databaseLocation.pathExtension == "sqlite" && databaseLocation.lastPathComponent != keptLocation.lastPathComponent {
            // The journal is written most recently when the index was last used.
            let lastUse = ["", "-wal"].compactMap { suffix in
                try? URL(fileURLWithPath: databaseLocation.path + suffix).resourceValues(forKeys: keys).contentModificationDate
            }.max() ?? .distantPast
            guard lastUse < cutoff else { continue }
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databaseLocation.path + suffix) }
        }
    }

    /// A file parsed for the index and ready to be written.
    struct PreparedFile: Sendable {
        let file: IndexedFile
        let semantics: NoteSemantics?
        /// Each frontmatter property's key and its YAML structure encoded as JSON.
        let encodedProperties: [(key: String, encodedNode: String)]
        let propertyLinkTargets: [String]

        /// The text full-text search reads. A canvas has none: its JSON is not prose, and
        /// Obsidian does not search canvases either.
        var searchableText: String {
            semantics == nil || DocumentKind(path: file.path) == .canvas ? "" : file.markdown ?? ""
        }

        /// A canvas whose text was read but that Graphite cannot read as a canvas.
        var isUnreadableCanvas: Bool {
            semantics == nil && file.markdown != nil && DocumentKind(path: file.path) == .canvas
        }
    }

    /// Whether a scan reads the file's text: notes, canvases for the links their cards make,
    /// and PDFs for the text of their text boxes (`PDFIndexText`).
    static func readsText(of path: VaultPath) -> Bool {
        let kind = DocumentKind(path: path)
        return kind == .markdown || kind == .canvas || kind == .pdf
    }

    /// Parses a file for the index. Static, so a scan runs it outside the actor and queries
    /// are not held up while a batch of notes is parsed.
    static func prepared(_ file: IndexedFile) throws -> PreparedFile {
        // Parsing leaves autoreleased objects behind; releasing them per note keeps a
        // batch of large notes from accumulating them until the batch ends.
        try autoreleasepool {
            let semantics: NoteSemantics?
            if let text = file.markdown, DocumentKind(path: file.path) == .canvas {
                semantics = try? CanvasLinks.semantics(ofCanvasText: text) // Unreadable: no links, and `isUnreadableCanvas` records it.
            } else if DocumentKind(path: file.path) == .pdf {
                semantics = file.markdown.map(NoteSemantics.plainText)
            } else {
                semantics = try file.markdown.map { text in try MarkdownSemantics.parse(text) }
            }
            let properties = semantics?.frontmatter.flatMap(BaseFrontmatter.entries(fromYAML:)) ?? []
            let encoder = JSONEncoder()
            let encodedProperties = try properties.map { entry in (key: entry.key, encodedNode: String(decoding: try encoder.encode(entry.node), as: UTF8.self)) }
            let propertyLinkTargets = BaseFrontmatter.links(in: properties).map { link in Self.storedLinkTarget(link.target, isWiki: link.isWiki, source: file.path) }
            return PreparedFile(file: file, semantics: semantics, encodedProperties: encodedProperties, propertyLinkTargets: propertyLinkTargets)
        }
    }

    public func update(_ files: [IndexedFile], generation: String) throws {
        // Parse outside the transaction. Limit batches at the caller for bounded memory.
        try write(files.map(Self.prepared), generation: generation)
    }

    private func write(_ preparedFiles: [PreparedFile], generation: String) throws {
        guard !preparedFiles.isEmpty else { return }
        try databasePool.write { database in
            // Cached statements: every file runs the same few dozen statements, and
            // compiling each one again per file cost more than executing it.
            let fileUpsert = try database.cachedStatement(sql: """
                INSERT INTO files (path, basename, title, size, modified, generation, contentIndexed, created,
                                   path_key, name_key, folded_path, folded_name, sort_name)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET basename=excluded.basename, title=excluded.title,
                  size=excluded.size, modified=excluded.modified, generation=excluded.generation,
                  contentIndexed=excluded.contentIndexed, created=excluded.created,
                  path_key=excluded.path_key, name_key=excluded.name_key,
                  folded_path=excluded.folded_path, folded_name=excluded.folded_name, sort_name=excluded.sort_name
                """)
            // FTS content columns have no ordinary B-tree index. Deleting by
            // path here would turn a full build into a quadratic table scan.
            let searchDeletion = try database.cachedStatement(sql: Self.searchRowDeletion)
            let searchInsertion = try database.cachedStatement(sql: "INSERT INTO search(rowid, path, title, body) SELECT rowid, path, ?, ? FROM files WHERE path = ?")
            let linkDeletion = try database.cachedStatement(sql: "DELETE FROM links WHERE source = ?")
            let perFileDeletions = try Self.perFileTables.map { table in try database.cachedStatement(sql: "DELETE FROM \(table) WHERE path = ?") }
            let propertyInsertion = try database.cachedStatement(sql: "INSERT INTO properties (path, position, key, node) VALUES (?, ?, ?, ?)")
            let propertyLinkInsertion = try database.cachedStatement(sql: "INSERT INTO property_links (path, target, folded_target) VALUES (?, ?, ?)")
            let linkInsertion = try database.cachedStatement(sql: "INSERT INTO links (source, target, isWiki, isEmbed, folded_target) VALUES (?, ?, ?, ?, ?)")
            let aliasInsertion = try database.cachedStatement(sql: "INSERT INTO aliases (alias, path, folded_alias) VALUES (?, ?, ?)")
            let tagInsertion = try database.cachedStatement(sql: "INSERT INTO tags VALUES (?, ?)")
            let headingInsertion = try database.cachedStatement(sql: "INSERT INTO headings VALUES (?, ?)")
            let storedContentState = try database.cachedStatement(sql: "SELECT contentIndexed FROM files WHERE path = ?")
            let generationTouch = try database.cachedStatement(sql: "UPDATE files SET generation = ? WHERE path = ?")
            for prepared in preparedFiles {
                let file = prepared.file
                let semantics = prepared.semantics
                // A note that left the device for the cloud is unreadable now, not empty: its text,
                // links, tags and headings stay as they were, and so do its size and date, so the
                // next scan reads it again once it is back or changed.
                if file.isNotDownloaded, semantics == nil,
                   try Int.fetchOne(storedContentState, arguments: [file.path.rawValue]) == IndexedContentState.indexed.rawValue {
                    try generationTouch.execute(arguments: [generation, file.path.rawValue])
                    continue
                }
                let title = semantics?.headings.first ?? file.path.stem
                let contentState: IndexedContentState = semantics != nil ? .indexed
                    : prepared.isUnreadableCanvas ? .unreadableCanvas : file.isUnreadableAsText ? .unreadableAsText
                    : file.isNotDownloaded ? .notDownloaded : .notRead
                try fileUpsert.execute(arguments: [file.path.rawValue, file.path.name, title, file.size, file.modified.timeIntervalSince1970, generation, contentState.rawValue,
                                                   (file.created ?? file.modified).timeIntervalSince1970,
                                                   WikiLinkResolver.comparisonKey(file.path.rawValue), WikiLinkResolver.comparisonKey(file.path.name),
                                                   Self.foldedKey(file.path.rawValue), Self.foldedKey(file.path.name), Self.naturalSortKey(file.path.name)])
                try searchDeletion.execute(arguments: [file.path.rawValue])
                // The whole text, frontmatter included: search finds property values too,
                // and a match's position is its position in the file.
                try searchInsertion.execute(arguments: [title, prepared.searchableText, file.path.rawValue])
                try linkDeletion.execute(arguments: [file.path.rawValue])
                for perFileDeletion in perFileDeletions { try perFileDeletion.execute(arguments: [file.path.rawValue]) }
                for (position, property) in prepared.encodedProperties.enumerated() {
                    try propertyInsertion.execute(arguments: [file.path.rawValue, position, property.key, property.encodedNode])
                }
                for target in Set(prepared.propertyLinkTargets) {
                    try propertyLinkInsertion.execute(arguments: [file.path.rawValue, target, Self.foldedKey(target)])
                }
                if let semantics {
                    for link in semantics.links {
                        let target = Self.storedLinkTarget(link, source: file.path)
                        try linkInsertion.execute(arguments: [file.path.rawValue, target, link.isWiki, link.isEmbed, Self.foldedKey(target)])
                    }
                    for alias in semantics.aliases {
                        try aliasInsertion.execute(arguments: [WikiLinkResolver.comparisonKey(alias), file.path.rawValue, Self.foldedKey(alias)])
                    }
                    for tag in semantics.tags { try tagInsertion.execute(arguments: [tag, file.path.rawValue]) }
                    for heading in semantics.headings { try headingInsertion.execute(arguments: [heading, file.path.rawValue]) }
                }
            }
        }
    }

    // The read-only queries below run outside the actor, straight on the database queue:
    // they do not wait while a scan reads and parses notes, and a cancelled caller
    // interrupts its query instead of letting it run to completion.

    /// The files a link can mean from `source`, the one it means first (`getFirstLinkpathDest`
    /// in Obsidian is this list's first): `WikiLinkResolver.closestFirst`.
    public nonisolated func resolve(_ target: String, from source: VaultPath, isWiki: Bool = true) async throws -> [VaultPath] {
        try await readOnAReader { database in try Self.resolvedPaths(target, from: source, isWiki: isWiki, in: database) }
    }

    /// The file each of these wikilinks means from `source`, in one read, as `resolve` chooses
    /// it; a link no file answers has no entry.
    public nonisolated func resolve(wikilinks targets: [String], from source: VaultPath) async throws -> [String: VaultPath] {
        try await readOnAReader { database in
            var resolved: [String: VaultPath] = [:]
            for target in targets {
                resolved[target] = try Self.resolvedPaths(target, from: source, isWiki: true, in: database).first
            }
            return resolved
        }
    }

    static func resolvedPaths(_ target: String, from source: VaultPath, isWiki: Bool, in database: Database) throws -> [VaultPath] {
        for candidate in WikiLinkResolver.directCandidates(target: target, source: source, isWiki: isWiki) {
            // Paths match case-insensitively, through the indexed folded key. Files whose
            // names differ only by case (possible on case-sensitive volumes) prefer the
            // exact spelling, and are otherwise returned together.
            let paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_path = ? ORDER BY path LIMIT 50",
                                            arguments: [foldedKey(candidate.rawValue)])
            guard !paths.isEmpty else { continue }
            let candidateKey = WikiLinkResolver.comparisonKey(candidate.rawValue)
            if let exactPath = paths.first(where: { path in WikiLinkResolver.comparisonKey(path) == candidateKey }) { return [try VaultPath(exactPath)] }
            return try paths.map(VaultPath.init)
        }
        let part = WikiLinkResolver.comparisonKey(lookupPathPart(of: target, isWiki: isWiki))
        guard !part.isEmpty, !part.contains(":") else { return [] }
        for fileName in WikiLinkResolver.fileNameVariants(for: part) {
            let paths: [String]
            if part.contains("/") {
                // A partial path, such as `[[covers/Book cover.png]]`, names the end of a
                // path, or the whole path when it starts at the vault root (`[[/Folder/Note]]`).
                let pathSuffix = foldedKey(fileName.hasPrefix("/") ? String(fileName.drop { character in character == "/" }) : fileName)
                if fileName.hasPrefix("/") {
                    // From the root only: as a suffix it also matched `Other/Folder/Note.md`.
                    paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_path = ? ORDER BY path", arguments: [pathSuffix])
                } else {
                    paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_path = ? OR folded_path LIKE ? ESCAPE '\\' ORDER BY path",
                                                arguments: [pathSuffix, "%/" + escapedForLike(pathSuffix)])
                }
            } else {
                // Every file of the name is read, with no limit: the closest may sort last by path.
                let namedPaths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_name = ?", arguments: [foldedKey(fileName)])
                // Aliases are Obsidian's Wikilink names; a Markdown link names a file. A file's
                // own name goes before another note's alias.
                let aliasPaths = isWiki
                    ? try String.fetchAll(database, sql: "SELECT path FROM aliases WHERE folded_alias = ?", arguments: [foldedKey(part)]) : []
                let namedResolution = WikiLinkResolver.closestFirst(namedPaths, toNoteAt: source)
                paths = namedResolution + WikiLinkResolver.closestFirst(aliasPaths.filter { path in !namedPaths.contains(path) }, toNoteAt: source)
                if !paths.isEmpty { return try paths.map(VaultPath.init) }
                continue
            }
            if !paths.isEmpty { return try WikiLinkResolver.closestFirst(paths, toNoteAt: source).map(VaultPath.init) }
        }
        return []
    }

    /// The path part a link names a file by when no direct path reaches it: as written for
    /// a Wikilink, and percent-decoded for a Markdown link (`My%20Note.md`). Obsidian
    /// resolves a Markdown link in the shortest format (`Note.md`) or as a partial path
    /// by name, as it does a Wikilink.
    static func lookupPathPart(of target: String, isWiki: Bool) -> String {
        let writtenPath = WikiLinkResolver.pathPart(target)
        return isWiki ? writtenPath : (writtenPath.removingPercentEncoding ?? writtenPath)
    }

    /// Number of indexed files in the vault.
    public nonisolated func fileCount() async throws -> Int {
        try await readOnAReader { database in try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files") ?? 0 }
    }

    /// Number of indexed files with this file name anywhere in the vault.
    public nonisolated func fileCount(named fileName: String) async throws -> Int {
        try await readOnAReader { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files WHERE folded_name = ?", arguments: [Self.foldedKey(fileName)]) ?? 0
        }
    }

    public nonisolated func outgoingLinks(from source: VaultPath) async throws -> [String] {
        try await readOnAReader { database in try String.fetchAll(database,
            sql: "SELECT DISTINCT target FROM links WHERE source = ? ORDER BY target LIMIT 200", arguments: [source.rawValue]) }
    }

    public nonisolated func backlinks(to destination: VaultPath) async throws -> [VaultPath] {
        try await readOnAReader { database in try Self.backlinkSources(to: destination, includesPropertyLinks: false, in: database) }
    }

    /// Every folded link target (`links.folded_target`, `property_links.folded_target`)
    /// that may name `destination`: each trailing part of its path (`Sub/Target.md`,
    /// `Target.md`), with and without the extension, the whole path written from the
    /// vault root (`/Folder/Sub/Target`), and its aliases. A superset: links among the
    /// matching rows must still resolve to `destination`.
    static func foldedLinkTargetCandidates(for destination: VaultPath, in database: Database) throws -> [String] {
        let components = destination.rawValue.split(separator: "/").map(String.init)
        var candidates: [String] = []
        for firstComponentIndex in components.indices {
            let pathSuffix = components[firstComponentIndex...].joined(separator: "/")
            candidates += [pathSuffix, (pathSuffix as NSString).deletingPathExtension]
        }
        candidates += ["/" + destination.rawValue, "/" + (destination.rawValue as NSString).deletingPathExtension]
        candidates += try String.fetchAll(database, sql: "SELECT alias FROM aliases WHERE path = ?", arguments: [destination.rawValue])
        return Array(NSOrderedSet(array: candidates.map(foldedKey)).array.compactMap { candidate in candidate as? String })
    }

    /// - Parameter includesPropertyLinks: Also count links written in frontmatter, as
    ///   Obsidian's `file.backlinks` does in bases.
    static func backlinkSources(to destination: VaultPath, includesPropertyLinks: Bool, in database: Database) throws -> [VaultPath] {
        // Candidate reduction uses the folded target indexes. Every link is then resolved
        // from its note, as a name several files share means the closest (`closestFirst`), and
        // each kind has its rules (`storedLinkTarget`).
        let candidateTargets = try foldedLinkTargetCandidates(for: destination, in: database)
        // A Wikilink relative to its note (`[[../Sub/Target]]`) is kept as written, so it is
        // found by its ending. Targets starting with `.` are a range of the folded index.
        let relativeEndings = Set([destination.name, destination.stem].map(foldedKey)).sorted().map { fileName in "%/" + escapedForLike(fileName) }
        let targetCondition = "folded_target IN (\(databaseQuestionMarks(count: candidateTargets.count)))"
            + " OR (folded_target >= '.' AND folded_target < '/' AND (" + relativeEndings.map { _ in "folded_target LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + "))"
        let targetArguments = StatementArguments(candidateTargets) + StatementArguments(relativeEndings)
        var sql = "SELECT DISTINCT source, target, isWiki FROM links WHERE \(targetCondition)"
        var arguments = targetArguments
        if includesPropertyLinks {
            // Property links are resolved as Wikilinks, which also find the written path of
            // a Markdown link: beside the note, from the vault root, or by name.
            sql += " UNION SELECT DISTINCT path, target, 1 FROM property_links WHERE \(targetCondition)"
            arguments += targetArguments
        }
        // Every linking row is read: a limit here would drop backlinks without saying so.
        let rows = try Row.fetchAll(database, sql: sql, arguments: arguments)
        var sources: Set<VaultPath> = []
        // A link resolves the same way from every note in one folder, so each written
        // target is resolved once per folder and link kind rather than once per linking note.
        var resolvesToDestination: [String: Bool] = [:]
        let destinationKey = foldedKey(destination.rawValue)
        for row in rows {
            let source = try VaultPath(row["source"] as String)
            guard !sources.contains(source) else { continue }
            let target: String = row["target"]
            let isWiki: Bool = row["isWiki"]
            if foldedKey(target) == destinationKey { sources.insert(source); continue }
            // A whole path written from the vault root names that file and no other; a
            // canvas's file cards are stored this way (`CanvasLinks`).
            if target.hasPrefix("/"), foldedKey(String(target.dropFirst())) == destinationKey { sources.insert(source); continue }
            let cacheKey = (isWiki ? "w" : "m") + source.parent.rawValue + "\u{0}" + target
            let isMatch: Bool
            if let cached = resolvesToDestination[cacheKey] {
                isMatch = cached
            } else {
                isMatch = try resolvedPaths(target, from: source, isWiki: isWiki, in: database).first == destination
                resolvesToDestination[cacheKey] = isMatch
            }
            if isMatch { sources.insert(source) }
        }
        return sources.sorted()
    }

    /// The target a link is indexed by, which `resolvedPaths` resolves from the linking note.
    /// Wikilinks keep their written target. Markdown links are percent-decoded: one that
    /// starts with `./` or `../`, or has no path (`#Heading`), can only mean one file, so it
    /// is stored as that vault path; any other may be a path beside the note, from the vault
    /// root or a name (Obsidian's relative, absolute and shortest formats), so it is stored
    /// as written. Each is then among the targets `foldedLinkTargetCandidates` looks up.
    static func storedLinkTarget(_ link: NoteLink, source: VaultPath) -> String {
        storedLinkTarget(link.target, isWiki: link.isWiki, source: source)
    }

    static func storedLinkTarget(_ target: String, isWiki: Bool, source: VaultPath) -> String {
        guard !isWiki else { return WikiLinkResolver.comparisonKey(WikiLinkResolver.pathPart(target)) }
        let writtenPath = WikiLinkResolver.pathPart(target)
        let decodedPath = lookupPathPart(of: target, isWiki: false)
        let isWebOrAppLink = URL(string: writtenPath)?.scheme != nil || URL(string: decodedPath)?.scheme != nil
        guard !isWebOrAppLink else { return WikiLinkResolver.comparisonKey(writtenPath) }
        guard decodedPath.isEmpty || WikiLinkResolver.isExplicitlyRelative(decodedPath),
              let notePath = WikiLinkResolver.directCandidates(target: target, source: source, isWiki: false).first else {
            return WikiLinkResolver.comparisonKey(decodedPath)
        }
        return WikiLinkResolver.comparisonKey(notePath.rawValue)
    }

    /// A file a scan found, with the metadata the unchanged check compares.
    private struct ScannedFile: Sendable {
        let path: VaultPath
        let location: URL
        let size: Int
        let modified: Date
        let created: Date?
        let isMarkdown: Bool
        /// A canvas, whose text is read for its links but is not searchable.
        let isCanvas: Bool
        /// A PDF, whose text boxes' text is searchable (`PDFIndexText`).
        let isPDF: Bool
        /// Set once the file is known to have changed: a note whose text the scan reads.
        var readsContent = false
        /// Set when the unchanged check found the file in the cloud.
        var isNotDownloaded = false
    }

    /// A changed file of a scan batch, read and parsed outside the actor.
    private struct ScanBatchEntry: Sendable {
        let file: IndexedFile
        /// Why the note's text could not be read; the file is still written, without text.
        let readFailure: String?
        let preparation: Result<PreparedFile, any Error>
    }

    /// The text of a note a scan read.
    enum NoteReading: Sendable {
        case text(String)
        case notText
        case failed(any Error)
    }

    /// What a scan has found and not yet written, and what it reports.
    private struct ScanState {
        var discoveredFiles = 0, updatedFiles = 0, pendingFiles = 0, prunedFiles = 0
        var failedPaths: [String] = []
        /// Enumerated files waiting for the unchanged check.
        var scannedFiles: [ScannedFile] = []
        /// Changed files waiting to be read and written.
        var batch: [ScannedFile] = []
        var batchContentBytes = 0
        /// Every file enumerated, which the prune keeps. In memory, so a scan that finds the
        /// vault as the index has it writes nothing; with 31,748 files it is a few megabytes,
        /// for as long as the scan runs.
        var seenPaths: Set<String> = []

        mutating func recordFailure(_ description: String) {
            if failedPaths.count < 100 { failedPaths.append(description) }
        }
    }

    /// Enumerated files are checked against the index this many at a time, in one read.
    private static let unchangedCheckChunkSize = 256

    /// Brings the index up to date with the whole vault, or with what is inside `folder`.
    public func reconcile(root: URL, inside folder: VaultPath? = nil) async throws -> IndexingReport {
        guard !isScanning else { throw GraphiteError.unavailable("An index scan is already running.") }
        isScanning = true
        let generation = UUID().uuidString
        activeScanGeneration = generation
        defer {
            isScanning = false
            activeScanGeneration = nil
            pathsRefreshedDuringScan.removeAll()
        }
        // A folder a scan would not enter: its files are not the vault's.
        let enumeratedFolder: URL
        if let folder {
            guard !folder.isHidden, let folderLocation = Self.locationWithoutSymbolicLinks(of: folder,
                root: root) else { return try partialReport(of: ScanState()) }
            enumeratedFolder = folderLocation
        } else {
            enumeratedFolder = root
        }
        // The download state is not listed: asking for it makes the file provider inspect
        // every item, which costs more than the rest of the enumeration. It is read only
        // for changed notes, the only files whose content the scan would read.
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        // Set when part of the vault could not be listed. Rows for files there were not
        // seen, so pruning would delete files that still exist.
        var isInventoryIncomplete = false
        // Relative URLs: the enumerator may report `/private/var/…` for a root given as
        // `/var/…`, so cutting the root's path length off absolute paths is unreliable.
        guard let enumerator = FileManager.default.enumerator(at: enumeratedFolder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles,
            .skipsPackageDescendants, .producesRelativePathURLs], errorHandler: { _, _ in isInventoryIncomplete = true; return true }) else {
            throw GraphiteError.unavailable("Cannot enumerate the vault.")
        }
        let folderPrefix = folder.map { folder in folder.rawValue + "/" } ?? ""
        var state = ScanState()
        while let location = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let relative = folderPrefix + location.relativePath
            let values: URLResourceValues
            do {
                values = try location.resourceValues(forKeys: Set(keys))
            } catch {
                // The item vanished or could not be inspected mid-scan. Its row, if any, is
                // kept rather than pruned on an unknown state; the file presenter or the
                // next scan settles it.
                if let path = try? VaultPath(relative) { state.seenPaths.insert(path.rawValue) }
                state.recordFailure(relative + ": " + error.localizedDescription)
                continue
            }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let path: VaultPath
            do {
                path = try VaultPath(relative)
            } catch {
                // APFS allows names that VaultPath refuses, such as one with a backslash.
                // No row can exist for such a file, so skipping it leaves nothing stale and
                // must not stop deleted files from being pruned.
                state.recordFailure(relative + ": " + error.localizedDescription)
                continue
            }
            state.discoveredFiles += 1
            state.seenPaths.insert(path.rawValue)
            state.scannedFiles.append(ScannedFile(path: path, location: location, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast,
                                                  created: values.creationDate, isMarkdown: DocumentKind(path: path) == .markdown,
                                                  isCanvas: DocumentKind(path: path) == .canvas, isPDF: DocumentKind(path: path) == .pdf))
            if state.scannedFiles.count >= Self.unchangedCheckChunkSize { try await checkScannedFiles(&state, generation: generation) }
        }
        try await checkScannedFiles(&state, generation: generation)
        try await writeBatch(&state, generation: generation)
        if !isInventoryIncomplete { state.prunedFiles = try pruneFilesNotSeen(state.seenPaths, inside: folder) }
        guard folder == nil else { return try partialReport(of: state) }
        if !isInventoryIncomplete { try recordFinishedScan() }
        return IndexingReport(discoveredFiles: state.discoveredFiles, examinedFiles: state.discoveredFiles, updatedFiles: state.updatedFiles,
            pendingContentFiles: state.pendingFiles,
            failedPaths: state.failedPaths, prunedFiles: state.prunedFiles)
    }

    /// What a scan of one folder reports: what it changed, with the counts of the whole vault,
    /// which are what a window says.
    private func partialReport(of state: ScanState) throws -> IndexingReport {
        let (fileCount, pendingFileCount) = try readThroughTheWriter { database in
            (try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files") ?? 0,
             try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files WHERE contentIndexed != ? AND path LIKE '%.md'",
                 arguments: [IndexedContentState.indexed.rawValue]) ?? 0)
        }
        return IndexingReport(discoveredFiles: fileCount, examinedFiles: state.discoveredFiles, updatedFiles: state.updatedFiles,
            pendingContentFiles: pendingFileCount,
            failedPaths: state.failedPaths, prunedFiles: state.prunedFiles)
    }

    /// Removes the rows of files the scan did not see, and returns how many. Synchronous on the
    /// actor, so `refresh` cannot add a row between the read and the deletion. Reading the paths
    /// is all an unchanged vault costs here: nothing is written.
    private func pruneFilesNotSeen(_ seenPaths: Set<String>, inside folder: VaultPath?) throws -> Int {
        let indexedPaths = try readThroughTheWriter { database in
            guard let folder else { return try String.fetchAll(database, sql: "SELECT path FROM files") }
            // '0' follows '/' in code-unit order, so this range is exactly the paths inside the folder.
            return try String.fetchAll(database, sql: "SELECT path FROM files WHERE path > ? AND path < ?", arguments: [folder.rawValue + "/",
                folder.rawValue + "0"])
        }
        // A file `refresh` wrote or removed during the scan is as `refresh` left it.
        let stalePaths = indexedPaths.filter { path in !seenPaths.contains(path) && pathsRefreshedDuringScan[path] == nil }
        guard !stalePaths.isEmpty else { return 0 }
        try databasePool.write { database in try Self.deleteRows(ofPaths: stalePaths, in: database) }
        return stalePaths.count
    }

    private static func deleteRows(ofPaths paths: [String], in database: Database) throws {
        let searchDeletion = try database.cachedStatement(sql: searchRowDeletion)
        let perFileDeletions = try perFileTables.map { table in try database.cachedStatement(sql: "DELETE FROM \(table) WHERE path = ?") }
        let linkDeletion = try database.cachedStatement(sql: "DELETE FROM links WHERE source = ?")
        let fileDeletion = try database.cachedStatement(sql: "DELETE FROM files WHERE path = ?")
        for path in paths {
            try searchDeletion.execute(arguments: [path])
            for perFileDeletion in perFileDeletions { try perFileDeletion.execute(arguments: [path]) }
            try linkDeletion.execute(arguments: [path])
            try fileDeletion.execute(arguments: [path])
        }
    }

    /// Written once: a later scan that finds the vault unchanged writes nothing at all.
    private func recordFinishedScan() throws {
        guard try !readThroughTheWriter({ database in try Self.hasFinishedScanFact(in: database) }) else { return }
        try databasePool.write { database in
            try database.execute(sql: "INSERT OR IGNORE INTO index_facts (name, value) VALUES (?, 1)", arguments: [Self.finishedScanFact])
        }
    }

    /// Checks a chunk of enumerated files against the index in one read, and adds changed files
    /// to the batch, writing it whenever it is full.
    private func checkScannedFiles(_ state: inout ScanState, generation: String) async throws {
        let storedContentStates = try storedContentStates(of: state.scannedFiles)
        for (var file, storedContentState) in zip(state.scannedFiles, storedContentStates) {
            // A note too large to index or still in the cloud stays unread until its
            // size, date or download state changes; reading it again would give the
            // same result. The download state is asked last, and only when it decides.
            let readability = contentReadability(of: file, storedContentState: storedContentState)
            let stateItWouldBeWritten: IndexedContentState = readability == .inTheCloud ? .notDownloaded : .notRead
            if let storedContentState,
                (storedContentState != .notRead && storedContentState != .notDownloaded) || (readability != .readable && storedContentState == stateItWouldBeWritten) {
                if file.isMarkdown, storedContentState != .indexed { state.pendingFiles += 1 }
                continue
            }
            if file.isMarkdown, readability != .readable { state.pendingFiles += 1 }
            file.readsContent = readability == .readable
            file.isNotDownloaded = readability == .inTheCloud
            // A PDF is not read whole: only its text boxes' text, which is bounded.
            if file.readsContent { state.batchContentBytes += file.isPDF ? min(file.size, PDFFreeTextContents.maximumUTF16Count * 2) : file.size }
            state.batch.append(file)
            state.updatedFiles += 1
            if state.batch.count >= Self.maximumBatchFileCount || state.batchContentBytes >= Self.maximumBatchContentBytes {
                try await writeBatch(&state, generation: generation)
            }
        }
        state.scannedFiles.removeAll(keepingCapacity: true)
        await Task.yield()
    }

    private enum ContentReadability {
        /// The index already has what it can have of the file, or the file has no text to read.
        case notApplicable
        case inTheCloud
        case readable
    }

    /// Whether a scan can read the file's text. A file last found in the cloud is not asked about
    /// through the file provider while the file system still marks it as a placeholder.
    private func contentReadability(of file: ScannedFile, storedContentState: IndexedContentState?) -> ContentReadability {
        guard storedContentState == nil || storedContentState == .notRead || storedContentState == .notDownloaded,
              file.isMarkdown || file.isCanvas || file.isPDF,
              file.size <= (file.isPDF ? PDFIndexText.maximumPDFBytes : Self.maximumIndexedNoteBytes) else { return .notApplicable }
        if storedContentState == .notDownloaded, cloudFileStatus.isDatalessPlaceholder(file.location) { return .inTheCloud }
        return cloudFileStatus.isNotDownloaded(file.location) ? .inTheCloud : .readable
    }

    private func writeBatch(_ state: inout ScanState, generation: String) async throws {
        guard !state.batch.isEmpty else { return }
        let entries = await Self.readAndPrepare(state.batch)
        state.batch.removeAll(keepingCapacity: true)
        state.batchContentBytes = 0
        // An unreadable note is still part of the inventory. Its failure must not look
        // like an incomplete scan, or deleted files are never pruned.
        for entry in entries {
            guard let readFailure = entry.readFailure else { continue }
            state.pendingFiles += 1
            state.recordFailure(entry.file.path.rawValue + ": " + readFailure)
        }
        for failure in try writeScanBatch(entries, generation: generation) { state.recordFailure(failure) }
    }

    /// The stored content state of each file whose size and modification date are unchanged,
    /// nil for a changed or new file. One synchronous read for the whole chunk: a separate
    /// asynchronous read per file cost more than the lookup itself.
    private func storedContentStates(of files: [ScannedFile]) throws -> [IndexedContentState?] {
        guard !files.isEmpty else { return [] }
        return try readThroughTheWriter { database in
            let lookup = try database.cachedStatement(sql: "SELECT contentIndexed FROM files WHERE path = ? AND size = ? AND modified = ?")
            return try files.map { file in
                try Int.fetchOne(lookup, arguments: [file.path.rawValue, file.size, file.modified.timeIntervalSince1970]).flatMap(IndexedContentState.init(rawValue:))
            }
        }
    }

    /// Reads the notes of a scan batch and parses every file of it. Static, so it runs
    /// outside the actor: queries and saves are not held up while a batch is read and parsed.
    private static func readAndPrepare(_ batch: [ScannedFile]) async -> [ScanBatchEntry] {
        var readings = await readNotes(at: batch.filter(\.readsContent).map(\.location.absoluteURL)).makeIterator()
        return batch.map { scannedFile in
            var markdown: String?
            var isUnreadableAsText = false
            var readFailure: String?
            if scannedFile.readsContent, let reading = readings.next() {
                switch reading {
                case .text(let text): markdown = text
                case .notText:
                    isUnreadableAsText = true
                    readFailure = GraphiteError.invalidFile("Note is not UTF-8.").localizedDescription
                case .failed(let error): readFailure = error.localizedDescription
                }
            }
            let file = IndexedFile(path: scannedFile.path, size: scannedFile.size, modified: scannedFile.modified, created: scannedFile.created,
                                   markdown: markdown, isUnreadableAsText: isUnreadableAsText, isNotDownloaded: scannedFile.isNotDownloaded)
            return ScanBatchEntry(file: file, readFailure: readFailure, preparation: Result { try prepared(file) })
        }
    }

    /// Reads notes under one file coordination for all of them: coordinating each file
    /// separately cost ten times more than reading it. When the coordination as a whole
    /// fails, each note is read under its own, so one file's failure costs only that file.
    private static func readNotes(at locations: [URL]) async -> [NoteReading] {
        guard !locations.isEmpty else { return [] }
        let intents = locations.map { location in NSFileAccessIntent.readingIntent(with: location, options: []) }
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        let coordinatedReadings: [NoteReading]? = await withCheckedContinuation { continuation in
            NSFileCoordinator(filePresenter: nil).coordinate(with: intents, queue: queue) { coordinationError in
                guard coordinationError == nil else { continuation.resume(returning: nil); return }
                // Each note is read through its intent's URL, which follows a move
                // reported during coordination.
                continuation.resume(returning: intents.map { intent in
                    DocumentKind(fileExtension: intent.url.pathExtension) == .pdf ? PDFIndexText.reading(at: intent.url)
                        : noteReading(from: Result { try readNoteData(at: intent.url) })
                })
            }
        }
        if let coordinatedReadings { return coordinatedReadings }
        let writer = AtomicFileWriter()
        return locations.map { location in
            DocumentKind(fileExtension: location.pathExtension) == .pdf ? PDFIndexText.coordinatedReading(at: location)
                : noteReading(from: Result { try writer.read(location, maximumBytes: maximumIndexedNoteBytes).data })
        }
    }

    /// The same size check and read as `AtomicFileWriter.read`, for a location that is
    /// already coordinated.
    private static func readNoteData(at location: URL) throws -> Data {
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumIndexedNoteBytes else { throw GraphiteError.oversized("This file exceeds the current editor's memory budget.") }
        return try Data(contentsOf: location)
    }

    private static func noteReading(from dataResult: Result<Data, any Error>) -> NoteReading {
        switch dataResult {
        case .success(let data): String(data: data, encoding: .utf8).map(NoteReading.text) ?? .notText
        case .failure(let error): .failed(error)
        }
    }

    /// Writes one batch of a scan and returns a description of each file it could not
    /// write. After a failed batch write each file is tried alone, so one bad file costs
    /// only itself and the batch never has to be kept for another attempt. Files that
    /// still fail, or could not be parsed, keep their existing rows, which the prune keeps
    /// as seen; the next scan tries them again.
    private func writeScanBatch(_ entries: [ScanBatchEntry], generation: String) throws -> [String] {
        var failures: [String] = []
        var preparedFiles: [PreparedFile] = []
        for entry in entries where !isSupersededByRefresh(entry.file) {
            switch entry.preparation {
            case .success(let prepared): preparedFiles.append(prepared)
            case .failure(let error):
                failures.append(entry.file.path.rawValue + ": " + error.localizedDescription)
            }
        }
        do {
            try write(preparedFiles, generation: generation)
        } catch {
            for prepared in preparedFiles {
                do {
                    try write([prepared], generation: generation)
                } catch {
                    failures.append(prepared.file.path.rawValue + ": " + error.localizedDescription)
                }
            }
        }
        return failures
    }

    /// Whether `refresh` wrote or removed this file after the scan read it, directly or by
    /// removing a folder that contains it.
    private func isSupersededByRefresh(_ file: IndexedFile) -> Bool {
        guard !pathsRefreshedDuringScan.isEmpty else { return false }
        if let refreshedModification = pathsRefreshedDuringScan[file.path.rawValue] { return refreshedModification >= file.modified }
        var ancestor = file.path.parent
        while !ancestor.rawValue.isEmpty {
            if pathsRefreshedDuringScan[ancestor.rawValue] == .distantFuture { return true }
            ancestor = ancestor.parent
        }
        return false
    }

    /// Re-reads specific files after Graphite saves them or a file presenter reports a
    /// change. Missing files are removed, with everything inside them when they were
    /// folders. This avoids a whole-vault scan per edit.
    ///
    /// Only files a scan would index are kept: hidden items (`.trash`, `.obsidian`) and
    /// items reached through a symbolic link are removed like missing ones. A note that
    /// cannot be read stays in the inventory without searchable text, as in a scan, and
    /// does not stop the other paths from being refreshed.
    public func refresh(paths: [VaultPath], root: URL) throws {
        let writer = AtomicFileWriter()
        let generation = activeScanGeneration ?? UUID().uuidString
        var changedFiles: [IndexedFile] = []
        var changedContentBytes = 0
        var removedPaths: [String] = []
        func writeChangedFiles() throws {
            try update(changedFiles, generation: generation)
            if activeScanGeneration != nil {
                for file in changedFiles { pathsRefreshedDuringScan[file.path.rawValue] = file.modified }
            }
            changedFiles.removeAll(keepingCapacity: true)
            changedContentBytes = 0
        }
        for path in Set(paths) {
            // Hidden files, such as Obsidian's settings, are not notes: a scan skips them, and
            // a change reported for one leaves it out of the index too.
            guard !path.isHidden else {
                removedPaths.append(path.rawValue)
                continue
            }
            guard let file = refreshedFile(at: path, root: root, writer: writer) else {
                if !isExistingIndexableDirectory(path, root: root) { removedPaths.append(path.rawValue) }
                continue
            }
            changedFiles.append(file)
            changedContentBytes += file.markdown?.utf8.count ?? 0
            if changedFiles.count >= Self.maximumBatchFileCount || changedContentBytes >= Self.maximumBatchContentBytes { try writeChangedFiles() }
        }
        try writeChangedFiles()
        guard !removedPaths.isEmpty else { return }
        if activeScanGeneration != nil {
            for removedPath in removedPaths { pathsRefreshedDuringScan[removedPath] = .distantFuture }
        }
        try databasePool.write { database in
            var allRemovedPaths: [String] = []
            for removedPath in removedPaths {
                // '0' follows '/' in code-unit order, so this range is exactly the paths
                // inside a removed folder, found through the primary key.
                let descendantPaths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE path > ? AND path < ?", arguments: [removedPath + "/", removedPath + "0"])
                allRemovedPaths += [removedPath] + descendantPaths
            }
            try Self.deleteRows(ofPaths: allRemovedPaths, in: database)
        }
    }

    /// The file at `path` as a scan would index it, or nil when a scan would not index it:
    /// missing, not a regular file, hidden, or reached through a symbolic link.
    private func refreshedFile(at path: VaultPath, root: URL, writer: AtomicFileWriter) -> IndexedFile? {
        guard !path.isHidden, let location = Self.locationWithoutSymbolicLinks(of: path, root: root),
              let values = try? location.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                                                                  .ubiquitousItemDownloadingStatusKey, .canonicalPathKey]),
              values.isRegularFile == true, values.isHidden != true else { return nil }
        // A case-insensitive volume finds `notes/Idea.md` under its old spelling `notes/idea.md`
        // too, right after a rename that only changed capitals. Only the stored spelling is a
        // file; a row for the other would stay beside the new one until the next full scan.
        if let canonicalPath = values.canonicalPath,
           !WikiLinkResolver.comparisonKey(canonicalPath).hasSuffix("/" + WikiLinkResolver.comparisonKey(path.rawValue)) { return nil }
        let size = values.fileSize ?? 0
        var markdown: String?
        var isUnreadableAsText = false
        let isNotDownloaded = Self.readsText(of: path) && values.ubiquitousItemDownloadingStatus == .notDownloaded
        if DocumentKind(path: path) == .pdf {
            if values.ubiquitousItemDownloadingStatus != .notDownloaded, size <= PDFIndexText.maximumPDFBytes,
               case .text(let text) = PDFIndexText.coordinatedReading(at: location) { markdown = text }
        } else if Self.readsText(of: path), values.ubiquitousItemDownloadingStatus != .notDownloaded, size <= Self.maximumIndexedNoteBytes {
            // `try?`: a note that cannot be read right now (removed mid-refresh, no
            // permission, grown past the limit) keeps its inventory row without text, and
            // the next scan reads it again.
            if let snapshot = try? writer.read(location, maximumBytes: Self.maximumIndexedNoteBytes) {
                markdown = String(data: snapshot.data, encoding: .utf8)
                isUnreadableAsText = markdown == nil
            }
        }
        return IndexedFile(path: path, size: size, modified: values.contentModificationDate ?? .distantPast, created: values.creationDate,
                           markdown: markdown, isUnreadableAsText: isUnreadableAsText, isNotDownloaded: isNotDownloaded)
    }

    /// Whether `path` is a folder a scan would enter. Its files are refreshed on their
    /// own or by a scan, so refreshing the folder itself changes nothing.
    private func isExistingIndexableDirectory(_ path: VaultPath, root: URL) -> Bool {
        guard !path.isHidden, let location = Self.locationWithoutSymbolicLinks(of: path, root: root),
              let values = try? location.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey]) else { return false }
        return values.isDirectory == true && values.isHidden != true
    }

    /// The location of `path`, or nil when reaching it follows a symbolic link inside the
    /// vault, which a scan does not do.
    private static func locationWithoutSymbolicLinks(of path: VaultPath, root: URL) -> URL? {
        guard let location = try? path.url(in: root) else { return nil }
        let unresolvedLocation = root.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(path.rawValue).standardizedFileURL
        return location.path == unresolvedLocation.path ? location : nil
    }

    /// Deletes every cached row so the next scan rebuilds the index from the vault.
    public func removeAllEntries() throws {
        try databasePool.write { database in
            for table in ["search", "links", "files", "index_facts"] + Self.perFileTables { try database.execute(sql: "DELETE FROM \(table)") }
        }
    }
}

