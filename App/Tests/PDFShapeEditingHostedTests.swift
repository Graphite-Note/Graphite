/**
 * File: PDFShapeEditingHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Hosted iPad tests of shapes the Mac's Shapes tool drew, and another application's unnamed /Square: a
 *              finger's tap selects one, a drag moves it, a handle resizes it, its menu changes border, fill and width
 *              and deletes it, each one step with the Mac's names; the saved file keeps standard /Square and /Line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class PDFShapeEditingHostedTests: XCTestCase {
    private var directory: URL!
    private static let red = PDFTextColor(red: 1, green: 0, blue: 0)
    private static let yellow = PDFTextColor(red: 1, green: 0.75, blue: 0)
    private let rectangle = PDFShape(name: "mac-rectangle", kind: .rectangle, start: CGPoint(x: 60, y: 380), end: CGPoint(x: 200, y: 480),
                                     borderColor: red, fillColor: yellow, lineWidth: 2.5)
    private let arrow = PDFShape(name: "mac-arrow", kind: .arrow, start: CGPoint(x: 60, y: 200), end: CGPoint(x: 300, y: 260),
                                 borderColor: .black, lineWidth: 5)
    /// Where Preview's unnamed square is: its own rectangle, written by PDFKit with no /NM.
    private let unnamedSquareBounds = CGRect(x: 250, y: 380, width: 100, height: 80)

    override func setUp() async throws {
        directory = try TemporaryVault.make(prefix: "PDFShapeEditing", for: self).root
    }

    /// A page with the Mac's rectangle and arrow, written by the session's own shape edits and
    /// saved as the Mac saves them, and another application's square without a name.
    private func makePDFAsTheMacDrewIt() async throws -> URL {
        let location = directory.appendingPathComponent("Worksheet.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(url: location))
        let square = PDFAnnotation(bounds: unnamedSquareBounds, forType: .square, withProperties: nil)
        square.color = .blue
        square.border = PDFBorder()
        square.border?.lineWidth = 1
        try XCTUnwrap(document.page(at: 0)).addAnnotation(square)
        XCTAssertTrue(document.write(to: location))
        let session = try await PDFSession.open(location)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try session.addShape(rectangle, on: page)
        try session.addShape(arrow, on: page)
        try await session.save()
        return location
    }

    /// The PDF in a window, as a pane shows it while annotating.
    private func show() async throws -> (session: PDFSession, controller: PDFShapeSelectionController, pdfView: GraphitePDFDisplayView, page: PDFPage) {
        let session = try await PDFSession.open(try await makePDFAsTheMacDrewIt())
        let input = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        let hosting = UIHostingController(rootView: GraphitePDFView(session: session, input: input))
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 1_000)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        addTeardownBlock { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let controller = try XCTUnwrap(pdfView.annotationCoordinator?.shapeSelection)
        return (session, controller, pdfView, try XCTUnwrap(session.document.page(at: 0)))
    }

    private func shape(named name: String, in session: PDFSession, on page: PDFPage) -> PDFShape? {
        session.shapeAnnotation(named: name, on: page).flatMap(PDFShape.init(annotation:))
    }

    private func windowPoint(_ pagePoint: CGPoint, on page: PDFPage, in pdfView: PDFView) -> CGPoint {
        pdfView.convert(pdfView.convert(pagePoint, from: page), to: nil)
    }

    private func requireTouches() throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { throw SynthesizedTouchesUnavailable() }
    }

    private struct SynthesizedTouchesUnavailable: Error {}

    /// Draws the window once the menu and the handles have shown.
    private func attach(_ window: UIWindow, named name: String) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Ends the event, so the next change is a step of its own, as each tap of a menu is.
    private func endEvent(of session: PDFSession) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(session.undoManager.groupingLevel, 0)
    }

    private func menuItem(_ path: [String], of controller: PDFShapeSelectionController) throws -> UIAction {
        var elements = try XCTUnwrap(controller.menu()).children
        for title in path.dropLast() {
            elements = try XCTUnwrap(elements.first { element in element.title == title } as? UIMenu, title).children
        }
        return try XCTUnwrap(elements.first { element in element.title == path.last } as? UIAction, path.joined(separator: " › "))
    }

    func testAFingerSelectsMovesAndResizesTheMacsRectangleEachAsOneStep() async throws {
        try requireTouches()
        let (session, controller, pdfView, page) = try await show()
        let window = try XCTUnwrap(pdfView.window)
        let touches = SynthesizedTouches(window: window)

        // A tap on the rectangle's border selects it and shows its handles at its four corners.
        let onBorder = windowPoint(CGPoint(x: 130, y: 380), on: page, in: pdfView)
        await touches.move(paths: [(onBorder, onBorder)], steps: 1, stepSeconds: 0.03, holdSeconds: 0)
        try await waitUntil("the tapped rectangle is selected") { controller.selectedShapeName == "mac-rectangle" }
        let frameView = try XCTUnwrap(controller.frameView)
        XCTAssertFalse(frameView.isHidden)
        XCTAssertEqual(frameView.handlesPositions.count, 4)
        XCTAssertTrue(controller.isMenuShown, "Its menu shows when it is selected.")
        attach(window, named: "The Mac's rectangle selected by a finger, with its menu")
        let scale = pdfView.scaleFactor

        // A drag from inside it moves it, as one Move Shape step.
        let inside = windowPoint(CGPoint(x: 130, y: 430), on: page, in: pdfView)
        await touches.drag(from: inside, to: CGPoint(x: inside.x + 60, y: inside.y + 40))
        try await waitUntil("the rectangle moved") { session.undoManager.undoActionName == "Move Shape" }
        let moved = try XCTUnwrap(shape(named: "mac-rectangle", in: session, on: page))
        XCTAssertEqual(moved.start.x, rectangle.start.x + 60 / scale, accuracy: 3)
        XCTAssertEqual(moved.start.y, rectangle.start.y - 40 / scale, accuracy: 3, "Down on the screen is down the page.")
        XCTAssertEqual(moved.boxRectangle.size.width, rectangle.boxRectangle.size.width, accuracy: 0.01)
        XCTAssertEqual(moved.fillColor, Self.yellow)

        // Its top right corner's handle resizes it, as one Resize Shape step; the opposite corner stays.
        let corner = windowPoint(moved.end, on: page, in: pdfView)
        await touches.drag(from: corner, to: CGPoint(x: corner.x + 50, y: corner.y - 30))
        try await waitUntil("the rectangle was resized") { session.undoManager.undoActionName == "Resize Shape" }
        attach(window, named: "The rectangle moved and resized by a finger")
        let resized = try XCTUnwrap(shape(named: "mac-rectangle", in: session, on: page))
        XCTAssertEqual(resized.start.x, moved.start.x, accuracy: 0.01)
        XCTAssertEqual(resized.start.y, moved.start.y, accuracy: 0.01)
        XCTAssertEqual(resized.end.x, moved.end.x + 50 / scale, accuracy: 3)
        XCTAssertEqual(resized.end.y, moved.end.y + 30 / scale, accuracy: 3)

        // Each was one step: undo takes the resize, then the move, back; redo puts the move back.
        session.undoManager.undo()
        XCTAssertEqual(shape(named: "mac-rectangle", in: session, on: page)?.boxRectangle, moved.boxRectangle)
        session.undoManager.undo()
        XCTAssertEqual(shape(named: "mac-rectangle", in: session, on: page)?.boxRectangle, rectangle.boxRectangle)
        session.undoManager.redo()
        XCTAssertEqual(shape(named: "mac-rectangle", in: session, on: page)?.boxRectangle, moved.boxRectangle)

        // A tap beside every shape leaves it.
        let beside = windowPoint(CGPoint(x: 350, y: 540), on: page, in: pdfView)
        await touches.move(paths: [(beside, beside)], steps: 1, stepSeconds: 0.03, holdSeconds: 0)
        try await waitUntil("nothing is selected") { !controller.isShapeSelected }
        XCTAssertTrue(controller.frameView?.isHidden ?? true)
    }

    func testTheMenuRestylesAndDeletesTheMacsArrowEachAsOneStepAndTheFileKeepsStandardShapes() async throws {
        let (session, controller, pdfView, page) = try await show()
        XCTAssertTrue(controller.selectShape(at: pdfView.convert(CGPoint(x: 180, y: 230), from: page)), "A point on the arrow's line selects it.")
        XCTAssertEqual(controller.selectedShapeName, "mac-arrow")
        XCTAssertEqual(controller.frameView?.handlesPositions.count, 2, "A line has a handle at each end.")
        // A line has no inside to fill.
        XCTAssertEqual(try XCTUnwrap(controller.menu()).children.map(\.title), ["Border", "Line Width", "Delete Shape"])
        XCTAssertEqual(try menuItem(["Line Width", "Bold"], of: controller).state, .on, "The arrow's own width is ticked.")

        try menuItem(["Border", "Black"], of: controller).performWithSender(nil, target: nil)
        endEvent(of: session)
        XCTAssertNotEqual(session.undoManager.undoActionName, "Format Shape", "Its own colour changes nothing.")
        try menuItem(["Line Width", "Fine"], of: controller).performWithSender(nil, target: nil)
        endEvent(of: session)
        XCTAssertEqual(session.undoManager.undoActionName, "Format Shape")
        let thinner = try XCTUnwrap(shape(named: "mac-arrow", in: session, on: page))
        XCTAssertEqual(thinner.lineWidth, 1)
        XCTAssertEqual(thinner.kind, .arrow, "The arrow keeps its head.")
        XCTAssertEqual(thinner.start, arrow.start)

        // The rectangle: no fill, then a black border, two steps.
        XCTAssertTrue(controller.selectShape(at: pdfView.convert(CGPoint(x: 130, y: 430), from: page)))
        XCTAssertEqual(controller.selectedShapeName, "mac-rectangle")
        XCTAssertEqual(try XCTUnwrap(controller.menu()).children.map(\.title), ["Border", "Fill", "Line Width", "Delete Shape"])
        try menuItem(["Fill", "No Fill"], of: controller).performWithSender(nil, target: nil)
        endEvent(of: session)
        try menuItem(["Border", "Black"], of: controller).performWithSender(nil, target: nil)
        endEvent(of: session)
        let restyled = try XCTUnwrap(shape(named: "mac-rectangle", in: session, on: page))
        XCTAssertNil(restyled.fillColor)
        XCTAssertEqual(restyled.borderColor, .black)
        session.undoManager.undo()
        XCTAssertEqual(shape(named: "mac-rectangle", in: session, on: page)?.borderColor, Self.red)
        XCTAssertNil(shape(named: "mac-rectangle", in: session, on: page)?.fillColor)
        session.undoManager.redo()
        endEvent(of: session)

        // Preview's square, which has no name, is found by where it is, moved and keeps its author's look.
        XCTAssertTrue(controller.selectShape(at: pdfView.convert(CGPoint(x: unnamedSquareBounds.midX, y: unnamedSquareBounds.midY), from: page)))
        let square = try XCTUnwrap(controller.selectedShape)
        XCTAssertTrue(controller.beginDrag(at: pdfView.convert(CGPoint(x: 300, y: 420), from: page)))
        controller.endDrag(at: pdfView.convert(CGPoint(x: 300, y: 400), from: page))
        endEvent(of: session)
        XCTAssertEqual(session.undoManager.undoActionName, "Move Shape")
        let movedSquare = try XCTUnwrap(controller.selectedShape)
        XCTAssertEqual(movedSquare.start.y, square.start.y - 20, accuracy: 0.01)
        XCTAssertEqual(movedSquare.borderColor, square.borderColor)

        // Delete Shape removes the arrow; undo puts it back where it was among the page's layers.
        XCTAssertTrue(controller.selectShape(at: pdfView.convert(CGPoint(x: 180, y: 230), from: page)))
        let layersBefore = page.annotations.map(\.persistentName)
        try menuItem(["Delete Shape"], of: controller).performWithSender(nil, target: nil)
        endEvent(of: session)
        XCTAssertEqual(session.undoManager.undoActionName, "Delete Shape")
        XCTAssertNil(shape(named: "mac-arrow", in: session, on: page))
        XCTAssertFalse(controller.isShapeSelected)
        session.undoManager.undo()
        XCTAssertNotNil(shape(named: "mac-arrow", in: session, on: page))
        XCTAssertEqual(page.annotations.map(\.persistentName), layersBefore)

        // The saved file keeps them as standard annotations the Mac and other readers show.
        try await session.save()
        // A copy kept outside the test's vault, for opening the iPad's file on the Mac afterwards.
        let keptCopy = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first).appendingPathComponent("ShapesEditedOnTheIPad.pdf")
        try? FileManager.default.removeItem(at: keptCopy)
        try FileManager.default.copyItem(at: session.location, to: keptCopy)
        let saved = try XCTUnwrap(PDFDocument(url: session.location).flatMap { document in document.page(at: 0) })
        let savedShapes = saved.annotations.compactMap(PDFShape.init(annotation:))
        XCTAssertEqual(saved.annotations.filter { annotation in annotation.type == "Square" }.count, 2)
        XCTAssertEqual(saved.annotations.filter { annotation in annotation.type == "Line" }.count, 1)
        let savedArrow = try XCTUnwrap(savedShapes.first { shape in shape.name == "mac-arrow" })
        XCTAssertEqual(savedArrow.kind, .arrow)
        XCTAssertEqual(savedArrow.lineWidth, 1)
        let savedRectangle = try XCTUnwrap(savedShapes.first { shape in shape.name == "mac-rectangle" })
        XCTAssertNil(savedRectangle.fillColor)
        XCTAssertEqual(savedRectangle.borderColor, .black)
        XCTAssertEqual(savedShapes.first { shape in shape.borderColor != .black && shape.kind == .rectangle }?.start.y ?? 0,
                       movedSquare.start.y, accuracy: 0.5, "Preview's square is saved where it was moved.")
    }
}
#endif
