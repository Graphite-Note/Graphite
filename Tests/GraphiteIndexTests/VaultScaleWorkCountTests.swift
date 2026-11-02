/**
 * File: VaultScaleWorkCountTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: What a base run and a scan cost at the sizes of a real vault, counted in reads made, files
 *              looked at and questions asked, over thousands of generated notes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import Synchronization
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// HUNT-029: a base of 5,000 records, with columns that ask about links and backlinks.
final class BaseRunAtVaultScaleWorkCountTests: XCTestCase {
    private static let bookCount = 5_000

    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "BaseScaleVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        for folder in ["Books", "People"] {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        // Every book links to the next book, and in its properties to a person outside the base,
        // by a partial path.
        for number in 0..<Self.bookCount {
            let text = "---\nauthor: \"[[People/Person \(number)]]\"\n---\n[[Book \((number + 1) % Self.bookCount)]]\n"
            try Data(text.utf8).write(to: vault.appendingPathComponent("Books/Book \(number).md"))
            try Data("---\nage: \(number)\n---\n".utf8).write(to: vault.appendingPathComponent("People/Person \(number).md"))
        }
        _ = try await index.reconcile(root: vault)
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func run(formulas: String, provider: BaseIndexRecordProvider) async throws -> BaseQueryResult {
        let baseText = """
            filters: file.inFolder("Books")
            formulas:
            \(formulas)
            views:
              - type: table
                name: Table
                order: [file.name, formula.answer]
            """
        let definition = try BaseDefinition.parse(baseText)
        XCTAssertTrue(definition.issues.isEmpty, "\(definition.issues)")
        let environment = BaseEvaluationEnvironment(now: .now, calendar: BaseDateFormatting.displayCalendar, declaredTypes: [:])
        let context = try VaultPath("Books.base")
        let thisRecord = BaseFileRecord(path: context, size: 0, createdDate: .now, modifiedDate: .now)
        let filters = [definition.filters, definition.views[0].filters].compactMap { filter in filter }
        let prefilter = BaseRecordPrefilter.extract(from: filters, definition: definition, environment: environment, thisRecord: thisRecord)
        let batch = try await index.baseRecords(matching: prefilter)
        XCTAssertEqual(batch.records.count, Self.bookCount)
        return BaseQueryEngine(definition: definition, environment: environment, thisRecord: thisRecord, provider: provider).run(viewIndex: 0, records: batch.records)
    }

    private func answers(_ result: BaseQueryResult) -> [String: String] {
        Dictionary(uniqueKeysWithValues: result.rows.map { row in (row.path.stem, row.cells[1].value?.displayText ?? "") })
    }

    private func readsOneFileAtATime() -> BaseIndexRecordProvider {
        BaseIndexRecordProvider(databasePool: index.databasePool, lookupsBeforeLoadingLinks: .max, readsRecordsAhead: false)
    }

    func testABacklinksColumnOver5000RowsIsNineReadsAndAnswersAsOneReadPerRowDoes() async throws {
        let formula = "  answer: file.backlinks.length"
        let oneByOne = readsOneFileAtATime()
        let expected = try await run(formulas: formula, provider: oneByOne)
        XCTAssertEqual(oneByOne.lookupReadCount, Self.bookCount)

        let provider = index.baseRecordProvider
        let result = try await run(formulas: formula, provider: provider)

        XCTAssertEqual(provider.lookupReadCount, BaseIndexRecordProvider.lookupsBeforeLoadingLinks + 1)
        XCTAssertEqual(answers(result), answers(expected))
        XCTAssertEqual(answers(result)["Book 7"], "1")
    }

    func testALinkByPartialPathOver5000RowsResolvesFromMemory() async throws {
        let formula = "  answer: file.hasLink(note.author)"
        let oneByOne = readsOneFileAtATime()
        let expected = try await run(formulas: formula, provider: oneByOne)
        XCTAssertEqual(oneByOne.lookupReadCount, Self.bookCount * 2, "One resolve and one more for each row, each scanning the files' folded paths.")

        let provider = index.baseRecordProvider
        let result = try await run(formulas: formula, provider: provider)

        XCTAssertEqual(provider.lookupReadCount, BaseIndexRecordProvider.lookupsBeforeLoadingLinks + 1)
        XCTAssertEqual(answers(result), answers(expected))
    }

    func testTheNameOfALinkedFileReadsNoRecord() async throws {
        let formula = "  answer: note.author.asFile().name"
        let provider = index.baseRecordProvider
        let result = try await run(formulas: formula, provider: provider)

        XCTAssertEqual(provider.lookupReadCount, BaseIndexRecordProvider.lookupsBeforeLoadingLinks + 1, "Was 5,009: a record read per row for a name the path holds.")
        XCTAssertEqual(provider.recordsReadAheadCount, 0)
        XCTAssertEqual(answers(result)["Book 7"], "Person 7.md")
    }

    func testAFieldOfLinkedFilesOutsideTheRowsReadsThemTogether() async throws {
        let formula = "  answer: note.author.asFile().properties.age"
        let oneByOne = readsOneFileAtATime()
        let expected = try await run(formulas: formula, provider: oneByOne)
        XCTAssertEqual(oneByOne.lookupReadCount, Self.bookCount * 2, "One resolve and one record read for each row.")

        let provider = index.baseRecordProvider
        let result = try await run(formulas: formula, provider: provider)

        XCTAssertLessThan(provider.lookupReadCount, 150, "Was 5,009 with the links in memory.")
        XCTAssertLessThan(provider.recordsReadAheadCount, 5_100, "Few records beyond those asked about.")
        XCTAssertEqual(answers(result), answers(expected))
        XCTAssertEqual(answers(result)["Book 7"], "7")
    }

    func testAFewLinkedFilesReadLittleMoreThanThemselves() async throws {
        let provider = index.baseRecordProvider
        let people = try (0..<8).map { number in try VaultPath("People/Person \(number * 500).md") }

        let ages = people.map { person in provider.record(at: person)?.properties.first?.key }

        XCTAssertEqual(ages, Array(repeating: "age", count: 8))
        XCTAssertEqual(provider.lookupReadCount, 8)
        XCTAssertLessThanOrEqual(provider.recordsReadAheadCount, 36, "As many as were asked about so far: 1 + 2 + … + 8.")
        XCTAssertNil(provider.record(at: try VaultPath("People/Nobody.md")))
    }
}

/// HUNT-042, HUNT-045: scans of a vault of 30,000 files.
final class ScanAtVaultScaleWorkCountTests: XCTestCase {
    private static let fileCount = 30_000
    private static let filesInSyncedFolder = 12

    private var vault: URL!
    private var databaseURL: URL!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ScanScaleVault", for: self).root
        databaseURL = vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite")
        let folders = ["Synced"] + (0..<300).map { number in "Folder \(number)" }
        for folder in folders { try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true) }
        for number in 0..<Self.filesInSyncedFolder { try Data("note".utf8).write(to: vault.appendingPathComponent("Synced/Note \(number).md")) }
        for number in Self.filesInSyncedFolder..<Self.fileCount {
            try Data("note".utf8).write(to: vault.appendingPathComponent("Folder \(number % 300)/Note \(number).md"))
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    func testAFolderReportedLooksAtItsOwnFilesNotTheVaults() async throws {
        let index = try VaultIndex(databaseURL: databaseURL)
        let wholeScan = try await index.reconcile(root: vault)
        XCTAssertEqual(wholeScan.examinedFiles, Self.fileCount, "What each report of a folder cost before.")

        try Data("new".utf8).write(to: vault.appendingPathComponent("Synced/New.md"))
        let folderScan = try await index.reconcile(root: vault, inside: try VaultPath("Synced"))

        XCTAssertEqual(folderScan.examinedFiles, Self.filesInSyncedFolder + 1)
        XCTAssertEqual(folderScan.updatedFiles, 1)
        XCTAssertEqual(folderScan.discoveredFiles, Self.fileCount + 1, "A window says the vault's count.")
    }

    func testALaunchAsksTheProviderNothingAboutFilesStillInTheCloud() async throws {
        let questions = Mutex((provider: 0, placeholder: 0))
        let index = try VaultIndex(databaseURL: databaseURL, cloudFileStatus: CloudFileStatus(isNotDownloaded: { _ in
            questions.withLock { state in state.provider += 1 }
            return true
        }, isDatalessPlaceholder: { _ in
            questions.withLock { state in state.placeholder += 1 }
            return true
        }))
        _ = try await index.reconcile(root: vault)
        XCTAssertEqual(questions.withLock { state in state.provider }, Self.fileCount, "The first scan asks about each new file; before, every scan did.")

        questions.withLock { state in state = (0, 0) }
        let nextLaunch = try await index.reconcile(root: vault)

        XCTAssertEqual(questions.withLock { state in state.provider }, 0)
        XCTAssertEqual(questions.withLock { state in state.placeholder }, Self.fileCount, "One system call each, which the provider does not hear of.")
        XCTAssertFalse(nextLaunch.changedAnything)
    }
}
