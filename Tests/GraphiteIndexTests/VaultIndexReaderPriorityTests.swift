/**
 * File: VaultIndexReaderPriorityTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The index's own scans and refreshes never wait for a reader connection that other reads hold,
 *              and reads outside the index's actor hold a reader at user-initiated priority at least.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import XCTest
import GRDB
import Synchronization
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// HUNT-316: Xcode reported a hang risk, a user-initiated thread waiting on a utility one. The
/// index's actor, escalated by a view awaiting it, waited in a scan or a refresh for one of
/// GRDB's reader connections, which a semaphore hands out without passing priority on, while
/// reads at utility priority held them.
final class VaultIndexReaderPriorityTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ReaderPriorityVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        try Data("# Note\n\n[[Other]] #tag\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    func testAScanAndARefreshEndWhileEveryReaderIsHeldByAnotherRead() async throws {
        let heldReaders = HeldReaders(databasePool: index.databasePool, count: VaultIndex.maximumReaderCount)
        defer { heldReaders.release() }
        try await waitUntil("every reader is held") { heldReaders.heldCount == VaultIndex.maximumReaderCount }

        let index = try XCTUnwrap(index)
        let vault = try XCTUnwrap(vault)
        let ended = Mutex<IndexingReport?>(nil)
        let scan = Task {
            let report = try await index.reconcile(root: vault)
            _ = try await index.refreshReportingChange(paths: [try VaultPath("Note.md")], root: vault)
            ended.withLock { endedReport in endedReport = report }
        }
        // Before the fix, both waited here until the other reads let their readers go.
        try await waitUntil("the scan and the refresh end", timeoutSeconds: 10) { ended.withLock { endedReport in endedReport != nil } }
        heldReaders.release()
        try await scan.value

        XCTAssertEqual(ended.withLock { endedReport in endedReport?.updatedFiles }, 1)
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 1)
    }

    func testAReadOutsideTheActorHoldsItsReaderAtUserInitiatedPriorityAtLeast() async throws {
        let index = try XCTUnwrap(index)
        let priorityWhileReading = await Task(priority: .utility) {
            try? await index.readOnAReader { _ in Task.currentPriority } // Failed: no priority, which fails the test.
        }.value

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(priorityWhileReading), VaultIndex.readerPriority)
    }
}

/// Reads that hold every reader connection until `release()`, each on a thread of its own.
private final class HeldReaders: Sendable {
    private let held = Mutex(0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let count: Int
    private let hasReleased = Mutex(false)

    var heldCount: Int { held.withLock { heldCount in heldCount } }

    init(databasePool: DatabasePool, count: Int) {
        self.count = count
        for _ in 0..<count {
            DispatchQueue.global().async { [self] in
                _ = try? databasePool.read { _ in // A failed read holds no reader, which the wait for every reader reports.
                    held.withLock { heldCount in heldCount += 1 }
                    releaseSignal.wait()
                }
            }
        }
    }

    /// Lets every held reader go; again, it does nothing.
    func release() {
        guard hasReleased.withLock({ released in defer { released = true }; return !released }) else { return }
        for _ in 0..<count { releaseSignal.signal() }
    }
}
