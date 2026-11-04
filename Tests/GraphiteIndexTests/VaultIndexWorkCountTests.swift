/**
 * File: VaultIndexWorkCountTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: What a scan and a lookup cost, counted in rows written, reads made and questions asked.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 04/11/2026
 */

import XCTest
import GRDB
import Synchronization
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// What a scan and a lookup cost, counted in rows written, reads made and questions asked: the
/// owner's vault has 31,748 files, and each of these runs at every launch or on every tap.
final class VaultIndexWorkCountTests: XCTestCase {
    private var vault: URL!
    private var databaseURL: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "WorkCountVault", for: self).root
        databaseURL = vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite")
        index = try VaultIndex(databaseURL: databaseURL)
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func rowsWrittenSoFar() throws -> Int {
        index.databasePool.writeWithoutTransaction { database in database.totalChangesCount }
    }

    private func indexedPaths() async throws -> [String] {
        try await index.databasePool.read { database in try String.fetchAll(database, sql: "SELECT path FROM files ORDER BY path") }
    }

    // MARK: HUNT-032

    func testAScanOfAnUnchangedVaultWritesNoRow() async throws {
        for number in 0..<600 { try write("# Note \(number)\n", to: "Folder \(number % 7)/Note \(number).md") }
        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.updatedFiles, 600)
        XCTAssertTrue(firstReport.changedAnything)

        let rowsWrittenBeforeSecondScan = try rowsWrittenSoFar()
        let secondReport = try await index.reconcile(root: vault)

        XCTAssertEqual(try rowsWrittenSoFar(), rowsWrittenBeforeSecondScan, "Every row was rewritten on every launch; now none is.")
        XCTAssertEqual(secondReport.discoveredFiles, 600)
        XCTAssertFalse(secondReport.changedAnything)
    }

    func testAScanRemovesOnlyTheRowsOfFilesGoneAndSaysSo() async throws {
        try write("[[Kept]] #tag", to: "Gone.md")
        try write("kept", to: "Kept.md")
        _ = try await index.reconcile(root: vault)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Gone.md"))

        let report = try await index.reconcile(root: vault)

        XCTAssertEqual(report.prunedFiles, 1)
        XCTAssertTrue(report.changedAnything)
        let paths = try await indexedPaths()
        XCTAssertEqual(paths, ["Kept.md"])
        let staleRows = try await index.databasePool.read { database in
            try Int.fetchOne(database, sql: "SELECT (SELECT COUNT(*) FROM links WHERE source = 'Gone.md') + (SELECT COUNT(*) FROM tags WHERE path = 'Gone.md') + (SELECT COUNT(*) FROM search WHERE path = 'Gone.md')")
        }
        XCTAssertEqual(staleRows, 0)
    }

    func testANoteRefreshedBetweenScansStaysAndIsNotReadAgain() async throws {
        try write("old", to: "Old.md")
        _ = try await index.reconcile(root: vault)
        // Saved through `refresh` between scans, then seen by the next one.
        try write("new", to: "Saved.md")
        try await index.refresh(paths: [try VaultPath("Saved.md")], root: vault)
        let report = try await index.reconcile(root: vault)
        let paths = try await indexedPaths()
        XCTAssertEqual(paths, ["Old.md", "Saved.md"])
        XCTAssertFalse(report.changedAnything)
    }

    // MARK: HUNT-042

    func testAFolderScanReadsAndPrunesOnlyThatFolder() async throws {
        try write("one", to: "Sync/One.md")
        try write("two", to: "Sync/Two.md")
        try write("other", to: "Other/Kept.md")
        try write("root", to: "Syncing not this.md")
        _ = try await index.reconcile(root: vault)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Sync/Two.md"))
        try write("three", to: "Sync/Three.md")
        // Changed outside the folder: a scan of the folder does not see it.
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Other/Kept.md"))
        try write("elsewhere", to: "Other/New.md")

        let report = try await index.reconcile(root: vault, inside: try VaultPath("Sync"))

        let paths = try await indexedPaths()
        XCTAssertEqual(paths, ["Other/Kept.md", "Sync/One.md", "Sync/Three.md", "Syncing not this.md"])
        XCTAssertEqual(report.updatedFiles, 1)
        XCTAssertEqual(report.prunedFiles, 1)
        XCTAssertEqual(report.discoveredFiles, 4, "A window says the vault's count, not the folder's.")
    }

    // MARK: HUNT-043

    func testAFinishedScanIsRememberedAcrossLaunchesUntilTheIndexIsEmptied() async throws {
        let isFinishedBeforeAnyScan = try await index.hasFinishedAScan()
        XCTAssertFalse(isFinishedBeforeAnyScan)
        try write("note", to: "Note.md")
        try write("inside", to: "Folder/Inside.md")
        _ = try await index.reconcile(root: vault, inside: try VaultPath("Folder"))
        let isFinishedAfterAFolderScan = try await index.hasFinishedAScan()
        XCTAssertFalse(isFinishedAfterAFolderScan, "Only a scan of the whole vault counts.")

        _ = try await index.reconcile(root: vault)
        index = nil
        index = try VaultIndex(databaseURL: databaseURL)
        let isFinishedAfterRelaunch = try await index.hasFinishedAScan()
        XCTAssertTrue(isFinishedAfterRelaunch)

        try await index.removeAllEntries()
        let isFinishedAfterEmptying = try await index.hasFinishedAScan()
        XCTAssertFalse(isFinishedAfterEmptying, "A rebuild is a first build again.")
    }

    // MARK: HUNT-033

    func testALongReadDoesNotHoldUpAnotherRead() async throws {
        try write("note", to: "Note.md")
        _ = try await index.reconcile(root: vault)
        let longReadIsInside = expectation(description: "The long read holds its connection")
        let longReadMayEnd = DispatchSemaphore(value: 0)
        let pool = try XCTUnwrap(index).databasePool
        let longRead = Task.detached {
            try pool.read { database in
                _ = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files")
                longReadIsInside.fulfill()
                longReadMayEnd.wait()
            }
        }
        await fulfillment(of: [longReadIsInside], timeout: 5)
        // A database queue would wait here for the read above, which waits for this one to end.
        let count = try await index.fileCount()
        XCTAssertEqual(count, 1)
        longReadMayEnd.signal()
        try await longRead.value
    }

    // MARK: HUNT-034

    func testAnExactNameInADeepFolderIsFoundAmongThousandsOfWeakMatchesWithShortPaths() async throws {
        let deepFolder = (0..<12).map { level in "Deep folder level \(level)" }.joined(separator: "/")
        var files = try (0..<(VaultIndex.maximumQuickSwitcherCandidates + 200)).map { number in
            // Holds the query's letters in order, far apart, under a short path.
            IndexedFile(path: try VaultPath("t\(number)a\(number)xes.md"), size: 1, modified: .distantPast, markdown: nil)
        }
        files.append(IndexedFile(path: try VaultPath(deepFolder + "/Tax.md"), size: 1, modified: .distantPast, markdown: nil))
        try await index.update(files, generation: "test")

        let matches = try await index.quickSwitcherMatches(for: "tax")

        XCTAssertEqual(matches.first?.path.rawValue, deepFolder + "/Tax.md")
    }

    // MARK: HUNT-045

    func testAFileInTheCloudIsNotAskedAboutThroughTheProviderAgainWhileItStaysAPlaceholder() async throws {
        let questions = Mutex((providerQuestions: 0, isPlaceholder: true))
        let cloudFileStatus = CloudFileStatus(isNotDownloaded: { _ in
            questions.withLock { state in
                state.providerQuestions += 1
                return state.isPlaceholder
            }
        }, isDatalessPlaceholder: { _ in questions.withLock { state in state.isPlaceholder } })
        index = try VaultIndex(databaseURL: databaseURL, cloudFileStatus: cloudFileStatus)
        for number in 0..<5 { try write("cloud \(number) needle", to: "Cloud \(number).md") }

        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(questions.withLock { state in state.providerQuestions }, 5)
        XCTAssertEqual(firstReport.pendingContentFiles, 5)

        let secondReport = try await index.reconcile(root: vault)
        XCTAssertEqual(questions.withLock { state in state.providerQuestions }, 5, "The provider is not asked again on the next launch.")
        XCTAssertEqual(secondReport.pendingContentFiles, 5)
        XCTAssertFalse(secondReport.changedAnything)

        // Downloaded since, which changes neither the file's size nor its date: it is read now.
        questions.withLock { state in state.isPlaceholder = false }
        let thirdReport = try await index.reconcile(root: vault)
        XCTAssertEqual(thirdReport.updatedFiles, 5)
        XCTAssertEqual(thirdReport.pendingContentFiles, 0)
        let found = try await index.search("needle").results.count
        XCTAssertEqual(found, 5)
    }

    func testARowFromBeforeTheCloudStateIsMarkedOnceAndThenLeftAlone() async throws {
        let cloudFileStatus = CloudFileStatus(isNotDownloaded: { _ in true }, isDatalessPlaceholder: { _ in true })
        try write("note", to: "Note.md")
        let attributes = try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent("Note.md").path)
        // Written as an earlier version wrote a note in the cloud: not read.
        try await index.update([IndexedFile(path: try VaultPath("Note.md"), size: 4, modified: try XCTUnwrap(attributes[.modificationDate] as? Date), markdown: nil)], generation: "test")
        index = nil
        index = try VaultIndex(databaseURL: databaseURL, cloudFileStatus: cloudFileStatus)

        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.updatedFiles, 1)
        let secondReport = try await index.reconcile(root: vault)
        XCTAssertEqual(secondReport.updatedFiles, 0)
    }

    // MARK: HUNT-029

    func testBacklinksForManyRowsAreOneLoadOfTheLinksInsteadOfOneReadPerRow() async throws {
        var noteTexts: [String: String] = ["Folder/Sub/Target.md": "---\naliases: [Other name]\n---\n"]
        noteTexts["Folder/Sub/Elsewhere.md"] = "[[Target]] and [[../Sub/Target]]"
        noteTexts["Folder/Partial.md"] = "[[Sub/Target]]"
        noteTexts["Alias.md"] = "[[Other name]]"
        noteTexts["Markdown.md"] = "[a](Folder/Sub/Target.md)"
        noteTexts["Rooted.md"] = "[[/Folder/Sub/Target]]"
        noteTexts["Property.md"] = "---\nrelated: \"[[Target]]\"\n---\n"
        noteTexts["Web.md"] = "[site](https://example.org/Target.md)"
        for number in 0..<60 { noteTexts["Row \(number).md"] = "[[Row \((number + 1) % 60)]]" }
        for (path, text) in noteTexts { try write(text, to: path) }
        _ = try await index.reconcile(root: vault)
        let paths = try noteTexts.keys.sorted().map { path in try VaultPath(path) }

        let readingEachOne = BaseIndexRecordProvider(databasePool: index.databasePool, lookupsBeforeLoadingLinks: .max)
        let expectedBacklinks = paths.map { path in readingEachOne.backlinks(to: path) }
        XCTAssertEqual(readingEachOne.lookupReadCount, paths.count)
        XCTAssertEqual(expectedBacklinks[paths.firstIndex(of: try VaultPath("Folder/Sub/Target.md"))!].map(\.rawValue).sorted(),
                       ["Alias.md", "Folder/Partial.md", "Folder/Sub/Elsewhere.md", "Markdown.md", "Property.md", "Rooted.md"])

        let provider = index.baseRecordProvider
        let backlinks = paths.map { path in provider.backlinks(to: path) }

        XCTAssertEqual(backlinks, expectedBacklinks, "Both ways of asking give the same answers.")
        XCTAssertEqual(provider.lookupReadCount, BaseIndexRecordProvider.lookupsBeforeLoadingLinks + 1)
        XCTAssertNoThrow(try provider.throwIfLookupFailed())
    }

    func testLinksResolvedFromMemoryAnswerAsTheDatabaseDoes() async throws {
        for (path, text) in ["A/Same.md": "", "B/Same.md": "", "A/Only.md": "", "Note.md": ""] { try write(text, to: path) }
        _ = try await index.reconcile(root: vault)
        let source = try VaultPath("A/Note.md")
        let fromMemory = BaseIndexRecordProvider(databasePool: index.databasePool, lookupsBeforeLoadingLinks: 0)
        let fromDatabase = BaseIndexRecordProvider(databasePool: index.databasePool, lookupsBeforeLoadingLinks: .max)
        for target in ["Same", "Only", "A/Only", "Note", "Missing", "only.md", "#Heading"] {
            XCTAssertEqual(fromMemory.resolveLinkTarget(target, from: source, isWiki: true), fromDatabase.resolveLinkTarget(target, from: source, isWiki: true), target)
        }
    }

    // MARK: HUNT-040

    func testNotesEmbeddingANoteAreFoundThroughOtherEmbeds() async throws {
        try write("![[Middle]]", to: "Top.md")
        try write("![[Bottom]]", to: "Middle.md")
        try write("text", to: "Bottom.md")
        try write("[[Bottom]]", to: "Only links.md")
        _ = try await index.reconcile(root: vault)

        let embedding = try await index.notesEmbedding([try VaultPath("Bottom.md")], throughLevels: 4)

        XCTAssertEqual(embedding.map(\.rawValue).sorted(), ["Middle.md", "Top.md"])
    }

    // MARK: HUNT-044

    func testWikilinksAreResolvedInOneRead() async throws {
        try write("", to: "Folder/Target.md")
        _ = try await index.reconcile(root: vault)
        let resolved = try await index.resolve(wikilinks: ["Target", "Missing"], from: try VaultPath("Note.md"))
        XCTAssertEqual(resolved, ["Target": try VaultPath("Folder/Target.md")])
    }

    /// As one link alone resolves (`getLinkpathDest`): several files of a name mean the closest.
    func testWikilinksResolvedInOneReadChooseAsASingleLookupDoes() async throws {
        try write("", to: "Course/Target.md")
        try write("", to: "Target/Deep/Target.md")
        _ = try await index.reconcile(root: vault)
        let source = try VaultPath("Course/Note.md")
        let resolved = try await index.resolve(wikilinks: ["Target"], from: source)
        let single = try await index.resolve("Target", from: source)
        XCTAssertEqual(resolved["Target"], try VaultPath("Course/Target.md"))
        XCTAssertEqual(resolved["Target"], single.first)
    }

    /// A move must count a note in the cloud as one whose links it could not check.
    func testANoteInTheCloudIsAmongTheNotesWithUnreadText() async throws {
        index = try VaultIndex(databaseURL: databaseURL, cloudFileStatus: CloudFileStatus(isNotDownloaded: { _ in true }, isDatalessPlaceholder: { _ in true }))
        try write("note", to: "Cloud.md")
        _ = try await index.reconcile(root: vault)
        let unreadNotes = try await index.notesWithUnreadText()
        XCTAssertEqual(unreadNotes, [try VaultPath("Cloud.md")])
    }
}

/// When a whole-vault scan may start after another app changed what cannot be named.
@MainActor
final class VaultIndexRegistrySpacingTests: XCTestCase {
    func testASyncCannotChainScansOfTheWholeVault() async throws {
        let vault = try TemporaryVault.make(prefix: "SpacingVault", for: self).root
        try Data("note".utf8).write(to: vault.appendingPathComponent("Note.md"))
        let caches = try TemporaryVault.make(prefix: "SpacingCaches", for: self).root
        let clock = ManualClock()
        let registry = VaultIndexRegistry(cachesFolder: caches, minimumSpacingOfSpacedScans: .seconds(60), clock: clock)
        let lease = try await registry.lease(forVault: UUID(), root: vault)
        defer { lease.end() }
        var events = lease.events.makeAsyncIterator()
        lease.requestScan(.always)
        guard case .scanStarted = await events.next(), case .scanFinished = await events.next() else { return XCTFail("The first scan runs") }

        // Reports as a sync sends them: none starts a scan before the spacing has passed.
        for _ in 0..<3 { lease.requestScan(.spaced) }
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(60)], "One wait, for all three reports.")
        // Asked outright, as a rebuild or Graphite's own bulk change does, a scan starts at once.
        lease.requestScan(.always)
        guard case .scanStarted = await events.next() else { return XCTFail("A scan asked outright starts") }
        guard case .scanFinished(_, let isAnotherScanQueued) = await events.next() else { return XCTFail("It finishes") }
        XCTAssertFalse(isAnotherScanQueued, "No spaced scan had started, or this one would follow it; and it covers the one waiting.")
    }

    func testASpacedScanRunsOnceTheSpacingHasPassed() async throws {
        let vault = try TemporaryVault.make(prefix: "SpacingVault", for: self).root
        let caches = try TemporaryVault.make(prefix: "SpacingCaches", for: self).root
        let clock = ManualClock()
        let registry = VaultIndexRegistry(cachesFolder: caches, minimumSpacingOfSpacedScans: .seconds(30), clock: clock)
        let lease = try await registry.lease(forVault: UUID(), root: vault)
        defer { lease.end() }
        var events = lease.events.makeAsyncIterator()
        lease.requestScan(.always)
        guard case .scanStarted = await events.next(), case .scanFinished = await events.next() else { return XCTFail("The first scan runs") }

        lease.requestScan(.spaced)
        try await clock.awaitPendingSleepers()
        clock.advance(by: .seconds(30))
        guard case .scanStarted = await events.next(), case .scanFinished = await events.next() else { return XCTFail("The spaced scan runs") }
    }

    func testAFolderRequestBeforeAnyWholeScanScansTheWholeVault() async throws {
        let vault = try TemporaryVault.make(prefix: "SpacingVault", for: self).root
        try Data("note".utf8).write(to: vault.appendingPathComponent("Top.md"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        let caches = try TemporaryVault.make(prefix: "SpacingCaches", for: self).root
        let registry = VaultIndexRegistry(cachesFolder: caches)
        let lease = try await registry.lease(forVault: UUID(), root: vault)
        defer { lease.end() }
        var events = lease.events.makeAsyncIterator()
        lease.requestScan(.folder(try VaultPath("Folder")))
        guard case .scanStarted = await events.next(), case .scanFinished(let report, _) = await events.next() else { return XCTFail("A scan runs") }
        XCTAssertEqual(report.discoveredFiles, 1)
        let isFinished = try await lease.index.hasFinishedAScan()
        XCTAssertTrue(isFinished, "A window's complete state stands only on a scan of everything.")
    }
}
