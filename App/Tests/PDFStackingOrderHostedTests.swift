/**
 * File: PDFStackingOrderHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The stacking order of a PDF page's pictures, text boxes and ink as the iPad shows it: what is under
 *              the ink drawn by PDFKit, what is over it drawn over the Pencil canvas, in the file's order.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// A red picture, a blue picture over it, the page's ink and a yellow text box over all of them,
/// arranged in the hosted app: the colour on screen where they overlap is the topmost object's, as
/// in the file, whether PDFKit draws it under the ink or the page's overlay over it.
@MainActor
final class PDFStackingOrderHostedTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
    }

    func testTheTopmostObjectIsDrawnWhereObjectsOverlapAsTheyAreArranged() async throws {
        let (session, controller, page) = try await openNotebook()
        let cropBox = page.bounds(for: .cropBox)
        let middle = CGPoint(x: cropBox.midX, y: cropBox.midY)
        try await session.addPicture(imageData: solidImage(red: 1, green: 0, blue: 0), placement: (0, CGPoint(x: middle.x - 60, y: middle.y)),
                                     preferredWidth: 200)
        try await session.addPicture(imageData: solidImage(red: 0, green: 0, blue: 1), placement: (0, CGPoint(x: middle.x + 60, y: middle.y)),
                                     preferredWidth: 200)
        session.selectedPicture = nil
        endEvent()
        let box = PDFTextBoxLayout.fitted(PDFTextBox(name: "stacked-box", runs: [PDFTextRun(text: "Box", attributes: .plain)],
                                                     origin: CGPoint(x: middle.x - 40, y: middle.y + 30), width: 80, height: 60, rotationRadians: 0,
                                                     style: PDFTextBoxStyle(alignment: .left, lineSpacing: 1, fillColor: PDFTextColor(red: 1, green: 1, blue: 0),
                                                                            borderColor: nil, borderWidth: 0, padding: 30)))
        try session.changeTextBox(from: nil, to: box, on: session.historyPage(for: page), actionName: "Add Text Box")
        endEvent()
        // Where the box covers both pictures, left over the red alone and right over the blue.
        let overBoth = CGPoint(x: middle.x, y: middle.y + 10)
        let overRedOnly = CGPoint(x: middle.x - 140, y: middle.y)
        // On the stroke, where it crosses the blue picture alone.
        let strokeOverBlue = CGPoint(x: middle.x + 120, y: middle.y - Self.strokeOffsetBelowMiddle)
        let pictureNames = session.pictures(on: page).map(\.name)
        XCTAssertEqual(pictureNames.count, 2)
        let blueSelection = PDFPictureSelection(pictureName: pictureNames[1], page: session.historyPage(for: page))

        try await expect(.yellow, at: overBoth, on: page, in: controller, "The box was placed over both pictures.")
        try await expect(.red, at: overRedOnly, on: page, in: controller)
        try await expect(.ink, at: strokeOverBlue, on: page, in: controller, "A new picture goes under the ink.")
        XCTAssertEqual(overInkViewObjectCount(in: controller), 1, "The box alone is over the ink.")
        attachScreenshot(of: controller, named: "Pictures under the ink, the box over it")

        // The blue picture over the box: drawn over the canvas, its annotation hidden.
        try session.arrangePicture(blueSelection, .bringToFront)
        endEvent()
        try await expect(.blue, at: overBoth, on: page, in: controller, "The blue picture brought to the front covers the box.")
        try await expect(.blue, at: strokeOverBlue, on: page, in: controller, "Over the box, the picture is over the ink too.")
        XCTAssertEqual(overInkViewObjectCount(in: controller), 2)
        let blueAnnotation = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == pictureNames[1] })
        XCTAssertFalse(blueAnnotation.shouldDisplay, "Drawn over the ink by the overlay, not twice.")
        attachScreenshot(of: controller, named: "Blue picture over the text box")

        // Undo puts it back under the box, drawn by PDFKit again.
        session.undoAvailability.undo()
        endEvent()
        try await expect(.yellow, at: overBoth, on: page, in: controller, "Undo puts the picture back under the box.")
        try await expect(.ink, at: strokeOverBlue, on: page, in: controller, "And under the ink.")
        XCTAssertTrue(try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == pictureNames[1] }).shouldDisplay)

        // The box sent to the back: under both pictures, which then cover it.
        session.textBoxActivity = .selected(PDFTextBoxSelection(boxName: box.name, page: session.historyPage(for: page)))
        try session.arrangeSelectedTextBox(.sendToBack)
        session.textBoxActivity = .idle
        endEvent()
        try await expect(.blue, at: overBoth, on: page, in: controller, "Sent to the back, the box is under the pictures.")
        try await expect(.ink, at: strokeOverBlue, on: page, in: controller, "The pictures stay under the ink.")
        XCTAssertEqual(overInkViewObjectCount(in: controller), 0)
        attachScreenshot(of: controller, named: "Text box sent to the back")
    }

    // MARK: Helpers

    private enum SampleColor { case red, blue, yellow, ink }

    /// How far under the page's middle the stroke runs.
    private static let strokeOffsetBelowMiddle: CGFloat = 60

    /// Waits until the screen shows the colour at a point of the page.
    private func expect(_ color: SampleColor, at pagePoint: CGPoint, on page: PDFPage, in controller: UIViewController, _ message: String = "",
                        file: StaticString = #filePath, line: UInt = #line) async throws {
        let pdfView = try XCTUnwrap((controller.view.window.flatMap { window in descendants(of: window, matching: PDFView.self).first }))
        let windowPoint = pdfView.convert(pdfView.convert(pagePoint, from: page), to: nil)
        try await waitUntil("\(color) shows at \(pagePoint). \(message)", timeoutSeconds: 6, pollingIntervalSeconds: 0.1, file: file, line: line) {
            let shown = try pixel(at: windowPoint, in: controller)
            return switch color {
            case .red: shown.red > 200 && shown.green < 80 && shown.blue < 80
            case .blue: shown.blue > 200 && shown.red < 80 && shown.green < 80
            case .yellow: shown.red > 200 && shown.green > 200 && shown.blue < 80
            case .ink: shown.red < 80 && shown.green < 80 && shown.blue < 80
            }
        }
    }

    private func pixel(at windowPoint: CGPoint, in controller: UIViewController) throws -> (red: Int, green: Int, blue: Int) {
        let window = try XCTUnwrap(controller.view.window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: CGRect(x: windowPoint.x, y: windowPoint.y, width: 1, height: 1), format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func openNotebook() async throws -> (PDFSession, UIHostingController<AnyView>, PDFPage) {
        let location = try makeHostedBlankNotebook(named: "StackingOrder")
        locations.append(location)
        // A stroke across the page, 60 points under its middle, where the pictures will be.
        let written = try XCTUnwrap(PDFDocument(url: location))
        PDFPageManager.prepareForWriting(written)
        let writtenCropBox = try XCTUnwrap(written.page(at: 0)).bounds(for: .cropBox)
        let strokeHeight = writtenCropBox.midY - Self.strokeOffsetBelowMiddle
        let stroke = PortableInkStroke(name: "stroke", segments: [[CGPoint(x: writtenCropBox.minX + 40, y: strokeHeight),
                                                                    CGPoint(x: writtenCropBox.maxX - 40, y: strokeHeight)]], width: 6,
                                       red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        try PDFPageManager.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke],
                                                         editableRecord: nil)), to: written, drawsInkOutlines: true)
        XCTAssertTrue(written.write(to: location))
        let session = try await PDFSession.open(location)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil("the page's canvas edits it") { coordinator()?.editingCanvas(for: page) != nil }
        return (session, controller, page)
    }

    private func overInkViewObjectCount(in controller: UIViewController) -> Int {
        descendants(of: controller.view, matching: PDFPageObjectsOverInkView.self).reduce(0) { count, view in count + view.objects.count }
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

    /// Steps made in code arrive within one turn of the run loop, in one undo group.
    private func endEvent() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let window = controller.view.window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}
#endif
