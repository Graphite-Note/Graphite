/**
 * File: PDFLassoArrangeHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Hosted iPad tests of the lasso's pictures and text boxes on a PDF page brought forward or sent back
 *              together, keeping their order among themselves, as one step named for what they are.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// What the lasso's menu calls to arrange its selection (`LassoCanvasContent.arrangeLassoPictures`),
/// on the editing canvas of a PDF page shown in a pane.
@MainActor
final class PDFLassoArrangeHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
    }

    func testTheLassosPicturesAndTextBoxesAreArrangedTogetherAsOneStepNamedForThem() async throws {
        let session = try await openNotebook()
        // The test runs in one turn of the run loop, so UIKit never closes an undo group by
        // event: each step is a group of its own (`step`), as each of a person's actions is.
        session.undoManager.groupsByEvent = false
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await step(in: session) { try await session.addPicture(imageData: try imageData(color: .systemRed)) }
        let red = try XCTUnwrap(session.pictures(on: page).first?.name)
        try await step(in: session) { try await session.addPicture(imageData: try imageData(color: .systemBlue)) }
        let blue = try XCTUnwrap(session.pictures(on: page).map(\.name).first { name in name != red })
        let box = PDFTextBox(name: "box-1", runs: [PDFTextRun(text: "Over the pictures", attributes: .plain)], origin: CGPoint(x: 150, y: 320),
                             width: 120, height: 30, rotationRadians: 0, style: PDFTextBoxDefaults.original.boxStyle)
        try await step(in: session) {
            try session.changeTextBox(from: nil, to: box, on: session.historyPage(for: page), actionName: "Add Text Box")
        }
        XCTAssertEqual(names(on: page), [red, blue, box.name])

        let canvas = try await editingCanvas(for: page, in: session)
        let boxIdentifier = PDFPageCanvasView.textBoxIdentifierPrefix + box.name
        XCTAssertEqual(Set(canvas.lassoPictures().map(\.identifier)), [red, blue, boxIdentifier])

        // The red picture and the box, with the blue picture between them: each way is possible,
        // and to the back they go together, keeping the red picture under the box.
        XCTAssertEqual(canvas.possibleLassoPictureArrangements([red, boxIdentifier]), [.bringToFront, .bringForward, .sendBackward, .sendToBack])
        await step(in: session) { canvas.arrangeLassoPictures([red, boxIdentifier], .sendToBack) }
        XCTAssertEqual(names(on: page), [red, box.name, blue])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Send Items to Back")
        XCTAssertEqual(canvas.possibleLassoPictureArrangements([red, boxIdentifier]), [.bringToFront, .bringForward])
        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [red, blue, box.name], "One Undo puts both back.")

        // One picture is called an image, one text box an item.
        await step(in: session) { canvas.arrangeLassoPictures([red], .bringToFront) }
        XCTAssertEqual(names(on: page), [blue, box.name, red])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Image to Front")
        await step(in: session) { canvas.arrangeLassoPictures([boxIdentifier], .sendToBack) }
        XCTAssertEqual(names(on: page), [box.name, blue, red])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Send Item to Back")

        // A move that would change nothing adds no step (outside a group, a step would raise);
        // the saved file keeps the order.
        canvas.arrangeLassoPictures([red], .bringToFront)
        XCTAssertEqual(names(on: page), [box.name, blue, red])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Send Item to Back")
        XCTAssertNil(session.errorMessage)
        try await session.save()
        let savedPage = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        XCTAssertEqual(names(on: savedPage), [box.name, blue, red])
    }

    private func step(in session: PDFSession, _ operation: () async throws -> Void) async rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try await operation()
    }

    private func names(on page: PDFPage) -> [String] {
        page.annotations.compactMap { annotation in
            PDFPageManager.isPicture(annotation) || annotation.type == PDFTextBox.annotationTypeName ? annotation.persistentName : nil
        }
    }

    private func openNotebook() async throws -> PDFSession {
        let location = try TemporaryVault.make(prefix: "LassoArrange", for: self).root.appendingPathComponent("Notebook.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1).write(to: location)
        return try await PDFSession.open(location)
    }

    private func host(_ rootView: AnyView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func editingCanvas(for page: PDFPage, in session: PDFSession) async throws -> PDFPageCanvasView {
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        return try XCTUnwrap(coordinator()?.editingCanvas(for: page))
    }

    private func imageData(color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 200, height: 120)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }
}
#endif
