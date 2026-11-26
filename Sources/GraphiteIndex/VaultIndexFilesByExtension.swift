/**
 * File: VaultIndexFilesByExtension.swift
 * --------------------------------------
 * Layer: Index
 * Description: The vault's files of one extension, a bounded list in path order, for choosers such as Calendar Copy's
 *              choice of a base.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// The indexed files whose extension is `fileExtension` (lowercase, without the dot), in path order, at most `limit`.
    public func paths(withFileExtension fileExtension: String, limit: Int) throws -> [VaultPath] {
        guard limit > 0, !fileExtension.isEmpty else { return [] }
        let pattern = "%." + Self.escapedForLike(fileExtension.lowercased())
        return try readThroughTheWriter { database in
            try String.fetchAll(database, sql: "SELECT path FROM files WHERE lower(path) LIKE ? ESCAPE '\\' ORDER BY path LIMIT ?", arguments: [pattern, limit])
                .compactMap { rawPath in try? VaultPath(rawPath) } // A stored path no vault can hold is left out.
        }
    }
}
