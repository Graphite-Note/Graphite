/**
 * File: PencilWhileAnnotatingTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: What holds around a PDF being written on: the note around an embed waits for palm
 *              rejection and a hand on the embed as the Pencil writes leaves the note still, and Apple Pencil's
 *              double tap and squeeze are answered with the bar hidden.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// What holds around a PDF being written on: the note around an embed waits for palm rejection,
/// and Apple Pencil's double tap and squeeze are answered with the bar hidden.
@MainActor
final class PencilWhileAnnotatingTests: XCTestCase {
    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func hostedWindow(_ rootView: some View) throws -> (UIHostingController<AnyView>, UIWindow) {
        let controller = UIHostingController(rootView: AnyView(rootView))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    /// HUNT-016: with only the PDF's own scrolling waiting, a resting hand scrolled the note under
    /// the Pencil. The note's settings come back when annotating ends.
    func testTheNoteAroundAnEmbedWaitsForPalmRejectionWhileAnnotating() async throws {
        let location = try makeHostedBlankNotebook(named: "EmbedPalm")
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        let annotating = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        let reading = PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)
        let (controller, window) = try hostedWindow(ScrollView {
            GraphitePDFView(session: session, input: reading, isEmbedded: true).frame(height: 600)
            Color.clear.frame(height: 2_000)
        })
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF is shown") { session.pdfView?.window != nil }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        var ancestor = pdfView.superview
        var noteScrollView: UIScrollView?
        while let view = ancestor, noteScrollView == nil {
            noteScrollView = view as? UIScrollView
            ancestor = view.superview
        }
        let note = try XCTUnwrap(noteScrollView, "A scroll view around the embed in \(controller)")
        let touchTypesWhileReading = note.panGestureRecognizer.allowedTouchTypes
        XCTAssertFalse(coordinator.waitsForPalmRejection(note.panGestureRecognizer), "Reading leaves the note as it is")

        coordinator.update(input: annotating)
        XCTAssertTrue(coordinator.waitsForPalmRejection(note.panGestureRecognizer), "A resting hand does not scroll the note")
        XCTAssertFalse(note.panGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.pencil.rawValue)), "The Pencil writes")
        XCTAssertEqual(note.panGestureRecognizer.minimumNumberOfTouches, 1, "One finger still scrolls the note")

        // The wait ends at once when nothing is written: a finger scrolls the note as before.
        coordinator.update(input: reading)
        XCTAssertEqual(note.panGestureRecognizer.allowedTouchTypes, touchTypesWhileReading)
        XCTAssertFalse(PalmRejection.isHandResting(isPalmRejectionOn: true, isWriting: coordinator.isWriting, isPencilActive: true),
                       "Palm rejection takes no finger while reading, so what waits for it goes on")
    }

    /// HUNT-016 through UIKit's own touches: while a PDF embedded in a long note is annotated, a hand that touches it as
    /// the Pencil lifts (as a resting hand does between strokes) does not scroll the note; once the Pencil has been off
    /// the screen for a moment, one finger scrolls the note as before.
    func testAHandOnTheEmbedAsThePencilWritesLeavesTheNoteWhereItIs() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        XCTAssertTrue(SynthesizedTouches.canMakePencilTouches)
        let palmRejection = AppStorage(wrappedValue: true, PalmRejectionPreference.key)
        let palmRejectionBefore = palmRejection.wrappedValue
        palmRejection.wrappedValue = true
        defer { palmRejection.wrappedValue = palmRejectionBefore }
        let location = try makeHostedBlankNotebook(named: "EmbedHand")
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        let annotating = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        let reading = PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)
        let (_, window) = try hostedWindow(ScrollView {
            Color.clear.frame(height: 200)
            GraphitePDFView(session: session, input: reading, isEmbedded: true).frame(height: 600)
            Color.clear.frame(height: 2_000)
        })
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF is shown") { session.pdfView?.window != nil }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        var ancestor = pdfView.superview
        var noteScrollView: UIScrollView?
        while let view = ancestor, noteScrollView == nil {
            noteScrollView = view as? UIScrollView
            ancestor = view.superview
        }
        let note = try XCTUnwrap(noteScrollView)
        let pages = try XCTUnwrap(pdfView.pagesScrollView)
        // Writing is turned on with the embed on screen, as the embed's Write button does.
        coordinator.update(input: annotating)
        XCTAssertTrue(coordinator.waitsForPalmRejection(note.panGestureRecognizer))
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
        let offsetBefore = note.contentOffset
        let pagesOffsetBefore = pages.contentOffset

        // The Pencil writes a stroke, and the hand slides on the embed as the Pencil lifts.
        await SynthesizedTouches(window: window, touchType: .pencil).drag(from: CGPoint(x: middle.x - 60, y: middle.y),
                                                                          to: CGPoint(x: middle.x + 60, y: middle.y), steps: 10, holdSeconds: 0)
        await SynthesizedTouches(window: window).drag(from: CGPoint(x: middle.x, y: middle.y + 100), to: CGPoint(x: middle.x + 10, y: middle.y - 100),
                                                      steps: 12, holdSeconds: 0)
        XCTAssertEqual(note.contentOffset.y, offsetBefore.y, accuracy: 0.5, "The resting hand does not scroll the note.")
        XCTAssertEqual(pages.contentOffset.y, pagesOffsetBefore.y, accuracy: 0.5, "Nor the embed's pages.")

        // Off the screen for longer than palm rejection waits, one finger on the note beside the embed scrolls the note.
        try await waitUntil("the Pencil counts as lifted", timeoutSeconds: 3) {
            !PencilActivity.isActive(at: ProcessInfo.processInfo.systemUptime)
        }
        let belowEmbed = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.maxY + 150), to: window)
        await SynthesizedTouches(window: window).drag(from: belowEmbed, to: CGPoint(x: belowEmbed.x, y: belowEmbed.y - 250), steps: 12)
        try await waitUntil("one finger scrolls the note") { note.contentOffset.y > offsetBefore.y + 50 }
    }

    /// HUNT-025: double tap and squeeze were heard only by the bar, so hiding the bar silenced them.
    func testPencilGesturesAreAnsweredWithTheFixedBarHidden() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        // What the pane reads, the standard preferences, as `SynthesizedStrokes.letFingersDraw` sets them.
        let chosenStyle = AppStorage(wrappedValue: PencilToolbarStyle.floating, PencilToolbarStyle.preferenceKey)
        let showsTools = AppStorage(wrappedValue: true, PDFAnnotationPreferenceKey.showsToolPicker)
        let styleBefore = chosenStyle.wrappedValue, showsToolsBefore = showsTools.wrappedValue
        defer {
            chosenStyle.wrappedValue = styleBefore
            showsTools.wrappedValue = showsToolsBefore
        }
        chosenStyle.wrappedValue = .fixed
        showsTools.wrappedValue = false
        let location = try makeHostedBlankNotebook(named: "GesturesBarHidden")
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        session.isWriting = true
        let (controller, window) = try hostedWindow(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        defer { window.isHidden = true; window.rootViewController = nil }

        try await waitUntil("something answers the Pencil's gestures") {
            !self.descendants(of: controller.view, matching: PencilGestureReceiverView.self).isEmpty
        }
        let receivers = descendants(of: controller.view, matching: PencilGestureReceiverView.self)
        XCTAssertEqual(receivers.count, 1, "Once, with no bar on screen")
        let receiver = try XCTUnwrap(receivers.first)
        XCTAssertNotNil(receiver.window)
        XCTAssertFalse(receiver.interactions.filter { interaction in interaction is UIPencilInteraction }.isEmpty)

        let toolbox = PencilToolbox.shared
        let toolBefore = toolbox.toolInUse
        toolbox.use(.ink)
        defer { toolbox.use(toolBefore) }
        receiver.respond(.switchToEraser, at: ProcessInfo.processInfo.systemUptime, hoverLocation: nil)
        XCTAssertEqual(toolbox.toolInUse, .eraser, "The double tap or squeeze takes up the eraser")
        receiver.respond(.switchToEraser, at: ProcessInfo.processInfo.systemUptime + 1, hoverLocation: nil)
        XCTAssertNotEqual(toolbox.toolInUse, .eraser, "A second one goes back")

        // Reading is not writing: nothing there to switch.
        session.isWriting = false
        try await waitUntil("the receiver goes with writing") {
            self.descendants(of: controller.view, matching: PencilGestureReceiverView.self).isEmpty
        }
    }
}
#endif
