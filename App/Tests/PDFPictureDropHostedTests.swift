/**
 * File: PDFPictureDropHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Hosted iPad test of pictures dropped onto a PDF view in a window: the view takes drops, an image as
 *              Photos and Safari offer it and an image file of the vault as the sidebar offers it are placed where
 *              they landed, selected, as one step each; a PDF file and a protected PDF take none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class PDFPictureDropHostedTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = try TemporaryVault.make(prefix: "PDFPictureDrop", for: self).root
    }

    private func makePDF(named name: String, auxiliaryInfo: CFDictionary? = nil) throws -> URL {
        let location = directory.appendingPathComponent(name)
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, auxiliaryInfo))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return location
    }

    private func pngData(width: Int = 200, height: Int = 100) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    /// The PDF shown in a window, as a pane shows it, and its view's drop handling.
    private func show(_ session: PDFSession) async throws -> (window: UIWindow, view: GraphitePDFDisplayView, drops: PDFPictureDropInteraction) {
        let input = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        let controller = UIHostingController(rootView: GraphitePDFView(session: session, input: input))
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 1_000)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let view = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        try await waitUntil("the page is laid out") { view.bounds.width > 0 && view.page(for: CGPoint(x: view.bounds.midX, y: view.bounds.midY), nearest: false) != nil }
        let drops = try XCTUnwrap(view.annotationCoordinator?.pictureDrops)
        return (window, view, drops)
    }

    /// An item that offers its bytes as `type`, as Photos, Files and Safari offer a picture.
    private func provider(of fileData: Data, as type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(fileData, nil)
            return nil
        }
        return provider
    }

    private func imageProvider(_ imageData: Data) -> NSItemProvider {
        provider(of: imageData, as: .png)
    }

    func testAnImageDroppedOnAPageIsPlacedWhereItLandedSelectedAsOneStep() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Slides.pdf"))
        let (_, view, drops) = try await show(session)
        XCTAssertTrue(view.interactions.contains { interaction in interaction === drops.interaction }, "The PDF view takes drops.")
        let page = try XCTUnwrap(session.document.page(at: 0))
        let target = CGPoint(x: 130, y: 410)
        let viewPoint = view.convert(target, from: page)

        let provider = imageProvider(try pngData())
        XCTAssertTrue(drops.takesDrop(of: [provider]))
        let placedCount = await drops.placePictures(of: [provider], atViewPoint: viewPoint)

        XCTAssertEqual(placedCount, 1)
        let pictures = session.pictures(on: page)
        XCTAssertEqual(pictures.count, 1)
        let picture = try XCTUnwrap(pictures.first)
        XCTAssertEqual(picture.bounds.midX, target.x, accuracy: 1.5)
        XCTAssertEqual(picture.bounds.midY, target.y, accuracy: 1.5)
        XCTAssertEqual(picture.bounds.width, 100, accuracy: 1, "200 pixels that state no resolution are placed at 100 points.")
        XCTAssertEqual(session.selectedPicture?.pictureName, picture.name)
        XCTAssertEqual(session.undoManager.undoActionName, "Add Image")
        session.undoManager.undo()
        XCTAssertTrue(session.pictures(on: page).isEmpty, "The drop is one step of the history.")
    }

    func testAnImageFileDraggedFromTheSidebarIsPlacedAndAPDFIsRefused() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Worksheet.pdf"))
        let (_, view, drops) = try await show(session)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try pngData(width: 300, height: 300).write(to: directory.appendingPathComponent("Figure.png"))

        let vaultItem = NSItemProvider()
        let transfer = try JSONEncoder().encode(VaultItemTransfer(path: "Figure.png", vaultRoot: directory))
        vaultItem.registerDataRepresentation(forTypeIdentifier: UTType.graphiteVaultItem.identifier, visibility: .ownProcess) { completion in
            completion(transfer, nil)
            return nil
        }
        let placedCount = await drops.placePictures(of: [vaultItem], atViewPoint: view.convert(CGPoint(x: 200, y: 300), from: page))
        XCTAssertEqual(placedCount, 1)
        XCTAssertEqual(session.pictures(on: page).first?.bounds.width ?? 0, 150, accuracy: 1)

        let pdfFile = provider(of: try Data(contentsOf: try makePDF(named: "Other.pdf")), as: .pdf)
        XCTAssertEqual(PDFPictureDropReader.kind(of: pdfFile), .pdfDocument)
        XCTAssertFalse(drops.takesDrop(of: [pdfFile]))
        let refusedCount = await drops.placePictures(of: [pdfFile], atViewPoint: view.convert(CGPoint(x: 200, y: 300), from: page))
        XCTAssertEqual(refusedCount, 0)
        XCTAssertEqual(session.pictures(on: page).count, 1)
    }

    func testAPasswordProtectedPDFTakesNoDrop() async throws {
        let location = try makePDF(named: "Encrypted.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""] as CFDictionary)
        let session = try await PDFSession.open(location)
        XCTAssertTrue(session.isProtected)
        let (_, view, drops) = try await show(session)
        let provider = imageProvider(try pngData())
        XCTAssertFalse(drops.takesDrop(of: [provider]))
        let placedCount = await drops.placePictures(of: [provider], atViewPoint: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
        XCTAssertEqual(placedCount, 0)
        XCTAssertTrue(session.pictures(on: try XCTUnwrap(session.document.page(at: 0))).isEmpty)
    }

    func testAPDFEmbeddedInANoteLeavesDropsToTheNote() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Embedded.pdf"))
        let coordinator = PDFAnnotationCoordinator(session: session, isEmbedded: true)
        let view = GraphitePDFDisplayView()
        view.document = session.document
        coordinator.attach(to: view)
        defer { coordinator.detach() }
        XCTAssertNil(coordinator.pictureDrops)
    }
}
#endif
