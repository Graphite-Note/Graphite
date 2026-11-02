/**
 * File: OversizedNoteTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: A note over the editing limit opens read-only, a page at a time, is never written, and can be loaded
 *              with Edit Anyway; external changes keep working (HUNT-102).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class OversizedNoteTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!
    private static let nineMegabytes = 9 * 1_048_576

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    // MARK: Opening

    func testANoteOverTheLimitOpensReadOnlyWithANotice() async throws {
        let (workspace, _) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        let path = try VaultPath("Big.md")
        await workspace.open(path)

        let document = workspace.activeDocument
        let note = try XCTUnwrap(document.oversizedNote)
        XCTAssertNil(document.markdownSession, "No editor, and none of what it costs.")
        XCTAssertNil(document.loadFailure)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(document.loadedPath, path)
        XCTAssertEqual(workspace.layout.activeTab.path, path)
        XCTAssertEqual(note.byteCount, Self.nineMegabytes)
        XCTAssertTrue(note.notice.contains("too large to edit"), note.notice)
        XCTAssertTrue(note.notice.contains("8 MB"), note.notice)
        XCTAssertTrue(note.canEditAnyway)
        XCTAssertEqual(note.pagesRead, 0, "Nothing of the file is read until a page shows.")
    }

    func testANoteAtTheLimitStillOpensInTheEditor() async throws {
        let (workspace, _) = try await makeWorkspace(largeNotes: ["Big.md": MarkdownSession.maximumEditableBytes], files: [:])
        await workspace.open(try VaultPath("Big.md"))
        XCTAssertNotNil(workspace.markdownSession)
        XCTAssertNil(workspace.activeDocument.oversizedNote)
    }

    func testReadOnlyNeverWritesToTheFile() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        let location = vault.appendingPathComponent("Big.md")
        let bytesBefore = try Data(contentsOf: location)
        let dateBefore = try location.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let path = try VaultPath("Big.md")
        let tabID = try await openTab(path, in: workspace)
        let note = try XCTUnwrap(workspace.activeDocument.oversizedNote)
        _ = try await note.text(ofPage: 0)

        try await workspace.saveOpenDocuments()
        let didSave = await workspace.saveBeforeClosing([tabID])
        XCTAssertTrue(didSave)
        XCTAssertFalse(workspace.activeDocument.hasUnsavedChanges)
        await workspace.checkOpenDocumentsForExternalChanges()
        await workspace.closeTab(tabID)

        XCTAssertEqual(try Data(contentsOf: location), bytesBefore)
        XCTAssertEqual(try location.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, dateBefore)
    }

    // MARK: Pages

    /// Every page together is the file, byte for byte, whatever falls on a page's edge: lines
    /// short and long, characters of two, three and four bytes, and line endings of both kinds.
    func testThePagesTogetherAreTheWholeFile() async throws {
        var text = ""
        for lineNumber in 0..<20_000 { text += "Line \(lineNumber) é€𝄞 of the note\(lineNumber % 2 == 0 ? "\n" : "\r\n")" }
        text += String(repeating: "é€𝄞", count: 90_000) + "\n"
        text += String(repeating: "x", count: 100_000)
        let store = VaultStore(root: try makeVault(files: ["Long.md": text]))
        let note = try await OversizedNoteDocument.open(try VaultPath("Long.md"), in: store)
        XCTAssertGreaterThan(note.pageCount, 30)

        var pages = ""
        for pageIndex in 0..<note.pageCount { pages += try await note.text(ofPage: pageIndex) }

        XCTAssertEqual(pages, text)
    }

    func testAPageIsNoLargerThanWhatIsReadForIt() async throws {
        let store = VaultStore(root: try makeVault(files: ["Long.md": String(repeating: "x", count: 500_000)]))
        let note = try await OversizedNoteDocument.open(try VaultPath("Long.md"), in: store)
        let page = try await note.text(ofPage: 3)
        XCTAssertLessThanOrEqual(page.utf8.count, OversizedNotePaging.bytesReadPerPage)
        XCTAssertEqual(note.pagesRead, 1)
    }

    /// 200 MB, on disk as a sparse file: it opens read-only with nothing read but its size, a
    /// page costs what a page of any note costs, and Edit Anyway is not offered.
    func testAFileOf200MegabytesOpensAndReadsAPageAtATime() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: [:], files: ["Huge.md": "start", "Other.md": ""])
        let byteCount = 200 * 1_048_576
        let handle = try FileHandle(forWritingTo: vault.appendingPathComponent("Huge.md"))
        try handle.truncate(atOffset: UInt64(byteCount))
        try handle.close()
        let path = try VaultPath("Huge.md")
        let tabID = try await openTab(path, in: workspace)

        let note = try XCTUnwrap(workspace.activeDocument.oversizedNote)
        XCTAssertEqual(note.byteCount, byteCount)
        XCTAssertFalse(note.canEditAnyway)
        XCTAssertTrue(note.notice.contains("200 MB"), note.notice)
        let lastPage = try await note.text(ofPage: note.pageCount - 1)
        XCTAssertLessThanOrEqual(lastPage.utf8.count, OversizedNotePaging.bytesReadPerPage)
        let firstPage = try await note.text(ofPage: 0)
        XCTAssertTrue(firstPage.hasPrefix("start"))

        await workspace.editOversizedNoteAnyway(inTab: tabID)
        XCTAssertNil(workspace.markdownSession, "A file this large stays read-only.")
        XCTAssertNotNil(workspace.activeDocument.oversizedNote)
    }

    // MARK: Edit Anyway

    func testEditAnywayLoadsTheNoteWithTheWarningAndItCanBeTrimmed() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        let path = try VaultPath("Big.md")
        let tabID = try await openTab(path, in: workspace)

        await workspace.editOversizedNoteAnyway(inTab: tabID)

        let session = try XCTUnwrap(workspace.markdownSession)
        XCTAssertNil(workspace.activeDocument.oversizedNote)
        XCTAssertEqual(session.text.utf8.count, Self.nineMegabytes)
        XCTAssertEqual(session.errorMessage, MarkdownSession.grownTooLargeMessage)
        XCTAssertFalse(session.hasUnsavedChanges, "Loading it changes nothing.")
        await session.checkExternalChange()
        XCTAssertEqual(session.errorMessage, MarkdownSession.grownTooLargeMessage, "Its own size is not reported as a problem.")
        XCTAssertEqual(session.text.utf8.count, Self.nineMegabytes)

        session.text = "trimmed"
        try await session.save()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Big.md"), encoding: .utf8), "trimmed")

        await workspace.closeTab(tabID)
        await workspace.open(path)
        XCTAssertEqual(workspace.markdownSession?.text, "trimmed", "Smaller now, it opens in the editor.")
    }

    func testANoteStillOverTheLimitOpensReadOnlyAgainAfterEditAnyway() async throws {
        let (workspace, _) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        let path = try VaultPath("Big.md")
        let tabID = try await openTab(path, in: workspace)
        await workspace.editOversizedNoteAnyway(inTab: tabID)
        XCTAssertNotNil(workspace.markdownSession)
        await workspace.closeTab(tabID)
        await workspace.open(path)
        XCTAssertNil(workspace.markdownSession)
        XCTAssertNotNil(workspace.activeDocument.oversizedNote)
    }

    /// A draft waits for the editor: read-only cannot show it, and says it is there.
    func testUnsavedTextOfAnOversizedNoteIsSaidToBeKept() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        let path = try VaultPath("Big.md")
        let bytes = try Data(contentsOf: vault.appendingPathComponent("Big.md"))
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let draft = UnsavedDocumentDraft(path: path, contents: bytes + Data(" typed".utf8), baseRevision: FileRevision.of(bytes), date: .now)
        let isKept = await processServices.unsavedDrafts.keep(draft, inVault: vaultIdentifier)
        XCTAssertTrue(isKept)

        let tabID = try await openTab(path, in: workspace)

        XCTAssertNotNil(workspace.activeDocument.oversizedNote)
        XCTAssertTrue(workspace.errorMessage?.contains("Edit Anyway") == true, workspace.errorMessage ?? "")
        await workspace.editOversizedNoteAnyway(inTab: tabID)
        XCTAssertTrue(workspace.markdownSession?.text.hasSuffix(" typed") == true, "The draft comes back in the editor.")
    }

    // MARK: External changes

    func testAFileThatShrinksIsEditedNormally() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        await workspace.open(try VaultPath("Big.md"))
        XCTAssertNotNil(workspace.activeDocument.oversizedNote)

        try Data("small now".utf8).write(to: vault.appendingPathComponent("Big.md"))
        await workspace.checkOpenDocumentsForExternalChanges()

        XCTAssertNil(workspace.activeDocument.oversizedNote)
        XCTAssertEqual(workspace.markdownSession?.text, "small now")
        XCTAssertNil(workspace.errorMessage)
    }

    func testAFileThatChangesButStaysLargeShowsTheNewVersion() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        await workspace.open(try VaultPath("Big.md"))
        let firstVersion = try XCTUnwrap(workspace.activeDocument.oversizedNote)

        try Data(repeating: UInt8(ascii: "y"), count: Self.nineMegabytes + 10).write(to: vault.appendingPathComponent("Big.md"))
        await workspace.checkOpenDocumentsForExternalChanges()

        let secondVersion = try XCTUnwrap(workspace.activeDocument.oversizedNote)
        XCTAssertFalse(firstVersion === secondVersion)
        XCTAssertEqual(secondVersion.byteCount, Self.nineMegabytes + 10)
        let firstPage = try await secondVersion.text(ofPage: 0)
        XCTAssertTrue(firstPage.hasPrefix("yyy"))
        let unchanged = secondVersion
        await workspace.checkOpenDocumentsForExternalChanges()
        XCTAssertTrue(workspace.activeDocument.oversizedNote === unchanged, "An unchanged file is not read again.")
    }

    func testAFileThatGoesAwaySaysSoInItsTab() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        let path = try VaultPath("Big.md")
        await workspace.open(path)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Big.md"))

        await workspace.checkOpenDocumentsForExternalChanges()

        XCTAssertNil(workspace.activeDocument.oversizedNote)
        XCTAssertEqual(workspace.activeDocument.loadFailure?.path, path)
    }

    /// An open note another app grew past the limit used to show the memory message at every
    /// check, over text that was now an old version. With nothing unsaved it opens read-only.
    func testANoteGrownElsewhereWithNothingUnsavedOpensReadOnly() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: [:], files: ["Note.md": "small", "Other.md": ""])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)

        try Data(repeating: UInt8(ascii: "y"), count: Self.nineMegabytes).write(to: vault.appendingPathComponent("Note.md"))
        await workspace.checkOpenDocumentsForExternalChanges()

        XCTAssertNil(workspace.markdownSession)
        XCTAssertNotNil(workspace.activeDocument.oversizedNote)
        XCTAssertNil(session.errorMessage)
        XCTAssertNil(workspace.errorMessage)
    }

    /// With text not saved, it is the conflict any other app's change is: the text stays, in a
    /// draft too, and the file is not touched.
    func testANoteGrownElsewhereUnderUnsavedTextIsAConflict() async throws {
        let (workspace, vault) = try await makeWorkspace(largeNotes: [:], files: ["Note.md": "small", "Other.md": ""])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.text = "typed"
        let grown = Data(repeating: UInt8(ascii: "y"), count: Self.nineMegabytes)
        try grown.write(to: vault.appendingPathComponent("Note.md"))

        await workspace.checkOpenDocumentsForExternalChanges()

        XCTAssertTrue(workspace.markdownSession === session)
        XCTAssertTrue(session.hasExternalConflict)
        XCTAssertEqual(session.text, "typed")
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts.map(\.contents), [Data("typed".utf8)])
        do {
            try await session.save()
            XCTFail("The newer file is not overwritten.")
        } catch { XCTAssertEqual(error as? GraphiteError, .conflict) }
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Note.md")), grown)
    }

    /// A note this session itself took past the limit is not another app's change.
    func testANoteGrownHereIsNotReportedAtEveryCheck() async throws {
        let (workspace, _) = try await makeWorkspace(largeNotes: [:], files: ["Note.md": "small", "Other.md": ""])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.text = String(repeating: "x", count: Self.nineMegabytes)
        try await session.save()

        await workspace.checkOpenDocumentsForExternalChanges()

        XCTAssertTrue(workspace.markdownSession === session, "It stays open in the editor it grew in.")
        XCTAssertEqual(session.errorMessage, MarkdownSession.grownTooLargeMessage)
        XCTAssertFalse(session.hasExternalConflict)
    }

    // MARK: What else reads notes

    func testALinkPreviewOfAnOversizedNoteShowsNoCard() async throws {
        let (workspace, _) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Source.md": "[[Big]]"])
        let reading = try XCTUnwrap(workspace.linkPreviewReading(at: .large))
        let request = LinkPreviewRequest(target: "Big", isWiki: true, sourceNote: try VaultPath("Source.md"), anchor: .zero, trigger: .press, source: .reading)
        let content = await reading.content(for: request)
        XCTAssertNil(content)
    }

    // MARK: The view

    #if os(macOS)
    /// In a real window: the note's first pages are read, and only those.
    func testTheViewReadsOnlyThePagesItShows() async throws {
        let (workspace, _) = try await makeWorkspace(largeNotes: ["Big.md": Self.nineMegabytes], files: ["Other.md": ""])
        await workspace.open(try VaultPath("Big.md"))
        let note = try XCTUnwrap(workspace.activeDocument.oversizedNote)
        var askedToEdit = false
        let hostingView = NSHostingView(rootView: OversizedNotePane(note: note) { askedToEdit = true })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = hostingView
        window.showInvisibly()
        defer { window.orderOut(nil); window.contentView = nil }

        try await waitUntil("the first pages to be read") { note.pagesRead > 0 }

        XCTAssertLessThan(note.pagesRead, note.pageCount / 4, "Read \(note.pagesRead) of \(note.pageCount) pages.")
        XCTAssertFalse(askedToEdit)
    }
    #endif

    // MARK: Helpers

    private func openTab(_ path: VaultPath, in workspace: WorkspaceModel) async throws -> UUID {
        let tabID = await workspace.open(path)
        return try XCTUnwrap(tabID)
    }

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "OversizedNoteVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files { try Data(contents.utf8).write(to: vault.appendingPathComponent(relativePath)) }
        return vault
    }

    /// `largeNotes` are written as that many bytes of lines of text.
    private func makeWorkspace(largeNotes: [String: Int], files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try makeVault(files: files)
        for (relativePath, byteCount) in largeNotes {
            let line = Data("A line of the note, grown by a paste.\n".utf8)
            var bytes = Data(capacity: byteCount + line.count)
            while bytes.count < byteCount { bytes.append(line) }
            try bytes.prefix(byteCount).write(to: vault.appendingPathComponent(relativePath))
        }
        let workspace = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        return (workspace, vault)
    }
}
