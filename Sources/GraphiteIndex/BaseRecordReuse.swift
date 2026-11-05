/**
 * File: BaseRecordReuse.swift
 * ---------------------------
 * Layer: Index
 * Description: Records a base query loaded, so the next query reads again only the files that changed.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 05/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

/// Records a base query loaded, each with the index row it was read from, so the next
/// query over the same index reads again only the files that changed.
///
/// Invariant: `update` rewrites a file's properties, tags and links together with its
/// `files` row, and every change to a file changes its size, modification date, creation
/// date or content state. An unchanged row therefore means an unchanged record.
public struct LoadedBaseRecords: Sendable {
    fileprivate struct RowRevision: Hashable, Sendable {
        let size: Int
        let modifiedInterval: Double
        let createdInterval: Double?
        let isContentIndexed: Bool
    }

    fileprivate struct RevisionedRecord: Sendable {
        let revision: RowRevision
        let record: BaseFileRecord
    }

    fileprivate var recordsByPath: [String: RevisionedRecord]
    /// What the records hold; a query that keeps something else reads them again.
    public let contents: BaseRecordContents
    /// Records the query that produced this read from the database rather than reused.
    let rereadRecordCount: Int
    /// Records held for the next query.
    public var recordCount: Int { recordsByPath.count }

    /// The record a query went through for this file; nil when it did not go through it.
    public func record(at path: VaultPath) -> BaseFileRecord? {
        recordsByPath[path.rawValue]?.record
    }

    /// Nothing loaded yet: the next query reads every record.
    public init() {
        recordsByPath = [:]
        rereadRecordCount = 0
        contents = .everything
    }

    fileprivate init(recordsByPath: [String: RevisionedRecord], rereadRecordCount: Int, contents: BaseRecordContents) {
        self.recordsByPath = recordsByPath
        self.rereadRecordCount = rereadRecordCount
        self.contents = contents
    }
}

extension VaultIndex {
    /// The same batch as `baseRecords(matching:contents:)`, reusing the records in
    /// `previousRecords` whose files have not changed in the index since.
    /// - Returns: The batch, and the loaded records to pass to the next query.
    public func baseRecords(matching prefilter: BaseRecordPrefilter, contents: BaseRecordContents = .everything,
                            reusing previousRecords: LoadedBaseRecords) throws -> (batch: BaseRecordBatch, loadedRecords: LoadedBaseRecords) {
        let reusableRecords = previousRecords.contents == contents ? previousRecords.recordsByPath : [:]
        return try readThroughTheWriter { database in
            let (whereClause, arguments) = try Self.sqlCondition(for: prefilter, in: database)
            let rows = try Row.fetchAll(database, sql: "SELECT path, size, modified, created, contentIndexed FROM files WHERE \(whereClause) ORDER BY path",
                                        arguments: arguments)
            var orderedPaths: [String] = []
            orderedPaths.reserveCapacity(rows.count)
            var revisionsByPath: [String: LoadedBaseRecords.RowRevision] = [:]
            revisionsByPath.reserveCapacity(rows.count)
            var changedRows: [IndexedFileRow] = []
            for row in rows {
                let fileRow = IndexedFileRow(row)
                let revision = LoadedBaseRecords.RowRevision(size: fileRow.size, modifiedInterval: fileRow.modifiedInterval, createdInterval: fileRow.createdInterval,
                                                             isContentIndexed: row["contentIndexed"])
                orderedPaths.append(fileRow.path)
                revisionsByPath[fileRow.path] = revision
                if reusableRecords[fileRow.path]?.revision != revision { changedRows.append(fileRow) }
            }
            var recordsByPath: [String: LoadedBaseRecords.RevisionedRecord] = [:]
            recordsByPath.reserveCapacity(orderedPaths.count)
            for record in try Self.records(for: changedRows, contents: contents, in: database) {
                guard let revision = revisionsByPath[record.path.rawValue] else { continue }
                recordsByPath[record.path.rawValue] = LoadedBaseRecords.RevisionedRecord(revision: revision, record: record)
            }
            var records: [BaseFileRecord] = []
            records.reserveCapacity(orderedPaths.count)
            for pathText in orderedPaths {
                if let reread = recordsByPath[pathText] {
                    records.append(reread.record)
                } else if let reused = reusableRecords[pathText], reused.revision == revisionsByPath[pathText] {
                    recordsByPath[pathText] = reused
                    records.append(reused.record)
                }
            }
            return (BaseRecordBatch(records: records),
                    LoadedBaseRecords(recordsByPath: recordsByPath, rereadRecordCount: changedRows.count, contents: contents))
        }
    }
}
