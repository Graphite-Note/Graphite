/**
 * File: NotebookImportEndToEndTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Goodnotes and Notability notebooks imported through the app's own Import call, every element they hold
 *              read back from the vault's PDFs: pages and sizes, paper, ink as PencilKit and PDF ink, pictures, outline,
 *              bookmarks, recordings and typed text as text boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteIndex
import GraphiteApple
import GraphiteFixtures
import NotebookImport
@testable import GraphiteUI
import GraphiteTestSupport

/// The synthetic notebooks of `Tests/SyntheticNotebooks` (built from the documented formats, nothing from a real
/// notebook) imported as the New menu's Import and every drop import them, through `WorkspaceModel.importFiles`, then
/// read back from the vault: each element the converter supports must be in the PDF, of its own kind, where it was.
/// Setting `GRAPHITE_IMPORT_RENDERS` to a folder also draws every imported page there as a PNG, to look at.
@MainActor
final class NotebookImportEndToEndTests: XCTestCase {
    private static let rendersFolderVariable = "GRAPHITE_IMPORT_RENDERS"
    private static let pointsPerGoodnotesUnit = 6.0 / 11.0
    private static let accuracy = 0.01

    private func makeWorkspace() async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "NotebookImportEndToEnd", files: ["Courses/Existing.md": "x"], for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "NotebookImportEndToEndIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    private func importedSummary(of sources: [URL], into folder: String, workspace: WorkspaceModel,
                                 timeoutSeconds: Double = 60) async throws -> NotebookImportSummary {
        await workspace.importFiles(from: sources, into: try VaultPath(folder))
        try await waitUntil("the notebook import has ended", timeoutSeconds: timeoutSeconds) {
            if case .finished = workspace.notebookImport?.state { true } else { false }
        }
        guard case .finished(let summary)? = workspace.notebookImport?.state else { throw GraphiteError.unavailable("The import did not end.") }
        workspace.endNotebookImport()
        return summary
    }

    private func document(_ path: String, in vault: URL) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(url: vault.appendingPathComponent(path)), path)
    }

    /// The page's imported ink: one editable group whose PencilKit drawing has one stroke per `/Ink` annotation.
    private func pencilKitDrawing(on page: PDFPage, context: String) throws -> (drawing: PKDrawing, inkAnnotationCount: Int) {
        let group = try XCTUnwrap(PDFInkGroups.editableGroup(on: page), "An ink group Graphite edits again: \(context)")
        let drawing = try XCTUnwrap(PDFPageInkTracker.restoring(group)?.drawing, "Its PencilKit drawing decodes: \(context)")
        let inkCount = page.annotations.count { annotation in
            annotation.type == "Ink" && annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String == group.group
        }
        return (drawing, inkCount)
    }

    // MARK: Every element the converter supports

    func testImportedNotebooksHoldEveryElementOfTheirSourceAsGraphiteObjects() async throws {
        let (workspace, vault) = try await makeWorkspace()
        let folder = FixtureFolders.syntheticNotebooks
        let names = ["Synthetic lecture.goodnotes", "Synthetic note.note", SyntheticNotebookNames.textBoxes, SyntheticNotebookNames.typedNote]
        let sourcesBefore = try names.map { name in try Data(contentsOf: folder.appendingPathComponent(name)) }
        let summary = try await importedSummary(of: names.map { name in folder.appendingPathComponent(name) }, into: "Courses", workspace: workspace)

        XCTAssertEqual(summary.importedCount, 4, "\(summary.outcomes)")
        XCTAssertEqual(summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue),
                       ["Courses/Synthetic lecture.pdf", "Courses/Synthetic note.pdf", "Courses/Synthetic text boxes.pdf", "Courses/Synthetic typed note.pdf"])
        XCTAssertEqual(try names.map { name in try Data(contentsOf: folder.appendingPathComponent(name)) }, sourcesBefore, "The notebooks are only read.")
        for outcome in summary.outcomes { try assertEachPageHoldsExactlyItsOwnElements(outcome, in: vault) }
        try assertGoodnotesLecture(in: vault, summary: summary)
        try assertNotabilityNote(in: vault)
        try assertGoodnotesTextBoxes(in: vault, summary: summary)
        try assertNotabilityTypedNote(in: vault, summary: summary)
        try renderPages(of: summary, in: vault)
    }

    /// Each written page holds its own strokes, pictures and text boxes and nothing of another page's: pages made from
    /// one template page once shared PDFKit's list of annotations, so every later page showed the earlier ones' too.
    private func assertEachPageHoldsExactlyItsOwnElements(_ outcome: NotebookImportOutcome, in vault: URL) throws {
        let notebook = try XCTUnwrap(outcome.importedNotebook, outcome.sourceName)
        let pdf = try document(notebook.pdf.rawValue, in: vault)
        let writtenPages = notebook.report.pages.compactMap(\.written)
        XCTAssertEqual(pdf.pageCount, writtenPages.count, outcome.sourceName)
        for (pageIndex, contents) in writtenPages.enumerated() {
            let page = try XCTUnwrap(pdf.page(at: pageIndex))
            let types = page.annotations.compactMap(\.type)
            let context = "\(outcome.sourceName) page \(pageIndex + 1)"
            XCTAssertEqual(types.count { type in type == "Ink" }, contents.strokeCount, context)
            XCTAssertEqual(types.count { type in type == "Stamp" }, contents.pictureCount, context)
            XCTAssertEqual(types.count { type in type == "FreeText" }, contents.textBoxCount, context)
        }
    }

    /// Pages of their paper's size with the paper as page content, the page without paper left out, ink as PencilKit
    /// strokes and `/Ink` annotations over a picture, the outline entry before the bookmark, and the recording beside.
    private func assertGoodnotesLecture(in vault: URL, summary: NotebookImportSummary) throws {
        let lecture = try document("Courses/Synthetic lecture.pdf", in: vault)
        XCTAssertEqual(lecture.pageCount, 3, "Its fourth page has no paper and is left out, as the report says.")
        let firstPage = try XCTUnwrap(lecture.page(at: 0))
        XCTAssertEqual(firstPage.bounds(for: .cropBox).size, CGSize(width: 600, height: 900))
        XCTAssertEqual(firstPage.annotations.map(\.type), ["Stamp", "Ink", "Ink"], "The picture under the ink.")
        XCTAssertEqual(PDFPageManager.pictures(on: firstPage).count, 1, "The picture is a Graphite picture, movable and croppable.")
        let ink = try pencilKitDrawing(on: firstPage, context: "lecture page 1")
        XCTAssertEqual(ink.drawing.strokes.count, ink.inkAnnotationCount, "One PencilKit stroke per PDF ink annotation.")
        XCTAssertEqual(ink.drawing.strokes.count, 2)
        let outline = try XCTUnwrap(lecture.outlineRoot)
        XCTAssertEqual((0..<outline.numberOfChildren).compactMap { childIndex in outline.child(at: childIndex)?.label }, ["Chapter 2", "Page 3"])
        let lectureOutcome = try XCTUnwrap(summary.outcomes.first { outcome in outcome.sourceName == "Synthetic lecture.goodnotes" }?.importedNotebook)
        XCTAssertEqual(lectureOutcome.recordings.map(\.rawValue), ["Courses/Synthetic lecture - Recording 1.m4a"])
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Courses/Synthetic lecture - Recording 1.m4a")).prefix(8).suffix(4),
                       Data("ftyp".utf8))
        XCTAssertEqual(lectureOutcome.report.writtenPageCount, 3)
        XCTAssertTrue(lectureOutcome.report.pages.contains { page in page.entries.contains(.pageWithoutPaper) })
    }

    /// The continuous note cut into its two letter pages, each with its curve as ink and its ruling as page content.
    private func assertNotabilityNote(in vault: URL) throws {
        let note = try document("Courses/Synthetic note.pdf", in: vault)
        XCTAssertEqual(note.pageCount, 2)
        for pageIndex in 0..<2 {
            let page = try XCTUnwrap(note.page(at: pageIndex))
            XCTAssertEqual(page.bounds(for: .cropBox).width, 612, accuracy: Self.accuracy)
            XCTAssertEqual(page.bounds(for: .cropBox).height, 803.25, accuracy: Self.accuracy)
            let ink = try pencilKitDrawing(on: page, context: "note page \(pageIndex + 1)")
            XCTAssertEqual(ink.drawing.strokes.count, 1)
            XCTAssertEqual(ink.inkAnnotationCount, 1)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Courses/Synthetic note - Lecture.m4a").path))
    }

    /// Goodnotes' text boxes, a turned one, a sticky note and an older RTF box, each a Graphite text box over the ink, with
    /// its font, size, colour, place, angle and link.
    private func assertGoodnotesTextBoxes(in vault: URL, summary: NotebookImportSummary) throws {
        let notebook = try document("Courses/Synthetic text boxes.pdf", in: vault)
        XCTAssertEqual(notebook.pageCount, 1)
        let page = try XCTUnwrap(notebook.page(at: 0))
        let pageHeight = Double(page.bounds(for: .cropBox).height)
        XCTAssertEqual(pageHeight, 588.45, accuracy: Self.accuracy)
        XCTAssertEqual(page.annotations.map(\.type).filter { type in type != "Link" }, ["Ink", "FreeText", "FreeText", "FreeText", "FreeText"],
                       "The text over the ink.")
        XCTAssertEqual(try pencilKitDrawing(on: page, context: "text boxes page").drawing.strokes.count, 1)
        let boxes = PDFPageManager.textBoxes(on: page)
        XCTAssertEqual(boxes.map(\.plainText), ["Graphite one", "Red two", "Sticky one", "Older box"])
        let unit = Self.pointsPerGoodnotesUnit

        let heading = boxes[0]
        XCTAssertEqual(heading.origin.x, 100 * unit, accuracy: Self.accuracy)
        XCTAssertEqual(heading.origin.y, pageHeight - 100 * unit, accuracy: Self.accuracy)
        XCTAssertEqual(heading.width, (140 + 20) * unit, accuracy: Self.accuracy, "The text's width and an inset on each side.")
        XCTAssertEqual(heading.style.padding, 10 * unit, accuracy: Self.accuracy)
        XCTAssertEqual(heading.leadingAttributes.fontFamily, "Helvetica Neue")
        XCTAssertEqual(heading.leadingAttributes.fontSize, 24 * unit, accuracy: Self.accuracy)
        XCTAssertEqual(heading.leadingAttributes.link, URL(string: "https://example.com/graphite"))
        XCTAssertTrue(isOneLine(heading), "The text breaks where Goodnotes' does: not at all.")
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Link" }.compactMap(\.url),
                       [try XCTUnwrap(URL(string: "https://example.com/graphite"))])

        let turned = boxes[1]
        XCTAssertEqual(turned.rotationRadians, Double.pi / 6, accuracy: 1e-6)
        XCTAssertEqual(turned.leadingAttributes.fontFamily, "Georgia")
        XCTAssertEqual(turned.leadingAttributes.fontSize, 36 * 2 * unit, accuracy: Self.accuracy, "Font sizes are multiplied by the box's scale.")
        let turnedColor = turned.leadingAttributes.color
        XCTAssertEqual([turnedColor.red, turnedColor.green, turnedColor.blue], [0.953, 0.247, 0.247].map { component in Double(Float(component)) })
        XCTAssertEqual(turned.width, (131 + 20) * 2 * unit, accuracy: Self.accuracy)
        XCTAssertTrue(isOneLine(turned))

        let sticky = boxes[2]
        XCTAssertEqual(sticky.width, 256 * unit, accuracy: Self.accuracy)
        XCTAssertEqual(sticky.height, 256 * unit, accuracy: Self.accuracy)
        XCTAssertNotNil(sticky.style.fillColor, "The sticky note keeps its paper colour.")

        let older = boxes[3]
        XCTAssertEqual(older.leadingAttributes.fontSize, 12 * unit, accuracy: Self.accuracy, "The iPad's RTF sizes read as written.")
        XCTAssertEqual(older.leadingAttributes.color, PDFTextColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(older.origin.x, 100 * unit, accuracy: Self.accuracy)
        XCTAssertEqual(older.width, 150 * unit, accuracy: Self.accuracy)

        let report = try XCTUnwrap(summary.outcomes.first { outcome in outcome.sourceName == SyntheticNotebookNames.textBoxes }?.importedNotebook?.report)
        XCTAssertEqual(report.pages.first?.written?.textBoxCount, 4)
        XCTAssertEqual(report.summary.map(\.kind), [.stickyNotesAsTextBoxes])
    }

    /// Notability's body text flowing from the top of the first page onto a page of its own, in whole lines, its heading
    /// bold and red, laid out as wide as on a Mac (the note stores no width), which the report says.
    private func assertNotabilityTypedNote(in vault: URL, summary: NotebookImportSummary) throws {
        let note = try document("Courses/Synthetic typed note.pdf", in: vault)
        XCTAssertEqual(note.pageCount, 2, "The text needs a second page, which the note itself does not have.")
        var pageTexts: [String] = []
        for pageIndex in 0..<note.pageCount {
            let page = try XCTUnwrap(note.page(at: pageIndex))
            XCTAssertEqual(page.bounds(for: .cropBox).height, 803.25, accuracy: Self.accuracy)
            let boxes = PDFPageManager.textBoxes(on: page)
            XCTAssertEqual(boxes.count, 1, "page \(pageIndex + 1)")
            let box = try XCTUnwrap(boxes.first)
            XCTAssertEqual(box.origin.x, NotabilityPageGeometry.leftInsetPoints, accuracy: Self.accuracy)
            XCTAssertEqual(box.origin.y, 803.25, accuracy: Self.accuracy, "Each page's text starts at its top.")
            XCTAssertLessThanOrEqual(box.height, 803.25 + Self.accuracy, "Only whole lines that fit.")
            pageTexts.append(box.plainText)
        }
        let firstBox = try XCTUnwrap(note.page(at: 0).flatMap { page in PDFPageManager.textBoxes(on: page).first })
        XCTAssertTrue(firstBox.plainText.hasPrefix("Synthetic typed note\nUnderlined line\nLine 1 of"), firstBox.plainText)
        XCTAssertTrue(firstBox.leadingAttributes.isBold)
        XCTAssertEqual(firstBox.leadingAttributes.fontSize, 20 * 612 / 572, accuracy: Self.accuracy)
        XCTAssertTrue(firstBox.runs.contains { run in run.attributes.isUnderlined && run.text.hasPrefix("Underlined line") })
        XCTAssertTrue(pageTexts.last?.hasSuffix("Line 70 of the synthetic typed note.") ?? false, "Nothing lost, and no empty lines after.")
        XCTAssertEqual(pageTexts.joined(separator: "\n").components(separatedBy: "\n").count, 72, "The heading, the underlined line and 70 lines.")
        XCTAssertEqual(try pencilKitDrawing(on: try XCTUnwrap(note.page(at: 0)), context: "typed note").drawing.strokes.count, 1)
        let report = try XCTUnwrap(summary.outcomes.first { outcome in outcome.sourceName == SyntheticNotebookNames.typedNote }?.importedNotebook?.report)
        XCTAssertEqual(report.summary.map(\.kind), [.pageWidthAssumed])
        XCTAssertEqual(report.pages.compactMap(\.written).map(\.textBoxCount), [1, 1])
    }

    /// Whether the box's text takes no more height than the same text in a box too wide to break any line.
    private func isOneLine(_ box: PDFTextBox) -> Bool {
        var unbroken = box
        unbroken.width = 10_000
        return abs(PDFTextBoxLayout(box: box).fittedHeight - PDFTextBoxLayout(box: unbroken).fittedHeight) < Self.accuracy
    }

    // MARK: Pictures of the pages

    /// Draws every page of every imported PDF into `GRAPHITE_IMPORT_RENDERS`, when it is set.
    private func renderPages(of summary: NotebookImportSummary, in vault: URL) throws {
        guard let folderPath = ProcessInfo.processInfo.environment[Self.rendersFolderVariable] else { return }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        for outcome in summary.outcomes {
            guard let pdf = outcome.importedNotebook?.pdf else { continue }
            let document = try document(pdf.rawValue, in: vault)
            try PDFPagePictures.write(document, named: pdf.stem, into: folder)
        }
    }
}

/// The names of the synthetic notebooks with typed text (`SyntheticTextNotebooks` in the NotebookImport package's tests).
enum SyntheticNotebookNames {
    static let textBoxes = "Synthetic text boxes.goodnotes"
    static let typedNote = "Synthetic typed note.note"
}
