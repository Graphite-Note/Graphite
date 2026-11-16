/**
 * File: VaultFolderSearch.swift
 * -----------------------------
 * Layer: Index
 * Description: Folders found by name from the index's file table: the search's folder: results, the SQL function that
 *              narrows notes to those inside a matching folder, and the file list the file tree's filter reads.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// Folders listed above a search's notes, at most.
    public static let maximumFolderResults = 50

    /// Every file the index holds, with its size and dates, for the file tree's filter (`FileTreeNameIndex`). One read
    /// of the file table on a reader, so a scan under way does not hold it up; no file is read.
    public nonisolated func fileEntries() async throws -> [VaultEntry] {
        try await readOnAReader { database in
            try Row.fetchAll(database, sql: "SELECT path, size, modified, created FROM files").compactMap { row -> VaultEntry? in
                guard let path = try? VaultPath(row["path"] as String) else { return nil } // A name no vault path can hold: left out.
                let modified = Date(timeIntervalSince1970: row["modified"])
                let created = (row["created"] as Double?).map(Date.init(timeIntervalSince1970:))
                return VaultEntry(path: path, isDirectory: false, size: row["size"], modified: modified, created: created)
            }
        }
    }

    /// The folders a search's `folder:` finds by name (`SearchFolderQuery`), as results of their own: every folder that
    /// holds an indexed file, in name order. Empty when the search names no folder. A folder with no file at any depth
    /// is not in the index, so it is not found here; the file tree's filter, which also reads the folders listed, finds it.
    public nonisolated func folderResults(for query: String, limit: Int = maximumFolderResults) async throws -> [SearchResult] {
        guard let expression = SearchQueryParser.parse(query), SearchFolderQuery.folderNameExpression(in: expression) != nil,
              expression.invalidRegularExpressionPatterns.isEmpty else { return [] }
        let filePaths = try await readOnAReader { database in
            try String.fetchAll(database, sql: "SELECT path FROM files").compactMap { path in try? VaultPath(path) } // An impossible path: left out.
        }
        try Task.checkCancellation()
        let folders = SearchFolderQuery.matchingFolders(of: query, among: SearchFolderQuery.folders(holding: filePaths)) ?? []
        let namedFolders = folders.map { folder in (folder: folder, name: folder.name) }.sorted { leftFolder, rightFolder in
            let nameOrder = leftFolder.name.localizedStandardCompare(rightFolder.name)
            return nameOrder == .orderedSame ? leftFolder.folder.rawValue < rightFolder.folder.rawValue : nameOrder == .orderedAscending
        }
        return namedFolders.prefix(max(limit, 0)).map { namedFolder in
            SearchResult(path: namedFolder.folder, title: namedFolder.name, matches: [], matchCount: 0, kind: .folder)
        }
    }
}

/// The functions a search's SQL calls, added to every connection.
enum SearchSQLFunctions {
    static func add(to database: Database) {
        database.add(function: RegularExpressionFunction.function)
        database.add(function: FolderNameFunction.function)
    }
}

/// `graphite_folder_name_matches(argument, path)` for SQLite: whether a folder the file is inside, at any depth, has a
/// name the argument matches, as `SearchMatcher` reads `folder:`. The argument is `w:` and the folded text for a word or
/// phrase (`VaultNameMatching`), or `x:` and a `graphite_regexp` argument for a regular expression.
enum FolderNameFunction {
    static let name = "graphite_folder_name_matches"
    private static let wordPrefix = "w:", regularExpressionPrefix = "x:"

    /// The exact condition for one term of `folder:`. Folding ignores accents, which the folded path column keeps, so the
    /// column narrows only paths written in ASCII, where both agree; the function decides each path left.
    static func condition(for term: SearchTerm) -> SearchSQLCondition {
        if term.kind == .regularExpression {
            let argument = regularExpressionPrefix + RegularExpressionFunction.argument(pattern: term.text, isCaseSensitive: false)
            return SearchSQLCondition(sql: "\(name)(?, files.path)", arguments: [argument], isExact: true)
        }
        let foldedText = VaultNameMatching.folded(term.text)
        guard !foldedText.isEmpty else { return SearchSQLCondition(sql: "1", arguments: [], isExact: true) }
        let isNotASCII = "length(CAST(files.path AS BLOB)) <> length(files.path)"
        return SearchSQLCondition(sql: "(files.folded_path LIKE ? ESCAPE '\\' OR \(isNotASCII)) AND \(name)(?, files.path)",
                                  arguments: ["%" + VaultIndex.escapedForLike(foldedText) + "%", wordPrefix + foldedText], isExact: true)
    }

    static let function = DatabaseFunction(name, argumentCount: 2, pure: true) { values in
        guard let argument = String.fromDatabaseValue(values[0]), let path = String.fromDatabaseValue(values[1]) else { return false }
        let folderNames = path.split(separator: "/").dropLast()
        if argument.hasPrefix(wordPrefix) {
            let foldedText = String(argument.dropFirst(wordPrefix.count))
            return folderNames.contains { folderName in VaultNameMatching.folded(String(folderName)).range(of: foldedText, options: .literal) != nil }
        }
        guard let regularExpression = RegularExpressionFunction.cache.regularExpression(for: String(argument.dropFirst(regularExpressionPrefix.count))) else {
            throw DatabaseError(resultCode: .SQLITE_ERROR, message: RegularExpressionFunction.invalidPatternMessage)
        }
        for folderName in folderNames where try RegularExpressionFunction.containsMatch(regularExpression, in: String(folderName)) { return true }
        return false
    }
}
