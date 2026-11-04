/**
 * File: VaultIndexRefreshChange.swift
 * -----------------------------------
 * Layer: Index
 * Description: What a refresh of some files changed in what the graph, the tag and property lists and
 *              the backlinks show, so a view that shows none of it does not read the vault again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

/// What refreshing files changed in the index, as far as the vault-wide views can tell.
public struct IndexRefreshChange: Sendable, Equatable {
    /// A file came or went, or a file's links, tags or properties differ: the graph, the tag
    /// list and the property list are out of date. Typing in the body of a note changes none of it.
    public let changedStructure: Bool
    /// A file came or went, or its name or aliases differ: the notes that mention this one by
    /// name are out of date.
    public let changedNames: Bool

    public init(changedStructure: Bool, changedNames: Bool) {
        self.changedStructure = changedStructure
        self.changedNames = changedNames
    }
}

extension VaultIndex {
    /// `refresh(paths:root:)`, saying what it changed. The facts of each file are read before
    /// and after in this one call of the index, so no other write falls between them. Reading
    /// them is a few lookups by path, where a view that read the vault again reads every row.
    public func refreshReportingChange(paths: [VaultPath], root: URL) throws -> IndexRefreshChange {
        let uniquePaths = Array(Set(paths))
        let before = try facts(of: uniquePaths)
        try refresh(paths: uniquePaths, root: root)
        let after = try facts(of: uniquePaths)
        return IndexRefreshChange(changedStructure: before.structure != after.structure, changedNames: before.names != after.names)
    }

    /// Everything the vault-wide views read of these files, as text to compare.
    private func facts(of paths: [VaultPath]) throws -> (structure: [String], names: [String]) {
        try databasePool.read { database in
            // A removed folder takes its files with it, which no listed path shows.
            let fileCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files") ?? 0
            var structure = ["files:\(fileCount)"]
            var names: [String] = []
            for path in paths {
                let name = try String.fetchOne(database, sql: "SELECT basename FROM files WHERE path = ?", arguments: [path.rawValue])
                let existence = name == nil ? "absent" : "present"
                structure.append(contentsOf: [path.rawValue, existence])
                names.append(contentsOf: [path.rawValue, existence, name ?? ""])
                // Links resolve through aliases, so the graph changes with them too.
                let aliases = try String.fetchAll(database, sql: "SELECT alias FROM aliases WHERE path = ? ORDER BY alias", arguments: [path.rawValue])
                names.append(contentsOf: aliases)
                structure.append(contentsOf: aliases)
                structure.append(contentsOf: try String.fetchAll(database, sql: """
                    SELECT target || char(31) || isWiki || char(31) || isEmbed FROM links WHERE source = ? ORDER BY 1
                    """, arguments: [path.rawValue]))
                structure.append(contentsOf: try String.fetchAll(database, sql: "SELECT tag FROM tags WHERE path = ? ORDER BY tag", arguments: [path.rawValue]))
                structure.append(contentsOf: try String.fetchAll(database, sql: """
                    SELECT key || char(31) || node FROM properties WHERE path = ? ORDER BY position
                    """, arguments: [path.rawValue]))
                structure.append(contentsOf: try String.fetchAll(database, sql: "SELECT target FROM property_links WHERE path = ? ORDER BY target", arguments: [path.rawValue]))
                // Where the groups of rows end, so one file's last row cannot be taken for the next one's first.
                structure.append("")
            }
            return (structure, names)
        }
    }
}
