/**
 * File: VaultIndexReads.swift
 * ---------------------------
 * Layer: Index
 * Description: How the index reads its database: the actor through the writer's connection, which only it uses,
 *              and every other read on a reader at user-initiated priority at least, so no read waits on a slower one.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import GRDB

/// How the index reads its database. GRDB hands its reader connections out through a semaphore,
/// which passes no priority on: a read that waits for a reader waits, at its own priority, for
/// whichever reads hold them. The index's actor, raised to user-initiated by a view awaiting it,
/// waited in a scan or a refresh for readers that reads at utility priority held (HUNT-316).
extension VaultIndex {
    /// The priority every read of a reader connection runs at, at least.
    static let readerPriority = TaskPriority.userInitiated

    /// A read on the actor, through the writer's connection, which only the actor uses: the
    /// actor never takes one of the readers, so a scan or a refresh, whatever priority it runs
    /// at, neither waits for the readers nor holds one back from a view (HUNT-316). The actor
    /// already makes its reads one at a time, so they lose no concurrency. Read-only, in a
    /// deferred transaction, as a reader's read is.
    func readThroughTheWriter<Answer>(_ lookup: (Database) throws -> Answer) throws -> Answer {
        try databasePool.writeWithoutTransaction { database in
            try database.readOnly {
                try database.beginTransaction(.deferred)
                defer {
                    do { try database.commit() } catch { try? database.rollback() } // A read-only transaction has nothing to keep.
                }
                return try lookup(database)
            }
        }
    }

    /// A read on one of the readers, outside the actor, at `readerPriority` at least whatever the
    /// caller's priority: a read that holds a reader never holds it at a priority below that of a
    /// read waiting for one. A cancelled caller still interrupts its query.
    nonisolated func readOnAReader<Answer: Sendable>(_ lookup: @escaping @Sendable (Database) throws -> Answer) async throws -> Answer {
        let databasePool = databasePool
        let reading = Task(priority: max(Task.currentPriority, Self.readerPriority)) { try await databasePool.read(lookup) }
        return try await withTaskCancellationHandler { try await reading.value } onCancel: { reading.cancel() }
    }
}
