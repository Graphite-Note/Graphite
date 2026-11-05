/**
 * File: BasePrefilterPushdownTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The filters a base pushes into the index's SQL give the results a full evaluation gives, every
 *              matching file is loaded however many there are, and bases over a 32,000-file index stay fast.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// A base run as the app runs it: the pre-filter in SQL, compact records of every candidate,
/// then the evaluator. Generated notes only, in a temporary folder.
private struct BaseRun {
    let definition: BaseDefinition
    let rows: [String]
    let matchingCount: Int
    let candidateCount: Int

    static func run(_ baseSource: String, index: VaultIndex) async throws -> BaseRun {
        let definition = try BaseDefinition.parse(baseSource)
        let environment = BaseEvaluationEnvironment()
        let provider = index.baseRecordProvider
        let filters = [definition.filters].compactMap { filter in filter } + definition.views.compactMap(\.filters)
        let prefilter = BaseRecordPrefilter.extract(from: filters, definition: definition, environment: environment, thisRecord: nil, provider: provider)
        let contents = BaseRecordContents(baseSourceText: baseSource, viewTypes: definition.views.map(\.type))
        let batch = try await index.baseRecords(matching: prefilter, contents: contents)
        let result = await Task.detached {
            BaseQueryEngine(definition: definition, environment: environment, thisRecord: nil, provider: provider).run(viewIndex: 0, records: batch.records)
        }.value
        return BaseRun(definition: definition, rows: result.rows.map(\.path.rawValue).sorted(), matchingCount: result.matchingCount, candidateCount: batch.records.count)
    }

    /// The same base evaluated over every file's whole record, without the pre-filter.
    static func fullEvaluation(_ baseSource: String, index: VaultIndex) async throws -> [String] {
        let definition = try BaseDefinition.parse(baseSource)
        let provider = index.baseRecordProvider
        let batch = try await index.baseRecords(matching: BaseRecordPrefilter())
        return await Task.detached {
            BaseQueryEngine(definition: definition, environment: BaseEvaluationEnvironment(), thisRecord: nil, provider: provider)
                .run(viewIndex: 0, records: batch.records).rows.map(\.path.rawValue).sorted()
        }.value
    }
}

final class BasePrefilterPushdownTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var fileCount = 0

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "PushdownVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        // Folders and tags that differ only by case, by a prefix, or by an accent, so a
        // pushed-down filter that reads them more loosely or more strictly than the evaluator shows.
        let folders = ["Recipes", "Recipes/Desserts", "recipes", "Recipes Old", "Archive/Recipes", "Journal", "Café", ""]
        let tagSets = [["recipe"], ["recipe/dessert"], ["Recipe"], ["recipes"], ["travel"], ["café"], [], ["recipe", "travel"]]
        let statuses = ["reading", "done", "Reading", ""]
        var files: [IndexedFile] = []
        for noteNumber in 0..<1_200 {
            let folder = folders[noteNumber % folders.count]
            let tags = tagSets[(noteNumber / 3) % tagSets.count]
            let status = statuses[(noteNumber / 7) % statuses.count]
            let fileExtension = noteNumber % 50 == 0 ? "canvas" : "md"
            let name = String(format: "Note %05d.\(fileExtension)", noteNumber)
            var markdown = "---\n"
            if !status.isEmpty { markdown += "status: \(status)\n" }
            if noteNumber % 5 == 0 { markdown += "Rating: \(noteNumber % 10)\n" }
            markdown += "---\n" + tags.map { tag in "#\(tag)" }.joined(separator: " ") + "\n"
            files.append(IndexedFile(path: try VaultPath(folder.isEmpty ? name : folder + "/" + name), size: 1, modified: .now,
                                     markdown: fileExtension == "md" ? markdown : ""))
        }
        fileCount = files.count
        try await index.update(files, generation: "pushdown")
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    /// Filters by kind and combined, each with whether the index must narrow its files.
    private static let filterCases: [(filters: String, narrows: Bool)] = [
        ("filters: file.hasTag(\"recipe\")", true),
        ("filters: file.hasTag(\"#recipe/dessert\", \"travel\")", true),
        ("filters: file.inFolder(\"Recipes\")", true),
        ("filters: file.inFolder(\"recipes/\")", true),
        ("filters: file.folder == \"Recipes\"", true),
        ("filters: file.folder == \"/\"", true),
        ("filters: file.tags.contains(\"#recipe\")", true),
        ("filters: file.ext == \"canvas\"", true),
        ("filters: file.name == \"Note 00010.md\"", true),
        ("filters: file.basename == \"Note 00011\"", true),
        ("filters: file.hasProperty(\"rating\")", true),
        ("filters: status == \"reading\"", true),
        ("filters:\n  or:\n    - file.hasTag(\"recipe\")\n    - file.inFolder(\"Recipes\")", true),
        ("filters:\n  not:\n    - file.inFolder(\"Recipes\")", true),
        ("filters:\n  not:\n    - file.hasTag(\"recipe\")\n    - file.inFolder(\"Journal\")", true),
        ("filters:\n  and:\n    - file.inFolder(\"Recipes\")\n    - not:\n        - file.hasTag(\"recipe/dessert\")", true),
        ("filters:\n  not:\n    - or:\n        - file.hasTag(\"recipe\")\n        - file.inFolder(\"Journal\")", true),
        ("filters: file.hasTag(\"travel\") || file.inFolder(\"Journal\")", true),
        ("filters: '!file.inFolder(\"Archive\")'", true),
        ("filters: 'file.inFolder(\"Recipes\") && !file.hasTag(\"recipe\")'", true),
        ("filters:\n  or:\n    - file.hasTag(\"café\")\n    - file.inFolder(\"Café\")", false),
        ("filters:\n  not:\n    - file.inFolder(\"Café\")", false),
        ("filters: '!(file.hasTag(\"recipe\") && status == \"done\")'", false),
        ("filters:\n  not:\n    - status == \"done\"", false),
        ("filters:\n  or:\n    - file.hasTag(\"recipe\")\n    - status.contains(\"ead\")", true),
        ("filters:\n  or:\n    - file.hasTag(\"recipe\")\n    - file.mtime > now() - \"1 day\"", false),
    ]

    func testEachPushedDownFilterGivesTheResultsOfAFullEvaluation() async throws {
        for (filters, narrows) in Self.filterCases {
            let baseSource = filters + "\nviews:\n  - type: table\n    name: Table\n    order: [file.name, status, Rating]\n"
            let pushedDown = try await BaseRun.run(baseSource, index: index)
            XCTAssertTrue(pushedDown.definition.issues.isEmpty, "\(filters): \(pushedDown.definition.issues)")
            let expected = try await BaseRun.fullEvaluation(baseSource, index: index)
            XCTAssertEqual(pushedDown.rows, expected, filters)
            XCTAssertGreaterThan(expected.count, 0, "\(filters) matches some files")
            if narrows {
                XCTAssertLessThan(pushedDown.candidateCount, fileCount, "\(filters) narrows the files loaded")
            }
        }
    }

    func testANotLetsThroughEveryFileItsConditionCannotRuleOut() async throws {
        let definition = try BaseDefinition.parse("filters:\n  not:\n    - file.inFolder(\"Recipes\")\n    - file.hasProperty(\"rating\")\n")
        let prefilter = BaseRecordPrefilter.extract(from: [definition.filters].compactMap { filter in filter }, definition: definition,
                                                    environment: BaseEvaluationEnvironment(), thisRecord: nil)
        XCTAssertEqual(prefilter.condition, .noneOf([.requirement(.inAnyFolder(["Recipes"]), isExact: true), .requirement(.hasAnyProperty(["rating"]), isExact: false)]))
        XCTAssertTrue(prefilter.requirements.isEmpty)
    }

    func testCompactRecordsKeepOnlyWhatTheBaseNames() {
        let tableOfStatus = BaseRecordContents(baseSourceText: "filters: file.inFolder(\"A\")\nviews:\n  - type: table\n    order: [status]\n", viewTypes: [.table])
        XCTAssertTrue(tableOfStatus.keepsProperty(named: "Status"))
        XCTAssertFalse(tableOfStatus.keepsProperty(named: "rating"))
        XCTAssertFalse(tableOfStatus.keepsTags)
        XCTAssertFalse(tableOfStatus.keepsLinks)
        for sourceText in ["formulas:\n  all: note.keys()\n", "order: [file.properties]", "formulas:\n  x: note[formula.key]\n", "filters: file.hasLink(\"A\")",
                           "filters: file.hasProperty(this.key)"] {
            XCTAssertTrue(BaseRecordContents(baseSourceText: sourceText, viewTypes: [.table]).keepsEveryProperty, sourceText)
        }
        XCTAssertTrue(BaseRecordContents(baseSourceText: "views:\n  - type: timeline\n", viewTypes: [.unsupported("timeline")]).keepsEveryProperty)
        XCTAssertTrue(BaseRecordContents(baseSourceText: "filters: file.hasTag(\"a\")", viewTypes: [.table]).keepsTags)
    }
}

/// Bases over a generated 32,000-file index: complete results beyond the 5,000 files the
/// index once loaded, and the time each base takes on this build.
final class BaseWholeVaultTimingTests: XCTestCase {
    private static let fileCount = 32_000
    private static let filesPerFolder = 100

    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "WholeVaultBases", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        var files: [IndexedFile] = []
        for noteNumber in 0..<Self.fileCount {
            // One file in a hundred is a recipe by tag, and folder 7 of each 320 holds recipes.
            let folderNumber = noteNumber / Self.filesPerFolder
            let folder = folderNumber == 7 ? "Recipes" : "Notes \(folderNumber % 40)/Sub \(folderNumber)"
            let tags = noteNumber % 100 == 3 ? "#recipe/dessert #food" : "#topic\(noteNumber % 30) #area/part\(noteNumber % 7)"
            let markdown = "---\nstatus: \(["reading", "done", "planned"][noteNumber % 3])\nrating: \(noteNumber % 10)\nauthor: Person \(noteNumber % 200)\n"
                + "created: 2026-01-\(String(format: "%02d", noteNumber % 28 + 1))\n---\n\(tags)\nA line with [[Note \(noteNumber + 1)]] and [[Other]].\n"
            files.append(IndexedFile(path: try VaultPath(String(format: "\(folder)/Note %05d.md", noteNumber)), size: markdown.utf8.count, modified: .now, markdown: markdown))
            if files.count == 4_000 {
                try await index.update(files, generation: "scale")
                files.removeAll(keepingCapacity: true)
            }
        }
        if !files.isEmpty { try await index.update(files, generation: "scale") }
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private static let view = "\nviews:\n  - type: table\n    name: Table\n    order: [file.name, status, rating]\n    sort:\n      - property: file.name\n        direction: ASC\n"

    /// The fastest of three runs, which leaves out the first statement's preparation.
    private func timedRun(_ baseSource: String) async throws -> (run: BaseRun, elapsedSeconds: Double) {
        var fastest = Double.infinity
        var lastRun: BaseRun?
        for _ in 0..<3 {
            let start = ContinuousClock.now
            lastRun = try await BaseRun.run(baseSource, index: index)
            let elapsed = ContinuousClock.now - start
            fastest = min(fastest, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        return (try XCTUnwrap(lastRun), fastest)
    }

    func testBasesOverAWholeVaultAreCompleteAndFast() async throws {
        let tagged = try await timedRun("filters: file.hasTag(\"recipe\")" + Self.view)
        XCTAssertEqual(tagged.run.matchingCount, Self.fileCount / 100)
        let inFolder = try await timedRun("filters: file.inFolder(\"Recipes\")" + Self.view)
        XCTAssertEqual(inFolder.run.matchingCount, Self.filesPerFolder)
        let either = try await timedRun("filters:\n  or:\n    - file.hasTag(\"recipe\")\n    - file.inFolder(\"Recipes\")" + Self.view)
        XCTAssertEqual(either.run.matchingCount, Self.fileCount / 100 + Self.filesPerFolder - 1, "Note 00703 is in both.")
        let everything = try await timedRun("views:\n  - type: table\n    name: Table\n    order: [file.name, status, rating]\n")
        XCTAssertEqual(everything.run.matchingCount, Self.fileCount, "Every file, far beyond 5,000.")
        let manyMatches = try await timedRun("filters:\n  or:\n    - status == \"reading\"\n    - file.inFolder(\"Recipes\")" + Self.view)
        let readingOrRecipeCount = (0..<Self.fileCount).filter { noteNumber in noteNumber % 3 == 0 || noteNumber / Self.filesPerFolder == 7 }.count
        XCTAssertEqual(manyMatches.run.matchingCount, readingOrRecipeCount, "Every match, beyond 5,000.")
        print(String(format: "Bases over %d files: tag %.1f ms (%d files loaded), folder %.1f ms (%d), tag or folder %.1f ms (%d), every file %.0f ms, status or folder %.0f ms (%d matches)",
                     Self.fileCount, tagged.elapsedSeconds * 1_000, tagged.run.candidateCount, inFolder.elapsedSeconds * 1_000, inFolder.run.candidateCount,
                     either.elapsedSeconds * 1_000, either.run.candidateCount, everything.elapsedSeconds * 1_000, manyMatches.elapsedSeconds * 1_000,
                     manyMatches.run.matchingCount))
        XCTAssertLessThan(tagged.elapsedSeconds, 0.1)
        XCTAssertLessThan(inFolder.elapsedSeconds, 0.1)
        XCTAssertLessThan(either.elapsedSeconds, 0.1)
        XCTAssertLessThan(everything.elapsedSeconds, 1.5)
    }
}
