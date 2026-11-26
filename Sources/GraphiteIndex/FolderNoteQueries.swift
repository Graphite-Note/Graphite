/**
 * File: FolderNoteQueries.swift
 * -----------------------------
 * Layer: Index
 * Description: The notes directly inside a folder, a bounded page of them, for the notes a relation in a base can
 *              name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// The Markdown notes directly inside `folder` (not in its subfolders), by name, at most `limit`. The vault's root
    /// has none here: its notes are every note, which a relation finds by search instead.
    public nonisolated func notes(directlyInside folder: VaultPath, limit: Int) async throws -> [VaultPath] {
        guard limit > 0, !folder.rawValue.isEmpty else { return [] }
        let prefix = folder.rawValue + "/"
        let prefixLength = prefix.unicodeScalars.count
        return try await readOnAReader { database in
            // An exact prefix (SQLite counts characters as Unicode scalars), then no further slash.
            try String.fetchAll(database, sql: """
                SELECT path FROM files WHERE substr(path, 1, ?) = ? AND instr(substr(path, ? + 1), '/') = 0
                AND lower(substr(path, -3)) = '.md' ORDER BY basename COLLATE NOCASE LIMIT ?
                """, arguments: [prefixLength, prefix, prefixLength, limit])
                .map(VaultPath.init)
        }
    }
}
