/**
 * File: NoteIconQueries.swift
 * ---------------------------
 * Layer: Index
 * Description: Every note's icon from its `icon` property, read in one query through the index on property keys, so
 *              a vault without icons costs one query that finds no rows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// At most this many notes' icons are read: beyond it the first notes by path keep theirs, which bounds the
    /// catalog's memory in a vault of any size.
    public static let maximumNoteIconsRead = 50_000

    /// The icon of every note whose `icon` property (in any capitals) names one Graphite can draw (`NoteIcon`).
    /// Only that property's rows are read, so the cost follows the number of notes with an icon.
    public nonisolated func noteIcons() async throws -> [VaultPath: NoteIcon] {
        let rows = try await readOnAReader { database in
            try Row.fetchAll(database, sql: "SELECT path, node FROM properties WHERE key = ? COLLATE NOCASE ORDER BY path LIMIT ?",
                             arguments: [NoteIcon.propertyKey, Self.maximumNoteIconsRead])
                .map { row -> (path: String, node: String) in (row["path"], row["node"]) }
        }
        return Self.noteIcons(fromRows: rows)
    }

    /// The icons of decoded rows: a scalar that names an icon; a list, a mapping or an unreadable row names none.
    nonisolated static func noteIcons(fromRows rows: [(path: String, node: String)]) -> [VaultPath: NoteIcon] {
        let decoder = JSONDecoder()
        var iconsByPath: [VaultPath: NoteIcon] = [:]
        for row in rows {
            guard let node = decodedScalarNode(row.node) ?? (try? decoder.decode(BaseFrontmatterNode.self, from: Data(row.node.utf8))), // Unreadable: no icon.
                  case .scalar(let text, _) = node,
                  let icon = NoteIcon(propertyText: text),
                  let path = try? VaultPath(row.path) else { continue } // A stored path that does not parse names no note.
            iconsByPath[path] = icon
        }
        return iconsByPath
    }
}
