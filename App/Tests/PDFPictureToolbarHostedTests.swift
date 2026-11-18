/**
 * File: PDFPictureToolbarHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Hosted iPad tests of a selected picture on a PDF page: its floating toolbar shows when it is selected,
 *              beside it, with Bring Image to Front, Send Image to Back, Rotate Right, Crop and Delete (and Forward and
 *              Backward behind "…"), each one step; cropping offers Cancel Crop and Crop; the same commands are
 *              VoiceOver actions; two fingers turn and pinch the picture as one step, and a cancelled gesture leaves it.
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

@MainActor
final class PDFPictureToolbarHostedTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = try TemporaryVault.make(prefix: "PDFPictureMenu", for: self).root
    }

    private func makePDF() throws -> URL {
        let location = directory.appendingPathComponent("Worksheet.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return location
    }

    private func pngData(color: UIColor = .systemTeal) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        return try XCTUnwrap(image.pngData())
    }

    /// The PDF in a window, as a pane shows it, with one picture selected and its frame shown.
    private func showWithSelectedPicture(pictureCount: Int = 1) async throws
        -> (session: PDFSession, controller: PDFPictureSelectionController, frame: SelectionFrameView) {
        let session = try await PDFSession.open(try makePDF())
        for index in 0..<pictureCount {
            try await session.addPicture(imageData: try pngData(color: index == 0 ? .systemTeal : .systemOrange),
                                         placement: (pageIndex: 0, center: CGPoint(x: 200 + CGFloat(index) * 30, y: 300)))
        }
        let input = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        let hosting = UIHostingController(rootView: GraphitePDFView(session: session, input: input))
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 1_000)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        addTeardownBlock { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let view = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let controller = try XCTUnwrap(view.annotationCoordinator?.pictureSelectionController)
        try await waitUntil("the picture's frame shows") {
            controller.update()
            return controller.selectionView?.superview === view && (controller.selectionView?.bounds.width ?? 0) > 0
        }
        return (session, controller, try XCTUnwrap(controller.selectionView))
    }

    private func picture(of session: PDFSession) throws -> PDFPicture {
        let selection = try XCTUnwrap(session.selectedPicture)
        let page = try XCTUnwrap(selection.page.page)
        return try XCTUnwrap(session.pictures(on: page).first { picture in picture.name == selection.pictureName })
    }

    func testASelectedPicturesToolbarFloatsBesideItWithItsCommands() async throws {
        let (session, controller, frame) = try await showWithSelectedPicture(pictureCount: 2)
        let toolbar = try XCTUnwrap(controller.toolbar)
        try await waitUntil("the toolbar shows when the picture is selected") { toolbar.isShown }
        let bar = try XCTUnwrap(toolbar.toolbar)
        let pdfView = try XCTUnwrap(frame.superview)
        XCTAssertTrue(bar.superview === pdfView, "The bar is in the PDF view, which is not zoomed, so it keeps its size.")

        // On the bar: the order, the picture's own commands, Delete in red, and "…" for the rest. No ink commands.
        XCTAssertEqual(bar.buttons.map(\.accessibilityLabel), ["Bring Image to Front", "Send Image to Back", "Rotate Right", "Crop", "Delete Image"])
        let more = try XCTUnwrap(bar.moreButton)
        XCTAssertEqual(more.menu?.children.map(\.title), ["Bring Image Forward", "Send Image Backward"])
        XCTAssertEqual(bar.buttons.last?.configuration?.baseForegroundColor, .systemRed)
        XCTAssertFalse(toolbar.items().contains { item in item.title.contains("Ink") })
        // The second picture, the one selected, is on top of the first: it can only go back.
        XCTAssertEqual(toolbar.items().filter { item in !item.isEnabled }.map(\.title), ["Bring Image to Front", "Bring Image Forward"])
        XCTAssertFalse(bar.buttons[0].isEnabled)
        // The bar stands clear of the picture and its handles, inside what the PDF view shows.
        XCTAssertFalse(bar.frame.intersects(frame.boxWithHandlesInSuperview))
        XCTAssertTrue(pdfView.bounds.inset(by: pdfView.safeAreaInsets).contains(bar.frame))
        // A touch on each button reaches it, not the page's canvas under the bar (which ended arranging before).
        for button in bar.buttons + [more] {
            let touched = pdfView.hitTest(button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: pdfView), with: nil)
            // A dimmed button lets its touch fall to the bar behind it, which does nothing; never to the page.
            let reached = button.isEnabled ? button : bar
            XCTAssertTrue(touched.map { view in view === reached || view.isDescendant(of: reached) } ?? false, "\(button.accessibilityLabel ?? "") gets its touch, not \(String(describing: touched))")
        }

        // VoiceOver offers what can be done, as actions of the selected image.
        let actionNames = frame.accessibilityCustomActions?.map(\.name) ?? []
        for title in ["Send Image to Back", "Send Image Backward", "Rotate Right", "Crop", "Delete Image"] { XCTAssertTrue(actionNames.contains(title), "\(title) in \(actionNames)") }
        XCTAssertFalse(actionNames.contains("Bring Image to Front"))

        // A tap on the selected picture hides its toolbar, another shows it again. The page's
        // own tap leaves touches on the frame alone, so the frame's tap does it; a tap on a
        // handle does not.
        let tappedFrame = try XCTUnwrap(controller.selectionView)
        XCTAssertTrue(tappedFrame.gestureRecognizers?.contains(tappedFrame.bodyTapRecognizer) ?? false, "The frame takes taps.")
        let middle = CGPoint(x: tappedFrame.bounds.midX, y: tappedFrame.bounds.midY)
        tappedFrame.bodyWasTapped(at: middle)
        XCTAssertFalse(toolbar.isShown)
        tappedFrame.bodyWasTapped(at: CGPoint(x: tappedFrame.bounds.minX, y: tappedFrame.bounds.minY))
        XCTAssertFalse(toolbar.isShown, "A tap on a corner handle leaves the bar as it is.")
        tappedFrame.bodyWasTapped(at: middle)
        XCTAssertTrue(toolbar.isShown)

        // Send Image to Back, pressed on the bar, is one step and leaves the bar on the picture.
        let selectedName = try picture(of: session).name
        bar.buttons[1].sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(session.undoManager.undoActionName, "Send to Back")
        let page = try XCTUnwrap(session.document.page(at: 0))
        XCTAssertEqual(session.pictures(on: page).first?.name, selectedName, "The selected picture is now under the other.")
        try await waitUntil("the bar is back with Bring Image to Front enabled") { toolbar.isShown && (toolbar.toolbar?.buttons.first?.isEnabled ?? false) }

        // VoiceOver's actions follow the change, and one run as VoiceOver runs it is one step too.
        // (The simulator has no VoiceOver: this is the action VoiceOver's rotor would perform.)
        XCTAssertTrue(frame.isAccessibilityElement)
        XCTAssertEqual(frame.accessibilityLabel, "Selected image")
        let bringToFront = try XCTUnwrap(frame.accessibilityCustomActions?.first { action in action.name == "Bring Image to Front" },
                                         "Bring Image to Front is an action once the image is under the other.")
        XCTAssertFalse(frame.accessibilityCustomActions?.contains { action in action.name == "Send Image to Back" } ?? true)
        XCTAssertTrue(bringToFront.actionHandler?(bringToFront) ?? false)
        XCTAssertEqual(session.undoManager.undoActionName, "Bring to Front")
        XCTAssertEqual(session.pictures(on: page).last?.name, selectedName, "The selected picture is on top again.")
    }

    func testRotateCropAndDeleteFromTheToolbarAreOneStepEach() async throws {
        let (session, controller, _) = try await showWithSelectedPicture()
        let toolbar = try XCTUnwrap(controller.toolbar)
        let before = try picture(of: session)
        func press(_ title: String) throws { try XCTUnwrap(toolbar.items().first { item in item.title == title }, title).action() }

        try press("Rotate Right")
        XCTAssertEqual(session.undoManager.undoActionName, "Rotate Image Right")
        XCTAssertEqual(((try picture(of: session).quarterTurns) % 4 + 4) % 4, ((before.quarterTurns - 1) % 4 + 4) % 4, "A quarter turn clockwise.")
        // The bar comes back centred under the turned picture, not under where its handles were
        // before the turn (on the simulator it stood 27 points to the right of a tall picture).
        try await waitUntil("the bar is back after the turn") { toolbar.isShown }
        let turnedFrame = try XCTUnwrap(controller.selectionView)
        let bar = try XCTUnwrap(toolbar.toolbar)
        XCTAssertEqual(bar.frame.midX, turnedFrame.frame.midX, accuracy: 1, "The bar is centred on the turned picture.")
        XCTAssertFalse(bar.frame.intersects(turnedFrame.boxWithHandlesInSuperview))
        session.undoManager.undo()
        XCTAssertEqual(try picture(of: session), before)

        try press("Crop")
        XCTAssertEqual(session.pictureCrop, before.bounds, "The crop starts as the whole picture.")
        XCTAssertEqual(toolbar.items().map(\.title), ["Cancel Crop", "Crop"])
        try await waitUntil("the bar offers Cancel Crop and Crop") { toolbar.toolbar?.buttons.map(\.accessibilityLabel) == ["Cancel Crop", "Crop"] }
        try press("Cancel Crop")
        XCTAssertNil(session.pictureCrop)

        try press("Delete Image")
        XCTAssertNil(session.selectedPicture)
        XCTAssertTrue(session.pictures(on: try XCTUnwrap(session.document.page(at: 0))).isEmpty)
        XCTAssertEqual(session.undoManager.undoActionName, "Delete Image")
        try await waitUntil("the bar goes with the selection") { controller.update(); return !toolbar.isShown && controller.selectionView == nil }
    }

    func testTwoFingersTurnAndPinchThePictureAsOneStep() async throws {
        let (session, controller, frame) = try await showWithSelectedPicture()
        let gesture = try XCTUnwrap(controller.twoFingerGesture)
        XCTAssertTrue(frame.gestureRecognizers?.contains(gesture.pinchRecognizer) ?? false)
        XCTAssertTrue(frame.gestureRecognizers?.contains(gesture.twistRecognizer) ?? false)
        // The frame lies over the PDF view's scroll view, not in it, so the page's pinch never sees these fingers.
        let pdfView = try XCTUnwrap(frame.superview as? PDFView)
        let scrollViews = pdfView.subviews.compactMap { view in view as? UIScrollView } + pdfView.subviews.flatMap { view in view.subviews.compactMap { subview in subview as? UIScrollView } }
        XCTAssertFalse(scrollViews.isEmpty)
        XCTAssertFalse(scrollViews.contains { scrollView in frame.isDescendant(of: scrollView) })
        let before = try picture(of: session)

        // Fingers about the picture's middle, spread to twice as far apart and turned 30° clockwise.
        let middle = CGPoint(x: frame.center.x, y: frame.center.y)
        let widthOnScreen = frame.unrotatedFrame.width
        gesture.begin(fingersMiddle: middle)
        XCTAssertFalse(controller.toolbar?.isShown ?? true, "The toolbar hides while the fingers move the picture.")
        gesture.change(fingersMiddle: middle, scale: 1.5, turn: .pi / 12)
        gesture.change(fingersMiddle: middle, scale: 2, turn: .pi / 6)
        XCTAssertEqual(frame.rotation, .pi / 6, accuracy: 0.0001)
        XCTAssertEqual(frame.unrotatedFrame.width, widthOnScreen * 2, accuracy: 0.01)
        XCTAssertEqual(try picture(of: session), before, "The picture changes when the fingers lift.")
        gesture.end()

        let after = try picture(of: session)
        XCTAssertEqual(after.bounds.width, before.bounds.width * 2, accuracy: 0.5)
        XCTAssertEqual(after.bounds.height, before.bounds.height * 2, accuracy: 0.5)
        XCTAssertEqual(after.bounds.midX, before.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(after.bounds.midY, before.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(abs(after.rotationRadians), .pi / 6, accuracy: 0.0001)
        XCTAssertEqual(session.undoManager.undoActionName, "Rotate Image")
        session.undoManager.undo()
        XCTAssertEqual(try picture(of: session), before, "One undo puts back the whole gesture.")
        try await waitUntil("the toolbar comes back") { controller.toolbar?.isShown == true }

        // A pinch with no turn, moved down: a resize, named so.
        gesture.begin(fingersMiddle: middle)
        gesture.change(fingersMiddle: CGPoint(x: middle.x, y: middle.y + 40), scale: 0.5, turn: 0)
        gesture.end()
        XCTAssertEqual(session.undoManager.undoActionName, "Resize Image")
        XCTAssertEqual(try picture(of: session).bounds.width, before.bounds.width / 2, accuracy: 0.5)
        XCTAssertLessThan(try picture(of: session).bounds.midY, before.bounds.midY, "Moved down on screen is down the page.")
        session.undoManager.undo()

        // A cancelled gesture leaves the frame and the picture as they were.
        let frameBefore = frame.unrotatedFrame
        gesture.begin(fingersMiddle: middle)
        gesture.change(fingersMiddle: middle, scale: 1.8, turn: 1)
        gesture.cancel()
        XCTAssertEqual(frame.rotation, 0)
        XCTAssertEqual(frame.unrotatedFrame.width, frameBefore.width, accuracy: 0.01)
        XCTAssertEqual(try picture(of: session), before)
    }
}
#endif
