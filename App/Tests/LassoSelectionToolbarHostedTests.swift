/**
 * File: LassoSelectionToolbarHostedTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Hosted iPad tests of the lasso selection's floating toolbar (Docs/Lasso-todo.md section 4): it shows beside
 *              the selection in place of an edit menu, its buttons take their taps, it hides while the selection is
 *              dragged, it gives up swatches before commands where it is narrow, and on a PDF page it brings several
 *              pictures and text boxes to the front or sends them to the back as one step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import PencilKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class LassoSelectionToolbarHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
    }

    private func window(showing controller: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return window
    }

    private func horizontalStroke(y: CGFloat) -> PKStroke {
        let controlPoints = stride(from: CGFloat(100), through: 400, by: 10).enumerated().map { index, x in
            PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: TimeInterval(index) / 100, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }

    /// A drawing's canvas in a window, as the drawing editor shows one, with a stroke selected.
    private func canvasWithSelectedStroke() throws -> (canvas: HistoryCanvasView, window: UIWindow) {
        let controller = UIViewController()
        let window = try window(showing: controller)
        let canvas = HistoryCanvasView(frame: controller.view.bounds.insetBy(dx: 40, dy: 120))
        canvas.drawing = PKDrawing(strokes: [horizontalStroke(y: 300)])
        controller.view.addSubview(canvas)
        canvas.inkSelection.isActive = true
        canvas.inkSelection.select([0])
        return (canvas, window)
    }

    func testTheSelectionShowsItsBarInPlaceOfAnEditMenuAndItsDeleteButtonTakesTheTap() throws {
        let (canvas, window) = try canvasWithSelectedStroke()
        let selection = canvas.inkSelection
        let frameView = try XCTUnwrap(canvas.subviews.compactMap { $0 as? SelectionFrameView }.first)
        XCTAssertFalse(frameView.interactions.contains { interaction in interaction is UIEditMenuInteraction },
                       "No edit menu on the selection: iOS adds Ask Siri to one (owner, 2026-11-17).")
        let bar = try XCTUnwrap(selection.selectionToolbar.toolbar)
        XCTAssertTrue(bar.isShown)
        XCTAssertTrue(bar.superview === canvas.superview, "A drawing's bar stands beside its canvas, not in the zoomed drawing.")
        XCTAssertEqual(bar.buttons.first?.accessibilityLabel, "Take Screenshot")
        XCTAssertTrue(bar.buttons.contains { button in button.accessibilityLabel == "Black" }, "Black is one tap away.")
        XCTAssertNotNil(bar.moreButton, "Smooth is behind \"…\".")
        XCTAssertNotNil(FloatingSelectionToolbar.swatchImage(of: .black), "Black gets a light ring on the dark bar.")
        XCTAssertNil(FloatingSelectionToolbar.swatchImage(of: .systemRed), "A light colour is a plain dot.")
        XCTAssertFalse(selection.selectionToolbarCommands().items.contains { item in item.title.contains("Front") }, "A drawing does not arrange.")
        let box = canvas.convert(frameView.boxWithHandlesInSuperview, to: bar.superview)
        XCTAssertFalse(bar.frame.intersects(box), "The bar keeps clear of the selection and its handles.")
        attachScreenshot(of: window, named: "The lasso's bar beside a selected stroke")

        // A touch on the bar's Delete reaches the button, not the canvas under it.
        let delete = try XCTUnwrap(bar.buttons.first { button in button.accessibilityLabel == "Delete" })
        let center = delete.convert(CGPoint(x: delete.bounds.midX, y: delete.bounds.midY), to: window)
        XCTAssertTrue(window.hitTest(center, with: nil) === delete)
        delete.sendActions(for: .primaryActionTriggered)
        XCTAssertTrue(canvas.drawing.strokes.isEmpty)
        XCTAssertFalse(bar.isShown, "Nothing selected, no bar.")
    }

    func testTheBarHidesWhileTheSelectionIsDraggedAndComesBackWhereTheDragEnds() throws {
        let (canvas, _) = try canvasWithSelectedStroke()
        let selection = canvas.inkSelection
        let bar = try XCTUnwrap(selection.selectionToolbar.toolbar)
        let frameView = try XCTUnwrap(canvas.subviews.compactMap { $0 as? SelectionFrameView }.first)
        selection.selectionDragDidBegin()
        XCTAssertFalse(bar.isShown)
        frameView.frameChangeWasCancelled?()
        XCTAssertTrue(bar.isShown)

        // A tap on the selection hides the bar, another shows it.
        selection.selectionToolbar.toggle()
        XCTAssertFalse(bar.isShown)
        selection.selectionToolbar.toggle()
        XCTAssertTrue(bar.isShown)
    }

    func testANarrowBarGivesUpSwatchesFirstThenDuplicateAndCut() throws {
        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        canvas.drawing = PKDrawing(strokes: [horizontalStroke(y: 300)])
        let selection = canvas.inkSelection
        selection.select([0])
        let palette = ["red": "#e93147", "orange": "#ec7500", "yellow": "#e0ac00", "green": "#08b94e", "teal": "#00bfbc", "blue": "#086ddd", "purple": "#7852ee"]
            .sorted { first, second in first.key < second.key }.map { name, hex in PaletteColor(name: name, hex: hex) }

        func onBar(_ commands: LassoToolbarCommands) -> [String] { commands.items.filter { item in !item.isInMoreMenu }.map(\.title) }
        let wide = selection.selectionToolbarCommands(palette: palette)
        XCTAssertEqual(wide.items.filter { item in !item.isInMoreMenu && item.symbolColor != nil }.count, InkSelectionController.maximumSwatchesOnToolbar)
        XCTAssertEqual(wide.moreMenuElements.count, 1, "The colours left out are a palette in \"…\".")

        // An iPhone's width: fewer swatches, every command still on the bar.
        let phone = selection.selectionToolbarCommands(palette: palette, availableWidth: 386)
        XCTAssertLessThanOrEqual(InkSelectionController.width(of: phone), 386)
        XCTAssertEqual(onBar(phone).filter { title in ["Take Screenshot", "Cut", "Copy", "Duplicate", "Delete"].contains(title) },
                       ["Take Screenshot", "Cut", "Copy", "Duplicate", "Delete"])
        XCTAssertGreaterThan(phone.items.filter { item in !item.isInMoreMenu && item.symbolColor != nil }.count, 0)

        // Narrower still: no swatch, then Duplicate goes into "…", then Cut; Delete stays.
        let narrow = selection.selectionToolbarCommands(palette: palette, availableWidth: 300)
        XCTAssertLessThanOrEqual(InkSelectionController.width(of: narrow), 300)
        XCTAssertEqual(onBar(narrow), ["Take Screenshot", "Cut", "Copy", "Delete"])
        let narrowest = selection.selectionToolbarCommands(palette: palette, availableWidth: 250)
        XCTAssertLessThanOrEqual(InkSelectionController.width(of: narrowest), 250)
        XCTAssertEqual(onBar(narrowest), ["Take Screenshot", "Copy", "Delete"])
        XCTAssertEqual(narrowest.items.filter(\.isInMoreMenu).map(\.title), ["Cut", "Duplicate", "Smooth"])
    }

    func testOnAPDFPageSeveralPicturesAndATextBoxAreSentToTheBackAndBroughtToTheFrontFromTheBar() async throws {
        let session = try await openNotebook()
        session.undoManager.groupsByEvent = false
        let hosting = UIHostingController(rootView: AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let window = try window(showing: hosting)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await step(in: session) { try await session.addPicture(imageData: try imageData(color: .systemRed)) }
        let red = try XCTUnwrap(session.pictures(on: page).first?.name)
        try await step(in: session) { try await session.addPicture(imageData: try imageData(color: .systemBlue)) }
        let blue = try XCTUnwrap(session.pictures(on: page).map(\.name).first { name in name != red })
        let box = PDFTextBox(name: "box-1", runs: [PDFTextRun(text: "Over the pictures", attributes: .plain)], origin: CGPoint(x: 150, y: 320),
                             width: 120, height: 30, rotationRadians: 0, style: PDFTextBoxDefaults.original.boxStyle)
        try await step(in: session) { try session.changeTextBox(from: nil, to: box, on: session.historyPage(for: page), actionName: "Add Text Box") }
        session.selectedPicture = nil
        XCTAssertEqual(names(on: page), [red, blue, box.name])

        let canvas = try await editingCanvas(for: page, in: session)
        let boxIdentifier = PDFPageCanvasView.textBoxIdentifierPrefix + box.name
        let selection = canvas.inkSelection
        selection.select([], pictures: [red, boxIdentifier])
        let bar = try XCTUnwrap(selection.selectionToolbar.toolbar)
        XCTAssertTrue(bar.isShown)
        XCTAssertTrue(bar.superview is PDFView, "On a page the bar stands in the PDF view, at its size whatever the zoom.")
        let commands = selection.selectionToolbarCommands(palette: [])
        XCTAssertEqual(commands.items.filter { item in !item.isInMoreMenu }.map(\.title),
                       ["Take Screenshot", "Copy", "Bring Items to Front", "Send Items to Back", "Delete"])
        XCTAssertEqual(commands.items.filter(\.isInMoreMenu).map(\.title), ["Bring Items Forward", "Send Items Backward"])
        attachScreenshot(of: window, named: "The lasso's bar with two objects of a PDF page selected")

        // Send Items to Back, tapped on the bar: both under the blue picture, the red one still
        // under the box, as one step.
        let sendToBack = try XCTUnwrap(bar.buttons.first { button in button.accessibilityLabel == "Send Items to Back" })
        let center = sendToBack.convert(CGPoint(x: sendToBack.bounds.midX, y: sendToBack.bounds.midY), to: window)
        XCTAssertTrue(window.hitTest(center, with: nil) === sendToBack, "The PDF view gives the bar its touches.")
        await step(in: session) { sendToBack.sendActions(for: .primaryActionTriggered) }
        XCTAssertEqual(names(on: page), [red, box.name, blue])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Send Items to Back")
        let backAgain = try XCTUnwrap(selection.selectionToolbar.toolbar?.buttons.first { button in button.accessibilityLabel == "Send Items to Back" })
        XCTAssertFalse(backAgain.isEnabled, "Already at the back: dimmed.")

        await step(in: session) { selection.selectionToolbarCommands(palette: []).items.first { item in item.title == "Bring Items to Front" }?.action() }
        XCTAssertEqual(names(on: page), [blue, red, box.name])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Items to Front")

        // Every object of the page selected: nothing can move, and the commands stay, dimmed.
        selection.select([], pictures: [red, blue, boxIdentifier])
        let all = selection.selectionToolbarCommands(palette: [])
        let arranging = all.items.filter { item in item.title.hasPrefix("Bring Items") || item.title.hasPrefix("Send Items") }
        XCTAssertEqual(arranging.count, 4)
        XCTAssertTrue(arranging.allSatisfy { item in !item.isEnabled })
        XCTAssertNil(session.errorMessage)
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: A PDF page

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
        let location = try TemporaryVault.make(prefix: "LassoToolbar", for: self).root.appendingPathComponent("Notebook.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1).write(to: location)
        return try await PDFSession.open(location)
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
