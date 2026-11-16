/**
 * File: PropertyValueQueries.swift
 * --------------------------------
 * Layer: Index
 * Description: The values one property takes across the vault, with how many notes use each, for suggestions while a
 *              value is typed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

/// A value a property takes in the vault, and how many notes give it that value.
public struct PropertyValueCount: Hashable, Sendable {
    public let value: String
    public let fileCount: Int
}

extension VaultIndex {
    /// At most this many of a property's rows are read for its values: a property set in more notes than that is
    /// counted over these, which keeps a suggestion's answer within a frame or two in a vault of any size.
    static let maximumPropertyRowsReadForValues = 20_000

    /// The values the property named `key` (in any capitals) takes, each item of a list counted as a value, that contain
    /// `query` ignoring capitals and accents; most used first, then alphabetically, at most `limit`. Spellings that
    /// differ only in capitals are one value, written as most notes write it.
    public nonisolated func propertyValues(of key: String, matching query: String, limit: Int = 40) async throws -> [PropertyValueCount] {
        guard limit > 0 else { return [] }
        let rows = try await readOnAReader { database in
            try Row.fetchAll(database, sql: "SELECT path, node FROM properties WHERE key = ? COLLATE NOCASE LIMIT ?",
                             arguments: [key, Self.maximumPropertyRowsReadForValues])
                .map { row -> (path: String, node: String) in (row["path"], row["node"]) }
        }
        return Self.valueCounts(of: rows, matching: query, limit: limit)
    }

    /// Counts the values of decoded rows, as `propertyValues(of:matching:limit:)` describes.
    nonisolated static func valueCounts(of rows: [(path: String, node: String)], matching query: String, limit: Int) -> [PropertyValueCount] {
        let decoder = JSONDecoder()
        var pathsByValue: [String: Set<String>] = [:]
        var spellingCounts: [String: [String: Int]] = [:]
        for row in rows {
            let encodedNode = Data(row.node.utf8)
            guard let node = try? decoder.decode(BaseFrontmatterNode.self, from: encodedNode) else { continue } // An unreadable row: not counted.
            for value in scalarTexts(of: node) {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, query.isEmpty || contains(trimmed, query) else { continue }
                let folded = trimmed.lowercased()
                pathsByValue[folded, default: []].insert(row.path)
                spellingCounts[folded, default: [:]][trimmed, default: 0] += 1
            }
        }
        let counts = pathsByValue.map { folded, paths in
            let mostWritten = spellingCounts[folded]?.max { left, right in left.value != right.value ? left.value < right.value : left.key > right.key }
            let spelling = mostWritten?.key ?? folded
            return PropertyValueCount(value: spelling, fileCount: paths.count)
        }
        return Array(counts.sorted { left, right in
            left.fileCount != right.fileCount ? left.fileCount > right.fileCount : left.value.localizedStandardCompare(right.value) == .orderedAscending
        }.prefix(limit))
    }

    /// A value's texts: the value itself, or each item of a list; nested mappings have none.
    private nonisolated static func scalarTexts(of node: BaseFrontmatterNode) -> [String] {
        switch node {
        case .scalar(let text, _): [text]
        case .sequence(let items): items.compactMap { item -> String? in
            guard case .scalar(let text, _) = item else { return nil }
            return text
        }
        case .mapping: []
        }
    }

    private nonisolated static func contains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
