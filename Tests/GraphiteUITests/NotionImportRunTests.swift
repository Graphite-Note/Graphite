/**
 * File: NotionImportRunTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: An import of a made-up Notion HTML export into a vault through Graphite's coordinated writes: where it
 *              goes, what it writes, the property types, Pause, Cancel, the report, and an export that is not one.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteTestSupport
import GraphiteFixtures
@testable import GraphiteUI

/// An import of Notion's export run as the workspace runs it, on a temporary vault: the export goes into a new folder
/// "Notion" (a free name), notes, a base, an attachment and the report note are written through the vault's store,
/// property types join `.obsidian/types.json` without changing the vault's own, nothing already there is replaced, the
/// files written reach the vault in batches, Pause holds every write until Resume, and Cancel leaves a usable part.
final class NotionImportRunTests: XCTestCase {
    private static let courseIdentifier = "1111111111111111aaaaaaaaaaaaaaaa"
    private static let weekIdentifier = "2222222222222222aaaaaaaaaaaaaaaa"
    private static let lecturesIdentifier = "3333333333333333aaaaaaaaaaaaaaaa"
    private static let introIdentifier = "4444444444444444aaaaaaaaaaaaaaaa"

    /// The files the run handed to the vault, as the workspace hears them on the main actor.
    @MainActor private final class DeliveredFiles {
        var batches: [[VaultPath]] = []
        var paths: [String] { batches.flatMap { batch in batch.map(\.rawValue) } }
    }

    private static func hyphenated(_ identifier: String) -> String {
        let characters = Array(identifier)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { range in String(characters[range]) }.joined(separator: "-")
    }

    /// A page as Notion's HTML export writes one.
    private static func page(_ identifier: String, title: String, header: String = "", body: String) -> String {
        """
        <html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"/><title>\(title)</title></head><body>\
        <article id="\(hyphenated(identifier))" class="page sans"><header>\(header)<h1 class="page-title">\(title)</h1></header>\
        <div class="page-body">\(body)</div></article></body></html>
        """
    }

    /// A made-up export, unzipped: a course page linking a week page and a picture, and a database of lectures whose
    /// row has a date and a checkbox.
    static func writeExport(in folder: TemporaryVault) throws -> URL {
        let course = "Course \(courseIdentifier)"
        let lectures = "Lectures \(lecturesIdentifier)"
        let table = """
            <table class="collection-content"><thead><tr><th>Name</th><th><span class="icon property-icon"><svg class="typesDate"></svg></span>Date</th>\
            <th><span class="icon property-icon"><svg class="typesCheckbox"></svg></span>Done</th></tr></thead><tbody>\
            <tr id="\(hyphenated(introIdentifier))"><td class="cell-title"><a href="\(lectures)/Intro%20\(introIdentifier).html">Intro</a></td>\
            <td class="cell-a"><time>@March 4, 2024</time></td><td class="cell-b"><div class="checkbox checkbox-on"></div></td></tr></tbody></table>
            """
        try folder.writeFile("Export/\(course).html", text: page(courseIdentifier, title: "Course", body: """
            <p id="a1" class="">See <a href="Course%20\(courseIdentifier)/Week%201%20\(weekIdentifier).html">Week 1</a>.</p>\
            <figure id="a2" class="image"><a href="Course%20\(courseIdentifier)/diagram.png"><img src="Course%20\(courseIdentifier)/diagram.png"/></a></figure>
            """))
        try folder.writeFile("Export/\(course)/Week 1 \(weekIdentifier).html",
                             text: page(weekIdentifier, title: "Week 1", body: "<p id=\"b1\" class=\"\">Back to <a href=\"../Course%20\(courseIdentifier).html\">the course</a>.</p>"))
        try folder.writeFile("Export/\(course)/diagram.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 7, count: 200_000)))
        try folder.writeFile("Export/\(lectures).html", text: page(lecturesIdentifier, title: "Lectures", body: table))
        try folder.writeFile("Export/\(lectures)/Intro \(introIdentifier).html", text: page(introIdentifier, title: "Intro", header: """
            <table class="properties"><tbody><tr class="property-row property-row-date"><th>Date</th><td><time>@March 4, 2024</time></td></tr>\
            <tr class="property-row property-row-checkbox"><th>Done</th><td><div class="checkbox checkbox-on"></div></td></tr></tbody></table>
            """, body: "<p id=\"c1\" class=\"\">The first lecture.</p>"))
        return folder.location(of: "Export")
    }

    private static func makeRun(vault: TemporaryVault, pause: NotionImportPause = NotionImportPause(), delivered: DeliveredFiles) -> NotionImportRun {
        NotionImportRun(store: VaultStore(root: vault.root), pause: pause, filesDidChange: { paths in delivered.batches.append(paths) },
                        importDate: Date(timeIntervalSince1970: 1_764_115_200), calendar: Calendar(identifier: .gregorian))
    }

    private static func run(_ run: NotionImportRun, sources: [URL], into directory: VaultPath) async -> (NotionImportSummary, [NotionImportProgress]) {
        let (progressUpdates, continuation) = AsyncStream.makeStream(of: NotionImportProgress.self)
        let summary = await run.run(sources: sources, into: directory, progress: continuation)
        continuation.finish()
        var updates: [NotionImportProgress] = []
        for await update in progressUpdates { updates.append(update) }
        return (summary, updates)
    }

    func testTheExportGoesIntoAFreeNotionFolderWithItsNotesBaseAttachmentTypesAndReport() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportRun", files: [
            "Courses/Notion/Kept.md": "already here",
            ".obsidian/types.json": "{\n  \"types\": {\n    \"done\": \"text\"\n  }\n}"
        ], for: self)
        let exportFolder = try TemporaryVault.make(prefix: "NotionExport", for: self)
        let export = try Self.writeExport(in: exportFolder)
        let delivered = DeliveredFiles()
        let (summary, updates) = await Self.run(Self.makeRun(vault: vault, delivered: delivered), sources: [export], into: try VaultPath("Courses"))

        XCTAssertNil(summary.failureMessage)
        XCTAssertEqual(summary.folder?.rawValue, "Courses/Notion 1")
        XCTAssertEqual(summary.noteCount, 3)
        XCTAssertEqual(summary.baseCount, 1)
        XCTAssertEqual(summary.attachmentCount, 1)
        XCTAssertFalse(summary.wasCancelled)
        XCTAssertEqual(summary.reportPath?.rawValue, "Courses/Notion 1/Notion import report.md")
        XCTAssertEqual(try vault.readText(at: "Courses/Notion/Kept.md"), "already here")
        XCTAssertTrue(try vault.readText(at: "Courses/Notion 1/Course.md").contains("[[Week 1]]"))
        XCTAssertTrue(try vault.readText(at: "Courses/Notion 1/Lectures.base").contains("file.folder"))
        XCTAssertEqual(try Data(contentsOf: vault.location(of: "Courses/Notion 1/Course/diagram.png")).count, 200_008)
        XCTAssertTrue(try vault.readText(at: "Courses/Notion 1/Notion import report.md").contains("Notion import"))
        // The vault's own type of "done" is kept; the date the import found is added.
        let types = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: vault.location(of: ".obsidian/types.json"))) as? [String: [String: String]])
        XCTAssertEqual(types["types"]?["done"], "text")
        XCTAssertEqual(types["types"]?["Date"], "date")
        // Every file written reached the vault, the folder last, and the progress counted every page.
        let deliveredPaths = await delivered.paths
        XCTAssertTrue(deliveredPaths.contains("Courses/Notion 1/Course.md"))
        XCTAssertTrue(deliveredPaths.contains("Courses/Notion 1/Course/diagram.png"))
        XCTAssertEqual(deliveredPaths.last, "Courses/Notion 1")
        XCTAssertEqual(updates.last, NotionImportProgress(finishedPageCount: 4, pageCount: 4))
        // The source is never changed.
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.appendingPathComponent("Course \(Self.courseIdentifier).html").path))
    }

    func testPauseHoldsEveryWriteUntilResume() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportPause", for: self)
        let exportFolder = try TemporaryVault.make(prefix: "NotionExport", for: self)
        let export = try Self.writeExport(in: exportFolder)
        let delivered = DeliveredFiles()
        let pause = NotionImportPause()
        pause.pause()
        let run = Self.makeRun(vault: vault, pause: pause, delivered: delivered)
        let importTask = Task.detached { await Self.run(run, sources: [export], into: .root) }
        try await waitUntil("the import waits to write") { pause.waitingWriteCount > 0 }
        XCTAssertFalse(vault.fileExists(at: "Notion"), "nothing is written while the import is paused")
        pause.resume()
        let (summary, _) = await importTask.value
        XCTAssertEqual(summary.noteCount, 3)
        XCTAssertTrue(vault.fileExists(at: "Notion/Course.md"))
    }

    func testCancelLeavesWhatWasWrittenAndAReportThatSaysSo() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportCancel", for: self)
        let exportFolder = try TemporaryVault.make(prefix: "NotionExport", for: self)
        let export = try Self.writeExport(in: exportFolder)
        let delivered = DeliveredFiles()
        let pause = NotionImportPause()
        pause.pause()
        let run = Self.makeRun(vault: vault, pause: pause, delivered: delivered)
        let importTask = Task.detached { await Self.run(run, sources: [export], into: .root) }
        try await waitUntil("the import waits to write") { pause.waitingWriteCount > 0 }
        // As the session's Cancel does: the task is cancelled, then a paused import is let go.
        importTask.cancel()
        pause.resume()
        let (summary, _) = await importTask.value
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertNil(summary.failureMessage)
        let report = try vault.readText(at: "Notion/Notion import report.md")
        XCTAssertTrue(report.contains("stopped"), report)
        XCTAssertFalse(vault.fileExists(at: "Notion/Course/diagram.png"), "attachments come after the pages and are not started")
    }

    func testAFolderWithNoNotionPageEndsInAMessageAndWritesNothing() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportRefusal", for: self)
        let exportFolder = try TemporaryVault.make(prefix: "NotionExport", files: ["Export/Readme.txt": "not an export"], for: self)
        let delivered = DeliveredFiles()
        let (summary, _) = await Self.run(Self.makeRun(vault: vault, delivered: delivered), sources: [exportFolder.location(of: "Export")], into: .root)
        XCTAssertEqual(summary.failureMessage?.hasPrefix("This file holds no Notion page."), true, summary.failureMessage ?? "")
        XCTAssertEqual(summary.noteCount, 0)
        XCTAssertFalse(vault.fileExists(at: "Notion"))
        let deliveredPaths = await delivered.paths
        XCTAssertEqual(deliveredPaths, [])
    }

    func testAFileThatIsNotAZipEndsInAMessage() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportNotAZip", for: self)
        let exportFolder = try TemporaryVault.make(prefix: "NotionExport", files: ["Export.zip": "truncated"], for: self)
        let delivered = DeliveredFiles()
        let (summary, _) = await Self.run(Self.makeRun(vault: vault, delivered: delivered), sources: [exportFolder.location(of: "Export.zip")], into: .root)
        XCTAssertEqual(summary.failureMessage?.hasPrefix("The export could not be read as a zip file"), true, summary.failureMessage ?? "")
        XCTAssertFalse(vault.fileExists(at: "Notion"))
    }

    private static let madeUpExports = FixtureFolders.repositoryRoot.appendingPathComponent("Tests/Fixtures/NotionExports", isDirectory: true)

    func testADownloadCutShortEndsInAMessageAndWritesNothing() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportTruncated", for: self)
        let delivered = DeliveredFiles()
        let (summary, _) = await Self.run(Self.makeRun(vault: vault, delivered: delivered),
                                          sources: [Self.madeUpExports.appendingPathComponent("made-up-export-truncated.zip")], into: .root)
        XCTAssertEqual(summary.failureMessage?.hasPrefix("The export could not be read as a zip file"), true, summary.failureMessage ?? "")
        XCTAssertFalse(vault.fileExists(at: "Notion"))
    }

    func testAPartOfALargeExportAloneImportsItsPagesAndReportsTheLinkToAPageItLacks() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportPartAlone", for: self)
        let delivered = DeliveredFiles()
        let (summary, _) = await Self.run(Self.makeRun(vault: vault, delivered: delivered),
                                          sources: [Self.madeUpExports.appendingPathComponent("made-up-export-Part-2.zip")], into: .root)
        XCTAssertNil(summary.failureMessage)
        XCTAssertEqual(summary.noteCount, 2)
        XCTAssertTrue(vault.fileExists(at: "Notion/Semester/Algebra.md") || vault.fileExists(at: "Notion/Algebra.md"))
        XCTAssertGreaterThan(summary.findingCount, 0, "The link to Semester, which this part lacks, is reported.")
    }

    func testTheSummaryWordingSaysWhatWasWrittenAndWhatTheReportLists() throws {
        var summary = NotionImportSummary(folder: try VaultPath("Notion"), reportPath: try VaultPath("Notion/Notion import report.md"),
                                          noteCount: 12, baseCount: 1, attachmentCount: 0, findingCount: 3)
        XCTAssertEqual(NotionImportWording.title(of: summary), "Notion Import Finished")
        XCTAssertEqual(NotionImportWording.headline(of: summary), "Imported 12 notes and 1 base into “Notion”.")
        XCTAssertEqual(NotionImportWording.details(of: summary), ["The report lists 3 things that were simplified or left out."])
        summary.wasCancelled = true
        XCTAssertEqual(NotionImportWording.title(of: summary), "Notion Import Stopped")
        XCTAssertEqual(NotionImportWording.details(of: summary).count, 2)
        XCTAssertEqual(NotionImportWording.progressDetail(NotionImportProgress(finishedPageCount: 3, pageCount: 40)), "3 of 40 pages")
        XCTAssertEqual(NotionImportWording.progressDetail(NotionImportProgress()), "Reading the export…")
    }
}
