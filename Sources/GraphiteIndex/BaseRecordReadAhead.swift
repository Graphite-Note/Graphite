/**
 * File: BaseRecordReadAhead.swift
 * -------------------------------
 * Layer: Index
 * Description: Records of files outside a base's rows, read together with their neighbours, so a column that
 *              reads a linked file's fields over thousands of rows is not one database read per row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation
import GRDB
import GraphiteCore
import Synchronization

/// The records one run of a base read for files outside its rows. Each read also takes the files
/// next to the one asked about, in path order, as many as were asked about so far: linked notes
/// tend to sit in one folder, and a run that asks about few files reads little more than those.
/// Let go with the provider. The evaluator may call from any thread.
final class BaseRecordReadAhead: Sendable {
    /// Records of one read: the statements of `VaultIndex.records(forPaths:in:)` take this many in one go.
    static let maximumRecordsPerRead = 500
    /// A run that read this many keeps asking one by one, to keep memory bounded.
    static let maximumRememberedRecords = VaultIndex.maximumBaseRecordLimit

    private struct State {
        var filesAskedAbout = 0
        var recordsRead = 0
        var recordsByPath: [String: BaseFileRecord] = [:]
    }

    private let state = Mutex(State())

    /// Records read so far, which a test counts.
    var recordsReadCount: Int { state.withLock { state in state.recordsRead } }

    func rememberedRecord(at path: VaultPath) -> BaseFileRecord? {
        state.withLock { state in state.recordsByPath[path.rawValue] }
    }

    /// How many files the read for a file not remembered should take, the file included.
    func filesToReadForNextMiss() -> Int {
        state.withLock { state in
            state.filesAskedAbout += 1
            guard state.recordsByPath.count < Self.maximumRememberedRecords else { return 1 }
            return min(state.filesAskedAbout, Self.maximumRecordsPerRead)
        }
    }

    func remember(_ records: [BaseFileRecord]) {
        state.withLock { state in
            state.recordsRead += records.count
            for record in records { state.recordsByPath[record.path.rawValue] = record }
        }
    }

    /// The paths to read around `path`, half before and half from it, leaving out those remembered.
    func pathsToRead(around path: VaultPath, fileCount: Int, in database: Database) throws -> [String] {
        guard fileCount > 1 else { return [path.rawValue] }
        let pathsBefore = try String.fetchAll(database, sql: "SELECT path FROM files WHERE path < ? ORDER BY path DESC LIMIT ?", arguments: [path.rawValue, fileCount / 2])
        let pathsFrom = try String.fetchAll(database, sql: "SELECT path FROM files WHERE path >= ? ORDER BY path LIMIT ?", arguments: [path.rawValue, fileCount - fileCount / 2])
        return state.withLock { state in (pathsBefore + pathsFrom).filter { nearbyPath in state.recordsByPath[nearbyPath] == nil } }
    }
}
