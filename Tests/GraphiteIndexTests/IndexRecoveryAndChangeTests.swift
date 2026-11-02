/**
 * File: IndexRecoveryAndChangeTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A damaged index is made again, and a refresh says what it changed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GRDB
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// A damaged index database must not lock a vault out, and a refresh must say whether the
/// vault-wide views have anything new to read.
@MainActor
final class IndexRecoveryAndChangeTests: XCTestCase {
    private var vault: URL!
    private var caches: URL!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "RecoveryVault", for: self).root
        caches = try TemporaryVault.make(prefix: "RecoveryCaches", for: self).root
        try Data("[[Other]] #topic".utf8).write(to: vault.appendingPathComponent("Note.md"))
        try Data("body".utf8).write(to: vault.appendingPathComponent("Other.md"))
    }

    private func databaseLocation(of vaultIdentifier: UUID) -> URL {
        caches.appendingPathComponent("Graphite/Indexes/\(vaultIdentifier.uuidString).sqlite")
    }

    private func plantFile(_ bytes: Data, at location: URL) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: location)
    }

    private func leaseAndScan(_ vaultIdentifier: UUID) async throws -> (VaultIndexLease, IndexingReport) {
        let registry = VaultIndexRegistry(cachesFolder: caches)
        let lease = try await registry.lease(forVault: vaultIdentifier, root: vault)
        var events = lease.events.makeAsyncIterator()
        lease.requestScan(.always)
        while let event = await events.next() {
            if case .scanFinished(let report, _) = event { return (lease, report) }
        }
        XCTFail("No scan ended.")
        throw CancellationError()
    }

    // MARK: A damaged database

    func testADatabaseThatIsNotADatabaseIsMadeAgainAndTheVaultOpens() async throws {
        let vaultIdentifier = UUID()
        try plantFile(Data(repeating: 0x41, count: 4096), at: databaseLocation(of: vaultIdentifier))
        try plantFile(Data("stale journal".utf8), at: URL(fileURLWithPath: databaseLocation(of: vaultIdentifier).path + "-wal"))

        let (lease, report) = try await leaseAndScan(vaultIdentifier)
        defer { lease.end() }

        XCTAssertEqual(report.discoveredFiles, 2, "The vault is read into the new index.")
        let backlinks = try await lease.index.backlinks(to: try VaultPath("Other.md"))
        XCTAssertEqual(backlinks.map(\.rawValue), ["Note.md"])
    }

    func testAHalfMigratedDatabaseIsMadeAgain() async throws {
        let vaultIdentifier = UUID()
        let location = databaseLocation(of: vaultIdentifier)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The first migration's table exists but the migration was never recorded: it fails with "table files already exists".
        let queue = try DatabaseQueue(path: location.path)
        try await queue.write { database in try database.execute(sql: "CREATE TABLE files (path TEXT)") }

        let (lease, report) = try await leaseAndScan(vaultIdentifier)
        defer { lease.end() }

        XCTAssertEqual(report.discoveredFiles, 2)
    }

    func testAnErrorOfTheMachineLeavesTheDatabaseAlone() throws {
        // A folder where the database file should be: opening fails with "unable to open", not damage.
        let location = caches.appendingPathComponent("blocked.sqlite")
        try FileManager.default.createDirectory(at: location.appendingPathComponent("inside"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try VaultIndex.openRebuildingIfDamaged(databaseURL: location))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.appendingPathComponent("inside").path, isDirectory: &isDirectory), "Nothing was deleted.")
    }

    func testWhichErrorsCountAsDamage() {
        XCTAssertTrue(VaultIndex.isDamagedDatabase(DatabaseError(resultCode: .SQLITE_NOTADB)))
        XCTAssertTrue(VaultIndex.isDamagedDatabase(DatabaseError(resultCode: .SQLITE_CORRUPT)))
        XCTAssertFalse(VaultIndex.isDamagedDatabase(DatabaseError(resultCode: .SQLITE_BUSY)), "Another process holds the lock for a moment.")
        XCTAssertFalse(VaultIndex.isDamagedDatabase(DatabaseError(resultCode: .SQLITE_FULL)))
        XCTAssertFalse(VaultIndex.isDamagedDatabase(DatabaseError(resultCode: .SQLITE_CANTOPEN)))
        XCTAssertFalse(VaultIndex.isDamagedDatabase(CocoaError(.fileWriteNoPermission)))
    }

    // MARK: What a refresh changed

    private func refreshedChange(after edit: (URL) throws -> Void, paths: [String]) async throws -> IndexRefreshChange {
        let index = try VaultIndex(databaseURL: caches.appendingPathComponent("index-\(UUID().uuidString).sqlite"))
        _ = try await index.reconcile(root: vault)
        try edit(vault)
        return try await index.refreshReportingChange(paths: try paths.map { path in try VaultPath(path) }, root: vault)
    }

    func testTypingInTheBodyOfANoteChangesNoStructureAndNoName() async throws {
        let change = try await refreshedChange(after: { vault in
            try Data("[[Other]] #topic and some more words typed".utf8).write(to: vault.appendingPathComponent("Note.md"))
        }, paths: ["Note.md"])

        XCTAssertEqual(change, IndexRefreshChange(changedStructure: false, changedNames: false))
    }

    func testAnAddedLinkTagOrPropertyChangesTheStructureOnly() async throws {
        for edited in ["[[Other]] [[Third]] #topic", "[[Other]] #topic #second", "---\nkind: a\n---\n[[Other]] #topic", "[[Other]]"] {
            let change = try await refreshedChange(after: { vault in
                try Data(edited.utf8).write(to: vault.appendingPathComponent("Note.md"))
            }, paths: ["Note.md"])
            XCTAssertEqual(change, IndexRefreshChange(changedStructure: true, changedNames: false), edited)
        }
    }

    func testAnAliasChangesTheNamesAndTheStructure() async throws {
        let change = try await refreshedChange(after: { vault in
            try Data("---\naliases: [Nickname]\n---\n[[Other]] #topic".utf8).write(to: vault.appendingPathComponent("Note.md"))
        }, paths: ["Note.md"])

        XCTAssertEqual(change, IndexRefreshChange(changedStructure: true, changedNames: true))
    }

    func testANewOrRemovedFileChangesTheStructureAndTheNames() async throws {
        let created = try await refreshedChange(after: { vault in
            try Data("".utf8).write(to: vault.appendingPathComponent("Fresh.md"))
        }, paths: ["Fresh.md"])
        XCTAssertEqual(created, IndexRefreshChange(changedStructure: true, changedNames: true))

        let removed = try await refreshedChange(after: { vault in
            try FileManager.default.removeItem(at: vault.appendingPathComponent("Other.md"))
        }, paths: ["Other.md"])
        XCTAssertEqual(removed, IndexRefreshChange(changedStructure: true, changedNames: true))
    }

    // MARK: A note that left for the cloud

    func testANoteEvictedToTheCloudKeepsItsLinksTagsAndSearchableText() async throws {
        let index = try VaultIndex(databaseURL: caches.appendingPathComponent("evicted.sqlite"))
        let note = try VaultPath("Cloud.md")
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try await index.update([IndexedFile(path: note, size: 30, modified: modified, markdown: "---\naliases: [Nimbus]\n---\nSee [[Target]] #weather uniqueword")], generation: "one")
        try await index.update([IndexedFile(path: try VaultPath("Target.md"), size: 1, modified: modified, markdown: "x")], generation: "one")

        // The system reports the note again after it was evicted: no text can be read now.
        try await index.update([IndexedFile(path: note, size: 30, modified: modified, created: nil, markdown: nil, isUnreadableAsText: false, isNotDownloaded: true)], generation: "two")

        let backlinks = try await index.backlinks(to: try VaultPath("Target.md"))
        XCTAssertEqual(backlinks, [note])
        let tags = try await index.tags(matching: "weather")
        XCTAssertEqual(tags.map(\.tag), ["weather"])
        let page = try await index.search("uniqueword")
        XCTAssertEqual(page.results.map(\.path), [note], "The evicted note is still found by its words.")
        let resolved = try await index.resolve("Nimbus", from: try VaultPath("Target.md"))
        XCTAssertEqual(resolved, [note], "Its alias still resolves.")
    }

    func testANoteNeverReadAndInTheCloudStaysUnread() async throws {
        let index = try VaultIndex(databaseURL: caches.appendingPathComponent("never-read.sqlite"))
        let note = try VaultPath("Cloud.md")
        try await index.update([IndexedFile(path: note, size: 30, modified: .distantPast, created: nil, markdown: nil, isUnreadableAsText: false, isNotDownloaded: true)], generation: "one")

        let page = try await index.search("anything")
        XCTAssertTrue(page.results.isEmpty)
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 1, "The note is in the inventory.")
    }
}
