/**
 * File: PostgreSQLMirrorSafetyTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Checks that a failed PostgreSQL copy is tried again by itself, and that two vaults with one folder name are not copied over each other.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
import GraphitePostgreSQLMirror
@testable import GraphiteUI
import GraphiteTestSupport

/// Neither test needs a PostgreSQL server: the copy goes to a port nothing listens on and fails at once.
@MainActor
final class PostgreSQLMirrorSafetyTests: XCTestCase {
    private func unreachableSource() async throws -> PostgreSQLMirrorSource {
        let vault = try TemporaryVault.make(prefix: "MirrorRetryVault", files: ["Paris.md": "# Paris\n"], for: self).root
        let index = try VaultIndex(databaseURL: try TemporaryVault.make(prefix: "MirrorRetryIndex", for: self).root.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let configuration = PostgreSQLMirrorConfiguration(host: "127.0.0.1", port: 1, databaseName: "graphite", userName: "graphite",
                                                          schemaName: "graphite", transportSecurity: .off)
        return PostgreSQLMirrorSource(vaultName: "Retry", index: index, store: VaultStore(root: vault), vaultRoot: vault, configuration: configuration)
    }

    private final class PasswordReads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func record() -> String {
            lock.withLock { count += 1 }
            return "unused"
        }
        var total: Int { lock.withLock { count } }
    }

    /// HUNT-228: a failure held automatic copies back for a minute, but nothing started one at the end of the wait, so the
    /// status stayed Failed until the vault changed again or the person pressed Copy Now.
    func testAFailedCopyIsTriedAgainWhenTheWaitEnds() async throws {
        let source = try await unreachableSource()
        let clock = ManualClock()
        let mirror = PostgreSQLMirrorController(clock: clock)
        let reads = PasswordReads()
        mirror.readPassword = { reads.record() }

        mirror.copyNow(source)
        try await waitUntil("the first copy to fail") { reads.total == 1 && mirror.isRetryScheduled }
        guard case .failed = mirror.status else { return XCTFail("The copy to a closed port fails: \(mirror.status)") }

        clock.advance(by: PostgreSQLMirrorController.retryDelay - .seconds(1))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(reads.total, 1, "Nothing is tried before the wait is over.")

        clock.advance(by: .seconds(1))
        try await waitUntil("the retry to run") { reads.total == 2 }
        try await waitUntil("the retry to fail and wait again") { mirror.isRetryScheduled }
        mirror.stop()
        XCTAssertFalse(mirror.isRetryScheduled, "Stopping the mirror cancels the retry.")
    }

    func testCopyNowAndANewScheduleReplaceTheRetry() async throws {
        let source = try await unreachableSource()
        let clock = ManualClock()
        let mirror = PostgreSQLMirrorController(clock: clock)
        let reads = PasswordReads()
        mirror.readPassword = { reads.record() }
        mirror.copyNow(source)
        try await waitUntil("the first copy to fail") { mirror.isRetryScheduled }

        mirror.copyNow(source)
        try await waitUntil("the second copy to fail") { reads.total == 2 && mirror.isRetryScheduled }
        mirror.stop()
    }

    /// HUNT-227: rows are keyed by the folder name, so two vaults with one name deleted each other's notes in the database.
    func testTwoVaultsWithOneFolderNameAreNotCopiedOverEachOther() {
        let location = VaultLocation(anchor: .applicationDocuments)
        var list = VaultList()
        let firstIdentifier = list.recordOpening(name: "Notes", location: location, path: "/Users/a/Notes", at: .now)
        var otherLocation = location
        otherLocation.relativePath = "Other"
        let secondIdentifier = list.recordOpening(name: "Notes", location: otherLocation, path: "/Users/b/Notes", at: .now)
        let thirdIdentifier = list.recordOpening(name: "Journal", location: VaultLocation(anchor: .applicationDocuments, relativePath: "Journal"),
                                                 path: "/Users/a/Journal", at: .now)
        XCTAssertNotEqual(firstIdentifier, secondIdentifier)

        let first = list.vault(withIdentifier: firstIdentifier)!
        let message = PostgreSQLMirrorController.refusalForSharedName(of: first, among: list.vaults)
        XCTAssertTrue(message?.contains("Notes") == true, "The message names the shared folder name.")
        XCTAssertNotNil(PostgreSQLMirrorController.refusalForSharedName(of: list.vault(withIdentifier: secondIdentifier)!, among: list.vaults))
        XCTAssertNil(PostgreSQLMirrorController.refusalForSharedName(of: list.vault(withIdentifier: thirdIdentifier)!, among: list.vaults),
                     "A vault with a name of its own is copied.")
        XCTAssertNil(PostgreSQLMirrorController.refusalForSharedName(of: first, among: [first]), "A vault is not its own namesake.")
    }

    func testARefusedCopyShowsWhyAndCopiesNothing() async throws {
        let mirror = PostgreSQLMirrorController(clock: ManualClock())
        mirror.refuse(because: "Another vault is also named “Notes”.")
        guard case .failed(let message, _) = mirror.status else { return XCTFail("A refused copy shows as failed: \(mirror.status)") }
        XCTAssertEqual(message, "Another vault is also named “Notes”.")
        XCTAssertFalse(mirror.isCopyScheduled)
        XCTAssertFalse(mirror.isRetryScheduled)
    }
}
