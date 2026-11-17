/**
 * File: PDFPageListDropHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: A PDF from Files dropped onto the iPad's page list of a PDF's sidebar, told to the drop interactions
 *              SwiftUI gives the list as UIKit tells them: its pages go between, after or before the pages, with the
 *              line drawn while the drag is held, as one undo step; a page of the list moves where it is let go; a
 *              picture and a protected PDF take no drop.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import XCTest
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class PDFPageListDropHostedTests: XCTestCase {
    private struct ShownList {
        let window: UIWindow
        let session: PDFSession
    }

    /// A PDF whose pages are as wide as `pageWidths` (and 400 points tall), so the test tells them apart by width.
    private func pdfData(pageWidths: [CGFloat], auxiliaryInfo: CFDictionary? = nil) throws -> Data {
        let pdfData = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: pdfData as CFMutableData))
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, auxiliaryInfo))
        for width in pageWidths {
            let pageBox = CGRect(x: 0, y: 0, width: width, height: 400)
            context.beginPDFPage([kCGPDFContextMediaBox: NSData(bytes: [pageBox], length: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.endPDFPage()
        }
        context.closePDF()
        return pdfData as Data
    }

    /// The sidebar of a two-page PDF in a window of its own, 210 points wide as in the pane.
    private func showList(auxiliaryInfo: CFDictionary? = nil) async throws -> ShownList {
        let directory = try TemporaryVault.make(prefix: "PDFPageListDrop", for: self).root
        let location = directory.appendingPathComponent("Annotated handout.pdf")
        try pdfData(pageWidths: [300, 301], auxiliaryInfo: auxiliaryInfo).write(to: location)
        let session = try await PDFSession.open(location)
        let sidebar = PDFPagesSidebar(session: session, commands: PDFPageCommands(session: session), renderer: PDFThumbnailRenderer())
            .frame(width: 210)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 210, height: 800)
        window.rootViewController = UIHostingController(rootView: sidebar)
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            window.isHidden = true
            window.rootViewController = nil
        }
        try await settle()
        return ShownList(window: window, session: session)
    }

    /// Lets SwiftUI lay the list out and draw it: a dozen polls of the main actor, each after a short wait.
    private func settle() async throws {
        var polls = 0
        try await waitUntil("the list settles") {
            polls += 1
            return polls >= 12
        }
    }

    private func dropInteractions(in view: UIView) -> [UIDropInteraction] {
        view.interactions.compactMap { interaction in interaction as? UIDropInteraction } + view.subviews.flatMap(dropInteractions(in:))
    }

    private func pageWidths(of session: PDFSession) -> [CGFloat] {
        (0..<session.document.pageCount).compactMap { pageIndex in session.document.page(at: pageIndex)?.bounds(for: .mediaBox).width }
    }

    private struct DropAnswer {
        var handledBy = 0
        var operations: [UIDropOperation] = []
        var wasPerformed = false
    }

    /// A drag of `providers` that comes down the list to `windowPoint`, is held there while `whileHeld` looks, and is let
    /// go, told to every drop interaction under the point that can handle it, as UIKit tells it.
    @discardableResult
    private func drop(_ providers: [NSItemProvider], at windowPoint: CGPoint, on list: ShownList,
                      whileHeld: () async throws -> Void = {}) async throws -> DropAnswer {
        let dropSession = PageListDropSession(providers: providers, windowPoint: CGPoint(x: windowPoint.x, y: windowPoint.y - 40))
        var answer = DropAnswer()
        let interactions = dropInteractions(in: list.window).filter { interaction in
            guard let view = interaction.view else { return false }
            // A delegate that leaves `canHandle` out handles every session, as UIKit reads it (SwiftUI's leaves it out).
            return view.bounds.contains(view.convert(windowPoint, from: nil)) && interaction.delegate?.dropInteraction?(interaction, canHandle: dropSession) != false
        }
        answer.handledBy = interactions.count
        if interactions.isEmpty { attachDiagnosis(of: list, at: windowPoint, session: dropSession) }
        guard let interaction = interactions.last, let delegate = interaction.delegate else { return answer }
        delegate.dropInteraction?(interaction, sessionDidEnter: dropSession)
        for step in 0...4 {
            dropSession.windowPoint = CGPoint(x: windowPoint.x, y: windowPoint.y - 40 + Double(step) * 10)
            answer.operations.append(delegate.dropInteraction?(interaction, sessionDidUpdate: dropSession).operation ?? .cancel)
        }
        try await settle()
        try await whileHeld()
        if answer.operations.last == .copy || answer.operations.last == .move {
            delegate.dropInteraction?(interaction, performDrop: dropSession)
            answer.wasPerformed = true
        } else {
            delegate.dropInteraction?(interaction, sessionDidExit: dropSession)
        }
        delegate.dropInteraction?(interaction, sessionDidEnd: dropSession)
        return answer
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

    /// Every drop interaction of the window, where it is and what it answers, and a picture of the window, kept with the
    /// result for a person to read when no interaction took a drag.
    private func attachDiagnosis(of list: ShownList, at windowPoint: CGPoint, session: PageListDropSession) {
        let lines = dropInteractions(in: list.window).map { interaction in
            let view = interaction.view
            let frame = view.map { view in view.convert(view.bounds, to: nil) } ?? .null
            let canHandle = interaction.delegate?.dropInteraction?(interaction, canHandle: session)
            return "\(view.map { view in String(describing: type(of: view)) } ?? "no view") \(frame) delegate \(String(describing: interaction.delegate)) canHandle \(String(describing: canHandle))"
        }
        let text = XCTAttachment(string: "window \(list.window.frame), point \(windowPoint)\n" + lines.joined(separator: "\n"))
        text.name = "drop interactions"
        text.lifetime = .keepAlways
        add(text)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(bounds: list.window.bounds, format: format).image { _ in
            list.window.drawHierarchy(in: list.window.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: picture)
        screenshot.name = "window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func filesPDF(pageWidths: [CGFloat]) throws -> NSItemProvider {
        Self.provider(of: try pdfData(pageWidths: pageWidths), as: .pdf)
    }

    /// The colour of the window at a point, from a picture of it.
    private func color(at windowPoint: CGPoint, in window: UIWindow) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let image = try XCTUnwrap(picture.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -windowPoint.x, y: windowPoint.y - CGFloat(image.height) + 1, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    private func isTinted(_ color: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> Bool {
        // The accent itself, not the pale tint behind the row of the page in view.
        max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue) > 0.35
    }

    // The list's rows: below the status bar's 24 points the picker takes about 52, each row about 237 with 14 between,
    // so the first page's middle is near 200 and the second's near 450, the gap near 330, and the list is empty below
    // about 580. Points well inside those ranges keep the tests from hanging on a few points of layout.

    func testAPDFFromFilesDroppedBetweenThePagesInsertsItsPagesAsOneUndoStep() async throws {
        let list = try await showList()
        let gapPoint = CGPoint(x: 105, y: 300)
        let answer = try await drop([try filesPDF(pageWidths: [500, 501])], at: gapPoint, on: list)
        XCTAssertGreaterThan(answer.handledBy, 0, "the list's drop takes a PDF")
        XCTAssertEqual(answer.operations.last, .copy, "a + on the drag")
        try await waitUntil("the pages are inserted", timeoutSeconds: 10) { list.session.pageCount == 4 }
        XCTAssertEqual(pageWidths(of: list.session), [300, 500, 501, 301])
        XCTAssertEqual(list.session.undoManager.undoActionName, "Insert PDF")
        list.session.undoManager.undo()
        XCTAssertEqual(pageWidths(of: list.session), [300, 301], "one Undo takes both pages out")
    }

    func testTheLineShowsWhileTheDragIsHeld() async throws {
        let list = try await showList()
        // Drawn halfway between the rows, near 330.
        var heldColors: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = []
        // Looked for left of the thumbnails and of the tint behind the row in view, where the line still runs, and away
        // from the row's page number, which is in the accent for the page in view.
        let probes = stride(from: 300.0, through: 360.0, by: 1.0).map { y in CGPoint(x: 18, y: y) }
        let before = try probes.map { probe in try color(at: probe, in: list.window) }
        try await drop([try filesPDF(pageWidths: [500])], at: CGPoint(x: 105, y: 300), on: list) {
            heldColors = try probes.map { probe in try color(at: probe, in: list.window) }
        }
        XCTAssertFalse(before.contains(where: isTinted), "no line before the drag")
        XCTAssertTrue(heldColors.contains(where: isTinted), "the line shows in the gap while the drag is held")
    }

    func testPDFsGoAfterTheLastPageAndBeforeTheFirst() async throws {
        let list = try await showList()
        try await drop([try filesPDF(pageWidths: [500])], at: CGPoint(x: 105, y: 700), on: list)
        try await waitUntil("the page is inserted at the end", timeoutSeconds: 10) { list.session.pageCount == 3 }
        XCTAssertEqual(pageWidths(of: list.session), [300, 301, 500], "dropped in the empty space below the last page")
        try await settle()
        try await drop([try filesPDF(pageWidths: [600])], at: CGPoint(x: 105, y: 130), on: list)
        try await waitUntil("the page is inserted at the start", timeoutSeconds: 10) { list.session.pageCount == 4 }
        XCTAssertEqual(pageWidths(of: list.session), [600, 300, 301, 500], "dropped on the first page's top half")
    }

    func testAPageDraggedWithinTheListMovesWhereItIsLetGo() async throws {
        let list = try await showList()
        let firstPage = PDFPageDragItem(sessionIdentifier: list.session.identifier, pageIndex: 0)
        let answer = try await drop([Self.provider(of: try JSONEncoder().encode(firstPage), as: .graphitePDFPage)], at: CGPoint(x: 105, y: 700), on: list)
        XCTAssertTrue(answer.wasPerformed, "a page is taken over the list")
        try await waitUntil("the page moved", timeoutSeconds: 10) { self.pageWidths(of: list.session) == [301, 300] }
        let otherPDFsPage = PDFPageDragItem(sessionIdentifier: UUID(), pageIndex: 0)
        try await drop([Self.provider(of: try JSONEncoder().encode(otherPDFsPage), as: .graphitePDFPage)], at: CGPoint(x: 105, y: 700), on: list)
        try await settle()
        XCTAssertEqual(pageWidths(of: list.session), [301, 300], "a page of another PDF moves nothing")
    }

    func testAPictureIsNotTaken() async throws {
        let list = try await showList()
        let picture = Self.provider(of: Data([0x89, 0x50, 0x4E, 0x47]), as: .png)
        let answer = try await drop([picture], at: CGPoint(x: 105, y: 300), on: list)
        XCTAssertFalse(answer.wasPerformed)
        try await settle()
        XCTAssertEqual(list.session.pageCount, 2)
    }

    func testAPasswordProtectedPDFTakesNoDrop() async throws {
        let list = try await showList(auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""] as CFDictionary)
        XCTAssertTrue(list.session.isProtected)
        let answer = try await drop([try filesPDF(pageWidths: [500])], at: CGPoint(x: 105, y: 300), on: list)
        XCTAssertFalse(answer.wasPerformed, "no + and no drop")
        try await settle()
        XCTAssertEqual(list.session.pageCount, 2)
    }
}

/// A drag over a window as UIKit's drop session describes it to a drop interaction: its items and the touch's place.
/// UIKit makes its own sessions only from a hand's drag, so a test gives this one in its place.
@MainActor
private final class PageListDropSession: NSObject, UIDropSession {
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
