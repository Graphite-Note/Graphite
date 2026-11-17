/**
 * File: PDFPictureDropHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Hosted iPad test of pictures dropped onto a PDF view in a window: the view takes drops, an image as
 *              Photos and Safari offer it and an image file of the vault as the sidebar offers it are placed where
 *              they landed, selected, as one step each; a PDF file and a protected PDF take none, and a PDF let go over
 *              a page says why in the banner; a PDF dragged from the sidebar is turned away as it is dragged in.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
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

    /// The drop interaction's own methods, called as UIKit calls them: a drag of a PDF over a page is forbidden, which
    /// UIKit never hands over as a drop, so letting go over the page says why in the banner; carried off the view
    /// first, it says nothing. A picture's drag is a copy.
    func testAPDFLetGoOverAPageSaysWhyInTheBanner() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Worksheet.pdf"))
        let (window, view, drops) = try await show(session)
        let interaction = try XCTUnwrap(drops.interaction)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let overPage = view.convert(view.convert(CGPoint(x: 200, y: 300), from: page), to: window)
        let pdfFile = provider(of: try Data(contentsOf: try makePDF(named: "Handout.pdf")), as: .pdf)

        let dragOfPDF = TellingDropSession(providers: [pdfFile], windowPoint: overPage)
        XCTAssertTrue(drops.dropInteraction(interaction, canHandle: dragOfPDF), "the drag of a PDF is followed, to say why at its end")
        XCTAssertEqual(drops.dropInteraction(interaction, sessionDidUpdate: dragOfPDF).operation, .forbidden)
        drops.dropInteraction(interaction, sessionDidEnd: dragOfPDF)
        XCTAssertEqual(session.errorMessage, "A PDF can't be placed on a page as an image. Drop a picture, such as a PNG or JPEG.")
        XCTAssertTrue(session.pictures(on: page).isEmpty)

        session.errorMessage = nil
        let carriedAway = TellingDropSession(providers: [pdfFile], windowPoint: overPage)
        _ = drops.dropInteraction(interaction, sessionDidUpdate: carriedAway)
        carriedAway.windowPoint = CGPoint(x: view.convert(view.bounds, to: window).maxX + 40, y: overPage.y)
        _ = drops.dropInteraction(interaction, sessionDidUpdate: carriedAway)
        drops.dropInteraction(interaction, sessionDidEnd: carriedAway)
        XCTAssertNil(session.errorMessage, "let go off the view, the drag says nothing")

        let dragOfPicture = TellingDropSession(providers: [imageProvider(try pngData())], windowPoint: overPage)
        XCTAssertTrue(drops.dropInteraction(interaction, canHandle: dragOfPicture))
        XCTAssertEqual(drops.dropInteraction(interaction, sessionDidUpdate: dragOfPicture).operation, .copy)
        drops.dropInteraction(interaction, sessionDidEnd: dragOfPicture)
        XCTAssertNil(session.errorMessage)
    }

    /// A PDF of the vault dragged from Graphite's sidebar is turned away as it is dragged in, by the name its drag gives
    /// (`NSItemProvider.graphiteDrag`, as the sidebar makes it): no "+", and letting go over a page says why. A picture of
    /// the vault is still a copy, and a folder names nothing.
    func testAPDFDraggedFromTheSidebarIsTurnedAwayAsItIsDraggedIn() async throws {
        let session = try await PDFSession.open(try makePDF(named: "Worksheet.pdf"))
        let (window, view, drops) = try await show(session)
        let interaction = try XCTUnwrap(drops.interaction)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let overPage = view.convert(view.convert(CGPoint(x: 200, y: 300), from: page), to: window)
        _ = try makePDF(named: "Handout.pdf")
        try pngData().write(to: directory.appendingPathComponent("Figure.png"))

        func sidebarDrag(of rawPath: String, isDirectory: Bool = false) throws -> NSItemProvider {
            let entry = VaultEntry(path: try VaultPath(rawPath), isDirectory: isDirectory, size: 0, modified: Date())
            return NSItemProvider.graphiteDrag(of: VaultItemTransfer(path: rawPath, vaultRoot: directory), contentType: .graphiteVaultItem,
                                               suggestedName: VaultItemTransfer.suggestedName(of: entry), opening: nil)
        }
        let sidebarPDF = try sidebarDrag(of: "Handout.pdf")
        XCTAssertEqual(sidebarPDF.suggestedName, "Handout.pdf")
        XCTAssertEqual(PDFPictureDropReader.kind(of: sidebarPDF), .pdfDocument)
        let dragOfPDF = TellingDropSession(providers: [sidebarPDF], windowPoint: overPage)
        XCTAssertTrue(drops.dropInteraction(interaction, canHandle: dragOfPDF))
        XCTAssertEqual(drops.dropInteraction(interaction, sessionDidUpdate: dragOfPDF).operation, .forbidden, "no + from the start")
        drops.dropInteraction(interaction, sessionDidEnd: dragOfPDF)
        XCTAssertEqual(session.errorMessage, "A PDF can't be placed on a page as an image. Drop a picture, such as a PNG or JPEG.")
        XCTAssertTrue(session.pictures(on: page).isEmpty)
        session.errorMessage = nil

        let sidebarPicture = try sidebarDrag(of: "Figure.png")
        XCTAssertEqual(PDFPictureDropReader.kind(of: sidebarPicture), .picture)
        XCTAssertEqual(drops.dropInteraction(interaction, sessionDidUpdate: TellingDropSession(providers: [sidebarPicture], windowPoint: overPage)).operation, .copy)
        XCTAssertNil(try sidebarDrag(of: "Lectures", isDirectory: true).suggestedName, "a folder names no file")
    }

    func testAPasswordProtectedPDFTakesNoDrop() async throws {
        let location = try makePDF(named: "Encrypted.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""] as CFDictionary)
        let session = try await PDFSession.open(location)
        XCTAssertTrue(session.isProtected)
        let (_, view, drops) = try await show(session)
        let provider = imageProvider(try pngData())
        XCTAssertFalse(drops.takesDrop(of: [provider]))
        let pdfFile = self.provider(of: try Data(contentsOf: try makePDF(named: "Handout.pdf")), as: .pdf)
        XCTAssertFalse(drops.isRefusedWithReason([pdfFile]), "a protected PDF says nothing of a PDF dragged over it")
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

/// A drag over a window as UIKit's drop session describes it to a drop interaction: its items and the touch's place.
/// UIKit makes its own sessions only from a hand's drag, so a test gives this one in its place.
@MainActor
private final class TellingDropSession: NSObject, UIDropSession {
    let items: [UIDragItem]
    /// The touch, in the window's coordinates.
    var windowPoint: CGPoint
    var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle = .none
    let progress = Progress(totalUnitCount: 1)

    init(providers: [NSItemProvider], windowPoint: CGPoint) {
        items = providers.map(UIDragItem.init(itemProvider:))
        self.windowPoint = windowPoint
    }

    func location(in view: UIView) -> CGPoint { view.convert(windowPoint, from: nil) }
    var allowsMoveOperation: Bool { false }
    var isRestrictedToDraggingApplication: Bool { false }
    /// Another application's drag.
    var localDragSession: (any UIDragSession)? { nil }

    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool {
        items.contains { item in typeIdentifiers.contains { identifier in item.itemProvider.hasItemConformingToTypeIdentifier(identifier) } }
    }

    func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool {
        items.contains { item in item.itemProvider.canLoadObject(ofClass: aClass) }
    }

    func loadObjects(ofClass aClass: any NSItemProviderReading.Type, completion: @escaping ([any NSItemProviderReading]) -> Void) -> Progress {
        completion([])
        return progress
    }
}
#endif
