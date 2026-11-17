/**
 * File: PDFPageListDropTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: A PDF dropped onto the page list of a PDF's sidebar: where its pages go and where the line is drawn,
 *              which dragged items may carry a PDF, reading them, and inserting their pages as one undo step that a
 *              protected PDF refuses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class PDFPageListDropTests: XCTestCase {
    /// Three rows of a list, 216 points tall with 14 between them, from 8 below the list's top.
    private let rowFrames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 8, width: 210, height: 216),
        1: CGRect(x: 0, y: 238, width: 210, height: 216),
        2: CGRect(x: 0, y: 468, width: 210, height: 216),
    ]

    // MARK: Where the pages go

    func testTheDropGoesBeforeTheFirstRowWhoseMiddleIsBelowThePointer() {
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 0, rowFrames: rowFrames, pageCount: 3), 0, "above the first page")
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 100, rowFrames: rowFrames, pageCount: 3), 0, "on the top half of the first page")
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 200, rowFrames: rowFrames, pageCount: 3), 1, "on its bottom half")
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 231, rowFrames: rowFrames, pageCount: 3), 1, "between the first two")
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 580, rowFrames: rowFrames, pageCount: 3), 3, "on the last page's bottom half")
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 900, rowFrames: rowFrames, pageCount: 3), 3, "in the empty space below the last page")
    }

    func testRowsTheLazyListHasNotLaidOutAreLeftOut() {
        // Scrolled to the end of a 40-page PDF: only the last rows are laid out.
        let laidOut: [Int: CGRect] = [38: CGRect(x: 0, y: 8_748, width: 210, height: 216), 39: CGRect(x: 0, y: 8_978, width: 210, height: 216)]
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 8_800, rowFrames: laidOut, pageCount: 40), 38)
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 9_000, rowFrames: laidOut, pageCount: 40), 39)
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 9_300, rowFrames: laidOut, pageCount: 40), 40)
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 50, rowFrames: [:], pageCount: 40), 40, "no row laid out: after the last page")
    }

    func testARowOfAPageNoLongerThereIsLeftOut() {
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 600, rowFrames: rowFrames, pageCount: 2), 2)
        XCTAssertEqual(PDFPageListInsertion.insertionIndex(atY: 900, rowFrames: rowFrames, pageCount: 2), 2)
    }

    func testAPageDraggedWithinTheListEndsUpWhereTheLineShowed() {
        XCTAssertEqual(PDFPageListInsertion.moveDestination(ofPage: 0, insertedAt: 3), 2, "the first page after the last of three")
        XCTAssertEqual(PDFPageListInsertion.moveDestination(ofPage: 2, insertedAt: 0), 0, "the last page before the first")
        XCTAssertEqual(PDFPageListInsertion.moveDestination(ofPage: 1, insertedAt: 1), 1, "let go just above itself: stays")
        XCTAssertEqual(PDFPageListInsertion.moveDestination(ofPage: 1, insertedAt: 2), 1, "let go just below itself: stays")
    }

    func testTheLineIsHalfwayBetweenTwoRowsOrJustOutsideTheEndOne() throws {
        XCTAssertEqual(try XCTUnwrap(PDFPageListInsertion.lineY(forInsertionIndex: 0, rowFrames: rowFrames)), 4)
        XCTAssertEqual(try XCTUnwrap(PDFPageListInsertion.lineY(forInsertionIndex: 1, rowFrames: rowFrames)), 231)
        XCTAssertEqual(try XCTUnwrap(PDFPageListInsertion.lineY(forInsertionIndex: 2, rowFrames: rowFrames)), 461)
        XCTAssertEqual(try XCTUnwrap(PDFPageListInsertion.lineY(forInsertionIndex: 3, rowFrames: rowFrames)), 688)
        XCTAssertNil(PDFPageListInsertion.lineY(forInsertionIndex: 7, rowFrames: rowFrames))
    }

    // MARK: What the drag carries

    private func vaultItem(named name: String?, transfer: VaultItemTransfer) throws -> NSItemProvider {
        let provider = NSItemProvider()
        let encoded = try JSONEncoder().encode(transfer)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.graphiteVaultItem.identifier, visibility: .all) { completion in
            completion(encoded, nil)
            return nil
        }
        provider.suggestedName = name
        return provider
    }

    /// An item offered as `type`, as Files offers a file it drags.
    private static func provider(of itemData: Data, as type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(for: type, visibility: .all) { completion in
            completion(itemData, nil)
            return nil
        }
        return provider
    }

    private func pdfItem(_ pdfData: Data) -> NSItemProvider {
        Self.provider(of: pdfData, as: .pdf)
    }

    func testOnlyAnItemThatMayBeAPDFIsTaken() throws {
        let transfer = VaultItemTransfer(path: "Handout.pdf")
        func mayBePDF(_ provider: NSItemProvider) -> Bool { PDFPageListDropReader.mayBePDF(provider, draggedFileAddresses: []) }
        XCTAssertTrue(mayBePDF(try vaultItem(named: "Handout.pdf", transfer: transfer)), "a PDF of the vault, by its name")
        XCTAssertFalse(mayBePDF(try vaultItem(named: "Diagram.png", transfer: transfer)), "a picture of the vault")
        XCTAssertTrue(mayBePDF(try vaultItem(named: nil, transfer: transfer)), "a vault item naming no file is read first")
        XCTAssertTrue(mayBePDF(pdfItem(try Self.pdfData(pageWidths: [300]))), "a PDF from Files")
        XCTAssertFalse(mayBePDF(NSItemProvider(object: "Some text" as NSString)))
        XCTAssertFalse(PDFPageListDropReader.mayCarryPDF([], draggedFileAddresses: []))
    }

    func testAPageOfTheListIsReadBack() async throws {
        let page = PDFPageDragItem(sessionIdentifier: UUID(), pageIndex: 4)
        let provider = Self.provider(of: try JSONEncoder().encode(page), as: .graphitePDFPage)
        XCTAssertTrue(PDFPageListDropReader.carriesPage([provider]))
        XCTAssertFalse(PDFPageListDropReader.carriesPage([pdfItem(try Self.pdfData(pageWidths: [300]))]))
        let draggedPage = await PDFPageListDropReader.draggedPage([provider])
        let readBack = try XCTUnwrap(draggedPage)
        XCTAssertEqual(readBack.sessionIdentifier, page.sessionIdentifier)
        XCTAssertEqual(readBack.pageIndex, 4)
    }

    func testAFinderFileIsTakenOnlyWhenTheDragsAddressesNameAPDF() throws {
        let finderFile = NSItemProvider(object: URL(fileURLWithPath: "/Users/someone/Handout.pdf") as NSURL)
        let picture = URL(fileURLWithPath: "/Users/someone/Diagram.png")
        let handout = URL(fileURLWithPath: "/Users/someone/Handout.pdf")
        XCTAssertFalse(PDFPageListDropReader.mayBePDF(finderFile, draggedFileAddresses: [picture]), "the Finder drags a picture")
        XCTAssertTrue(PDFPageListDropReader.mayBePDF(finderFile, draggedFileAddresses: [picture, handout]), "a picture and a PDF")
        XCTAssertTrue(PDFPageListDropReader.mayBePDF(finderFile, draggedFileAddresses: []), "no address to go by: read first")
    }

    func testItemsAreReadInTheDropsOrder() async throws {
        let vault = try TemporaryVault.make(prefix: "PDFPageListDropRead", for: self).root
        let vaultPDF = try Self.pdfData(pageWidths: [310, 320])
        try vaultPDF.write(to: vault.appendingPathComponent("Handout.pdf"))
        try Data([0x89, 0x50]).write(to: vault.appendingPathComponent("Diagram.png"))
        let filesPDF = try Self.pdfData(pageWidths: [330])
        let items = await PDFPageListDropReader.read([
            pdfItem(filesPDF),
            try vaultItem(named: "Handout.pdf", transfer: VaultItemTransfer(path: "Handout.pdf", vaultRoot: vault)),
            try vaultItem(named: "Diagram.png", transfer: VaultItemTransfer(path: "Diagram.png", vaultRoot: vault)),
            try vaultItem(named: "Gone.pdf", transfer: VaultItemTransfer(path: "Gone.pdf", vaultRoot: vault)),
        ])
        XCTAssertEqual(items, [.pdf(filesPDF), .pdf(vaultPDF), .notPDF, .unreadable])
    }

    // MARK: Inserting the pages

    /// A PDF whose pages are as wide as `pageWidths`, so a test tells them apart by their width.
    static func pdfData(pageWidths: [CGFloat], auxiliaryInfo: CFDictionary? = nil) throws -> Data {
        let pdfData = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: pdfData as CFMutableData))
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, auxiliaryInfo))
        for width in pageWidths {
            let pageBox = CGRect(x: 0, y: 0, width: width, height: 400)
            let pageInfo = [kCGPDFContextMediaBox: NSData(bytes: [pageBox], length: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.endPDFPage()
        }
        context.closePDF()
        return pdfData as Data
    }

    private func openSession(pageWidths: [CGFloat], auxiliaryInfo: CFDictionary? = nil) async throws -> PDFSession {
        let location = try TemporaryVault.make(prefix: "PDFPageListDropSession", for: self).root.appendingPathComponent("Annotated handout.pdf")
        try Self.pdfData(pageWidths: pageWidths, auxiliaryInfo: auxiliaryInfo).write(to: location)
        return try await PDFSession.open(location)
    }

    private func pageWidths(of session: PDFSession) -> [CGFloat] {
        (0..<session.document.pageCount).compactMap { pageIndex in session.document.page(at: pageIndex)?.bounds(for: .mediaBox).width }
    }

    func testADroppedPDFsPagesGoWhereItWasLetGoAsOneUndoStep() async throws {
        let session = try await openSession(pageWidths: [100, 101, 102])
        try session.insertDroppedPDFs([try Self.pdfData(pageWidths: [200, 201])], at: 1)
        XCTAssertEqual(pageWidths(of: session), [100, 200, 201, 101, 102])
        XCTAssertEqual(session.pageCount, 5)
        XCTAssertEqual(session.currentPageIndex, 1, "the first inserted page is shown")
        XCTAssertEqual(session.undoManager.undoActionName, "Insert PDF")
        session.undoManager.undo()
        XCTAssertEqual(pageWidths(of: session), [100, 101, 102], "one Undo takes every inserted page out")
        XCTAssertFalse(session.undoManager.canUndo)
        session.undoManager.redo()
        XCTAssertEqual(pageWidths(of: session), [100, 200, 201, 101, 102])
    }

    func testPDFsGoBeforeTheFirstPageAndAfterTheLast() async throws {
        let session = try await openSession(pageWidths: [100, 101])
        try session.insertDroppedPDFs([try Self.pdfData(pageWidths: [200])], at: 0)
        XCTAssertEqual(pageWidths(of: session), [200, 100, 101])
        try session.insertDroppedPDFs([try Self.pdfData(pageWidths: [300])], at: session.pageCount)
        XCTAssertEqual(pageWidths(of: session), [200, 100, 101, 300])
    }

    func testSeveralDroppedPDFsAreOneStepInTheDropsOrder() async throws {
        let session = try await openSession(pageWidths: [100, 101])
        try session.insertDroppedPDFs([try Self.pdfData(pageWidths: [200, 201]), try Self.pdfData(pageWidths: [300])], at: 1)
        XCTAssertEqual(pageWidths(of: session), [100, 200, 201, 300, 101])
        XCTAssertEqual(session.undoManager.undoActionName, "Insert PDFs")
        session.undoManager.undo()
        XCTAssertEqual(pageWidths(of: session), [100, 101])
        XCTAssertFalse(session.undoManager.canUndo)
    }

    func testAPasswordProtectedOrUnreadableDroppedPDFInsertsNothing() async throws {
        let session = try await openSession(pageWidths: [100, 101])
        let lockedInfo = [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: "user"] as CFDictionary
        XCTAssertThrowsError(try session.insertDroppedPDFs([try Self.pdfData(pageWidths: [200], auxiliaryInfo: lockedInfo)], at: 1))
        XCTAssertThrowsError(try session.insertDroppedPDFs([Data("not a PDF".utf8)], at: 1))
        XCTAssertEqual(pageWidths(of: session), [100, 101])
        XCTAssertFalse(session.undoManager.canUndo)
    }

    func testAProtectedPDFTakesNoPages() async throws {
        let session = try await openSession(pageWidths: [100, 101], auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""] as CFDictionary)
        XCTAssertTrue(session.isProtected)
        XCTAssertThrowsError(try session.insertDroppedPDFs([try Self.pdfData(pageWidths: [200])], at: 1))
        XCTAssertEqual(session.document.pageCount, 2)
    }
}
