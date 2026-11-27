/**
 * File: SectionLinksOnPDFTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Sections of notes placed on PDF pages through the workspace: the picture drawn from the note, a section
 *              dropped where it landed with the link the file keeps, the picture drawn again when the note changes,
 *              the block a drag names given its identifier, a reading view's heading handed over while the main thread
 *              waits, and the link opening the section beside the PDF.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 27/11/2026
 */

#if os(macOS)
import XCTest
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

@MainActor
final class SectionLinksOnPDFTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()
    private static let note = "# Lecture 1\n\n## Entropy\n\nEntropy counts the microstates of a system.\n\n## Second law\n\n- It never decreases.\n"

    override func tearDown() async throws {
        testBed.tearDown()
    }

    /// A vault with the lecture note and a blank one-page PDF beside it.
    private func workspaceWithNoteAndPDF() async throws -> (workspace: WorkspaceModel, vault: URL, session: PDFSession) {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Lecture 1.md": Self.note, "Archive/Contents.md": "# Archive\n"])
        let pageData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: pageData)), mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        try (pageData as Data).write(to: vault.appendingPathComponent("Slides.pdf"))
        let tabID = try await testBed.open("Slides.pdf", in: workspace)
        return (workspace, vault, try XCTUnwrap(workspace.document(for: tabID).pdfSession))
    }

    private func actions(of workspace: WorkspaceModel, opened: @escaping @MainActor (SectionLink) -> Void = { _ in }) -> PDFSectionLinkActions {
        PDFSectionLinkActions(vaultRoot: workspace.folderAccess?.root,
                              prepare: { link in try await workspace.preparedSectionPicture(for: link) },
                              currentDigest: { link in await workspace.currentSectionTextDigest(for: link) },
                              open: opened, openAddress: { url in SectionLink(openingURL: url).map(opened) })
    }

    private func dropLocation(in session: PDFSession) throws -> PDFDropLocation {
        let page = try XCTUnwrap(session.document.page(at: 0))
        let cropBox = page.bounds(for: .cropBox)
        let shownPage = PDFShownPage(cropBox: cropBox, rotationDegrees: 0, frameInView: cropBox, viewIsFlipped: false)
        return PDFDropLocation(pageIndex: 0, shownPage: shownPage, pagePoint: CGPoint(x: cropBox.midX, y: cropBox.midY))
    }

    func testASectionIsDrawnAsThePageShowsItAndItsDigestFollowsTheNote() async throws {
        let (workspace, _, _) = try await workspaceWithNoteAndPDF()
        let link = SectionLink(note: "Lecture 1", subpath: "Entropy")
        let prepared = try await workspace.preparedSectionPicture(for: link)
        let size = try XCTUnwrap(PictureNaturalSize.measure(ofImageData: prepared.imageData)?.shownPixelSize)
        XCTAssertEqual(prepared.widthInPoints, 420, accuracy: 1, "An A5 page's width: \(size)")
        XCTAssertLessThan(size.height, size.width, "Cut below the section's last line, not a whole page: \(size)")
        XCTAssertTrue(prepared.address.hasPrefix("obsidian://open?vault="))
        XCTAssertTrue(prepared.address.hasSuffix("&file=Lecture%201%23Entropy"), prepared.address)
        XCTAssertEqual(prepared.textDigest, SectionLink.textDigest(of: "## Entropy\n\nEntropy counts the microstates of a system.\n"))

        // A picture for a person to look at, when `GRAPHITE_SNAPSHOT_DIRECTORY` names a folder.
        if let directory = ProcessInfo.processInfo.environment["GRAPHITE_SNAPSHOT_DIRECTORY"] {
            try prepared.imageData.write(to: URL(fileURLWithPath: directory).appendingPathComponent("section-link-entropy.png"))
        }
        let missing = try await workspace.preparedSectionPicture(for: SectionLink(note: "Lecture 1", subpath: "Third law"))
        XCTAssertEqual(missing.textDigest, "missing", "A section the note lacks is drawn as Obsidian's message for it.")
        let missingSize = try XCTUnwrap(PictureNaturalSize.measure(ofImageData: missing.imageData)?.shownPixelSize)
        XCTAssertGreaterThan(missingSize.height, 0)
        if let directory = ProcessInfo.processInfo.environment["GRAPHITE_SNAPSHOT_DIRECTORY"] {
            try missing.imageData.write(to: URL(fileURLWithPath: directory).appendingPathComponent("section-link-missing.png"))
        }
    }

    func testADroppedSectionIsPlacedWhereItLandedAndTheFileLinksToIt() async throws {
        let (workspace, vault, session) = try await workspaceWithNoteAndPDF()
        let placed = await session.placeDroppedSectionLink(SectionLink(note: "Lecture 1", subpath: "Entropy"), actions: actions(of: workspace),
                                                           at: try dropLocation(in: session))
        XCTAssertTrue(placed)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let picture = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertNotNil(picture.sectionLinkAddress)
        XCTAssertEqual(picture.bounds.midX, 297.5, accuracy: 1, "Its middle where it was dropped.")
        XCTAssertEqual(session.undoManager.undoActionName, "Add Section Link")
        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: vault.appendingPathComponent("Slides.pdf"))?.page(at: 0))
        XCTAssertEqual(saved.annotations.filter { annotation in annotation.type == "Link" }.compactMap(\.url).map(\.absoluteString),
                       [try XCTUnwrap(picture.sectionLinkAddress)], "The saved file has a link over the picture.")
    }

    func testTheSectionIsDrawnAgainWhenTheNoteChangesAndNotOtherwise() async throws {
        let (workspace, vault, session) = try await workspaceWithNoteAndPDF()
        let sectionActions = actions(of: workspace)
        _ = await session.placeDroppedSectionLink(SectionLink(note: "Lecture 1", subpath: "Entropy"), actions: sectionActions, at: try dropLocation(in: session))
        let page = try XCTUnwrap(session.document.page(at: 0))
        let before = try XCTUnwrap(session.pictures(on: page).first)
        let unchanged = await session.refreshSectionPictures(onPages: [0], actions: sectionActions)
        XCTAssertEqual(unchanged, 0, "An unchanged section is not drawn again.")

        try (Self.note.replacingOccurrences(of: "of a system.", with: "of a system, and much more: a second sentence that makes the section taller.\n\nAnd a second paragraph."))
            .write(to: vault.appendingPathComponent("Lecture 1.md"), atomically: true, encoding: .utf8)
        let refreshed = await session.refreshSectionPictures(onPages: [0], actions: sectionActions)
        XCTAssertEqual(refreshed, 1)
        let after = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertEqual(after.name, before.name)
        XCTAssertNotEqual(after.sectionTextDigest, before.sectionTextDigest)
        XCTAssertEqual(after.bounds.width, before.bounds.width, accuracy: 0.01, "The width is kept.")
        XCTAssertEqual(after.bounds.maxY, before.bounds.maxY, accuracy: 0.01, "The top edge is kept.")
        XCTAssertGreaterThan(after.bounds.height, before.bounds.height, "The taller section's picture is taller.")
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Link" }.map(\.bounds), [after.annotationBounds],
                       "The link follows the picture.")
    }

    func testRenamingANoteRelinksAClosedPDFThatShowsItsSection() async throws {
        let (workspace, vault, session) = try await workspaceWithNoteAndPDF()
        _ = await session.placeDroppedSectionLink(SectionLink(note: "Lecture 1", subpath: "Entropy"), actions: actions(of: workspace),
                                                  at: try dropLocation(in: session))
        try await session.save()
        let pdfPath = try VaultPath("Slides.pdf")
        let tabID = try XCTUnwrap(workspace.layout.tabID(showing: pdfPath))
        await workspace.closeTab(tabID)
        await workspace.refreshIndexAndRecordChange(for: [pdfPath])
        let index = try XCTUnwrap(workspace.index)
        let backlinks = try await index.linkingNotes(to: try VaultPath("Lecture 1.md"))
        XCTAssertEqual(backlinks, [pdfPath], "The index knows the PDF links to the note.")

        workspace.vaultSettings.updatesLinksAutomatically = true
        await workspace.rename(try VaultPath("Lecture 1.md"), to: "Thermodynamics")
        XCTAssertNil(workspace.errorMessage)
        let saved = try XCTUnwrap(PDFDocument(url: vault.appendingPathComponent("Slides.pdf"))?.page(at: 0))
        let address = try XCTUnwrap(PDFPageManager.pictures(on: saved).first?.sectionLinkAddress)
        XCTAssertTrue(address.hasSuffix("&file=Thermodynamics%23Entropy"), address)
        XCTAssertEqual(saved.annotations.filter { annotation in annotation.type == "Link" }.compactMap(\.url?.absoluteString), [address])
        let link = try XCTUnwrap(URL(string: address).flatMap(SectionLink.init(openingURL:)))
        let digest = await workspace.currentSectionTextDigest(for: link)
        XCTAssertNotEqual(digest, nil, "The renamed note is found by the new address.")
    }

    func testRenamingANoteRelinksAnOpenPDFInPlace() async throws {
        let (workspace, _, session) = try await workspaceWithNoteAndPDF()
        _ = await session.placeDroppedSectionLink(SectionLink(note: "Lecture 1", subpath: "Entropy"), actions: actions(of: workspace),
                                                  at: try dropLocation(in: session))
        try await session.save()
        let pdfPath = try VaultPath("Slides.pdf")
        await workspace.refreshIndexAndRecordChange(for: [pdfPath])
        workspace.vaultSettings.updatesLinksAutomatically = true
        await workspace.move(try VaultPath("Lecture 1.md"), into: try VaultPath("Archive"))
        let page = try XCTUnwrap(session.document.page(at: 0))
        let address = try XCTUnwrap(session.pictures(on: page).first?.sectionLinkAddress)
        XCTAssertTrue(address.hasSuffix("&file=Archive%2FLecture%201%23Entropy"), address)
        XCTAssertTrue(session.hasUnsavedChanges || session.changeVersion > 0, "The open PDF took the change and saves it as an edit.")
    }

    func testAHeadingDraggedFromTheReadingViewCarriesItsSectionAndALinkAsText() async throws {
        let notePath = try VaultPath("Physics/Lecture 1.md")
        let headingOffset = (Self.note as NSString).range(of: "## Second law").location
        let drags = ReadingSectionDrags(notePath: notePath, noteText: Self.note, vaultRoot: URL(fileURLWithPath: "/Vault"),
                                        blockOffsets: ["heading-2": headingOffset])
        XCTAssertNil(drags.itemProvider(forBlock: "embedded-heading"), "A block that is not the note's own is not dragged.")
        let provider = try XCTUnwrap(drags.itemProvider(forBlock: "heading-2"))
        let transfer = await SectionLinkTransfer.load(from: provider)
        XCTAssertEqual(transfer?.link, SectionLink(note: "Physics/Lecture 1", subpath: "Second law"))
        XCTAssertTrue(transfer?.isInVault(at: URL(fileURLWithPath: "/Vault")) == true)
        let text: String? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in continuation.resume(returning: object as? String) }
        }
        XCTAssertEqual(text, "[[Physics/Lecture 1#Second law]]", "Dropped into a note, it is a link to the section.")
    }

    /// On the Mac, SwiftUI's pasteboard reads a dragged heading's section while the main thread
    /// waits for it, as a PDF page does to decide whether it takes the drag: the section must
    /// come without the main thread, or the app freezes with the drag over the page.
    func testAHeadingDraggedFromTheReadingViewGivesItsSectionWhileTheMainThreadWaits() throws {
        let notePath = try VaultPath("Physics/Lecture 1.md")
        let headingOffset = (Self.note as NSString).range(of: "## Entropy").location
        let drags = ReadingSectionDrags(notePath: notePath, noteText: Self.note, vaultRoot: URL(fileURLWithPath: "/Vault"),
                                        blockOffsets: ["heading-1": headingOffset])
        let provider = try XCTUnwrap(drags.itemProvider(forBlock: "heading-1"))
        let received = ReceivedSectionData()
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.graphiteSectionLink.identifier) { encoded, _ in
            received.store(encoded)
        }
        XCTAssertEqual(received.arrived.wait(timeout: .now() + 5), .success, "The section came while the main thread waited.")
        let transfer = try JSONDecoder().decode(SectionLinkTransfer.self, from: try XCTUnwrap(received.encoded))
        XCTAssertEqual(transfer.link, SectionLink(note: "Physics/Lecture 1", subpath: "Entropy"))
    }

    func testADraggedBlockGetsItsIdentifierOnlyWhenAPageTakesItAndTheCursorStays() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Lecture 1.md": Self.note])
        let tabID = try await testBed.open("Lecture 1.md", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tabID).markdownSession)
        session.selection = NSRange(location: (Self.note as NSString).length, length: 0)
        let location = (Self.note as NSString).range(of: "counts").location
        let (transfer, identifierEdit) = MarkdownEditorSectionDrag.transfer(startingAt: location, in: session)
        let subpath = try XCTUnwrap(transfer.subpath)
        XCTAssertTrue(subpath.hasPrefix("^"))
        XCTAssertEqual(session.text, Self.note, "Dragging alone leaves the note as it was.")

        MarkdownEditorSectionDrag.addIdentifier(identifierEdit, to: session, expectingText: Self.note)
        XCTAssertTrue(session.text.contains("of a system. " + subpath), session.text)
        XCTAssertEqual(session.selection.location, (session.text as NSString).length, "The cursor stays at the end, past the new identifier.")
        XCTAssertTrue(transfer.isInVault(at: workspace.folderAccess?.root))
        let decoded = try JSONDecoder().decode(SectionLinkTransfer.self, from: try JSONEncoder().encode(transfer))
        XCTAssertEqual(decoded, transfer)
    }

    func testALinkClickedOnThePageOpensTheSectionAndOtherAddressesAreLeftToTheSystem() throws {
        var opened: [SectionLink] = []
        let clicks = PDFLinkClicks()
        clicks.sectionLinks = PDFSectionLinkActions(vaultRoot: nil, prepare: { _ in throw CancellationError() }, currentDigest: { _ in nil },
                                                    open: { link in opened.append(link) },
                                                    openAddress: { url in SectionLink(openingURL: url).map { link in opened.append(link) } })
        clicks.pdfViewWillClick(onLink: PDFView(), with: try XCTUnwrap(URL(string: "obsidian://open?vault=Study&file=Lecture%201%23Entropy")))
        XCTAssertEqual(opened, [SectionLink(note: "Lecture 1", subpath: "Entropy")])
    }
}
/// The section a provider handed over, kept for the waiting main thread.
private final class ReceivedSectionData: @unchecked Sendable {
    let arrived = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedData: Data?

    var encoded: Data? { lock.withLock { storedData } }

    func store(_ data: Data?) {
        lock.withLock { storedData = data }
        arrived.signal()
    }
}
#endif
