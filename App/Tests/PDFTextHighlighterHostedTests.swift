/**
 * File: PDFTextHighlighterHostedTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The fixed bar's text highlighter on a PDF page in the hosted app: a drag over the text, of a finger
 *              where fingers draw or of touches typed as Apple Pencil's, marks it once in the chosen style as one undo
 *              step, shown in the style's colour as it is covered, a finger's long press marks it on lift, no ink is
 *              drawn, and the eraser removes a mark it passes over.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
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

/// The fixed bar's text highlighter on a PDF page with a line of text. Finger touches go through UIKit
/// (`SynthesizedTouches`), so the page's own recognizers take them: with finger drawing on, a finger drags as the Pencil
/// does (the tool's drag recognizer takes the Pencil always and a finger only then, `TextHighlighterToolController`);
/// with it off, a finger's long press selects. UIKit gives no way to send a Pencil's touches through the window, so the
/// Pencil's part is checked by giving PencilKit's own drawing recognizer a Pencil stroke, which draws nothing while the
/// tool is chosen.
@MainActor
final class PDFTextHighlighterHostedTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []
    private var restoreDevicePreferences: [() -> Void] = []
    private var toolBeforeTest: (kind: PencilToolKind, presetIndex: Int)?

    private static let pageText = "Graphite marks this sentence"

    override func setUp() async throws {
        // Touches are what these tests are about: without them they fail rather than pass unseen.
        if let reason = SynthesizedTouches.unavailableReason { throw TouchesUnavailable(reason: reason) }
        // A finger landing within moments of a Pencil test's last touch is a hand resting while the Pencil writes.
        PencilActivity.forgetPencil()
        try await waitUntil("the last test's Pencil is no longer active") { !PencilActivity.isActive(at: PencilActivity.now) }
        restoreDevicePreferences.append(HostedDevicePreferences.saving([PDFAnnotationPreferenceKey.markupStyle, PencilToolbox.storageKey]))
        restoreDevicePreferences.append(HostedDevicePreferences.set(false, forKey: PDFAnnotationPreferenceKey.drawsWithFinger))
        restoreDevicePreferences.append(HostedDevicePreferences.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey))
        let toolbox = PencilToolbox.shared
        toolBeforeTest = (toolbox.toolInUse, toolbox.presetInUseIndex)
        PencilActivity.forgetPencil()
    }

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) } // best-effort cleanup of the test's own files
        locations = []
        if let toolBeforeTest {
            if toolBeforeTest.kind == .ink { PencilToolbox.shared.usePreset(at: toolBeforeTest.presetIndex) } else { PencilToolbox.shared.use(toolBeforeTest.kind) }
        }
        for restore in restoreDevicePreferences.reversed() { restore() }
        restoreDevicePreferences = []
    }

    /// With finger drawing on, a finger dragged over the line with the text highlighter chosen marks it once, in the
    /// colour chosen beside the tool, when it lifts: one annotation, one undo step, no ink, the selection cleared.
    func testADragWithTheTextHighlighterMarksTheTextOnceAndDrawsNoInk() async throws {
        restoreDevicePreferences.append(SynthesizedStrokes.letFingersDraw())
        restoreDevicePreferences.append(HostedDevicePreferences.set(PDFMarkupStyle.highlight(.green).rawValue, forKey: PDFAnnotationPreferenceKey.markupStyle))
        let fixture = try await openTextPDF()
        let canvas = try await canvasMarkingText(in: fixture)
        XCTAssertFalse(canvas.isDrawingEnabled, "PencilKit draws nothing while the text highlighter is chosen.")

        let (start, end) = try lineEnds(in: fixture)
        await SynthesizedTouches(window: fixture.window).drag(from: start, to: end, steps: 24, holdSeconds: 0.1)

        try await waitUntil("the line is marked") { !self.marks(on: fixture.page).isEmpty }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        let marks = marks(on: fixture.page)
        XCTAssertEqual(marks.count, 1, "One mark for one drag.")
        XCTAssertEqual(marks.first?.kind, .highlight)
        XCTAssertEqual(marks.first?.color, .green)
        XCTAssertTrue(canvas.drawing.strokes.isEmpty, "The drag drew no stroke.")
        XCTAssertTrue(fixture.page.annotations.filter { annotation in annotation.type == "Ink" }.isEmpty)
        XCTAssertTrue((fixture.pdfView.currentSelection?.string ?? "").isEmpty, "The marked text is no longer selected.")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, PDFMarkupKind.highlight.title)
        attachScreenshot(of: fixture.window, named: "A line marked with the text highlighter")

        fixture.session.undoAvailability.undo()
        try await waitUntil("undo takes the mark away") { self.marks(on: fixture.page).isEmpty }
        fixture.session.undoAvailability.redo()
        try await waitUntil("redo puts it back") { self.marks(on: fixture.page).count == 1 }
        XCTAssertNil(fixture.session.errorMessage)
    }

    /// With finger drawing off, as on the owner's iPad, Apple Pencil dragged over the line with the text highlighter
    /// chosen marks it once when it lifts, with no ink. The touches report the Pencil's type, so every recognizer that
    /// filters by type (the page's scrolling, PDFKit's, PencilKit's, the tool's own) treats them as the screen's Pencil
    /// touches: a finger's drag would scroll here instead.
    func testAPencilDragWithTheTextHighlighterMarksTheTextOnce() async throws {
        guard SynthesizedTouches.canMakePencilTouches else { throw TouchesUnavailable(reason: "UIKit's setter of a touch's type was not found") }
        let fixture = try await openTextPDF()
        let canvas = try await canvasMarkingText(in: fixture)
        XCTAssertNotEqual(canvas.drawingPolicy, .anyInput, "Fingers do not draw, so only the Pencil can mark by dragging.")

        let (start, end) = try lineEnds(in: fixture)
        await SynthesizedTouches(window: fixture.window, touchType: .pencil).drag(from: start, to: end, steps: 24, holdSeconds: 0.1)

        try await waitUntil("the line is marked") { !self.marks(on: fixture.page).isEmpty }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        XCTAssertEqual(marks(on: fixture.page).count, 1, "One mark for one drag.")
        XCTAssertTrue(canvas.drawing.strokes.isEmpty, "The drag drew no stroke.")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, PDFMarkupKind.highlight.title)
        fixture.session.undoAvailability.undo()
        try await waitUntil("one undo takes the mark away") { self.marks(on: fixture.page).isEmpty }
    }

    /// While the Pencil drags, the text it has covered shows in the style's colour, before it lifts: PDFKit drew nothing
    /// for a selection set during the drag, so the owner saw the mark only after lifting (2026-11-17). It is Graphite's
    /// own layer, not PDFKit's highlighted selections, which left a frame without fill at each move and are read aloud's.
    func testThePencilsDragShowsTheTextCoveredInTheStylesColourBeforeItLifts() async throws {
        guard SynthesizedTouches.canMakePencilTouches else { throw TouchesUnavailable(reason: "UIKit's setter of a touch's type was not found") }
        restoreDevicePreferences.append(HostedDevicePreferences.set(PDFMarkupStyle.highlight(.green).rawValue, forKey: PDFAnnotationPreferenceKey.markupStyle))
        let fixture = try await openTextPDF()
        _ = try await canvasMarkingText(in: fixture)
        let (start, end) = try lineEnds(in: fixture)
        let middle = CGPoint(x: (start.x + end.x) / 2, y: start.y)

        let touches = SynthesizedTouches(window: fixture.window, touchType: .pencil)
        touches.begin(at: [start])
        await touches.slide(to: [middle], steps: 12)
        try await waitUntil("the text covered shows") { self.coveredText(in: fixture.pdfView) != nil }
        let shownHalfway = try XCTUnwrap(coveredText(in: fixture.pdfView))
        let selectedHalfway = try XCTUnwrap(fixture.pdfView.currentSelection?.string)
        XCTAssertTrue(marks(on: fixture.page).isEmpty, "Nothing is marked before the lift.")
        XCTAssertTrue(Self.pageText.hasPrefix(selectedHalfway), "The text from the first word to the Pencil is selected.")
        XCTAssertLessThan(selectedHalfway.count, Self.pageText.count)
        XCTAssertEqual(shownHalfway.fillColor, PDFTextHighlighterInteraction.colorWhileSelecting(for: .highlight(.green)).cgColor)
        let lineInWindow = (start.x - 4)...(end.x + 4)
        let shownHalfwayInWindow = fixture.pdfView.convert(try XCTUnwrap(shownHalfway.path).boundingBox, to: fixture.window)
        XCTAssertEqual(shownHalfwayInWindow.minX, lineInWindow.lowerBound, accuracy: 6, "It shows from the line's start.")
        XCTAssertLessThan(shownHalfwayInWindow.maxX, end.x - 20, "Only as far as the Pencil.")
        XCTAssertNil(fixture.pdfView.highlightedSelections, "PDFKit's highlighted selections are left to read aloud.")
        await touches.slide(to: [end], steps: 12)
        XCTAssertEqual(fixture.pdfView.currentSelection?.string, Self.pageText, "It grows with the drag.")
        let shownAtTheEnd = fixture.pdfView.convert(try XCTUnwrap(coveredText(in: fixture.pdfView)?.path).boundingBox, to: fixture.window)
        XCTAssertGreaterThan(shownAtTheEnd.maxX, end.x - 4, "And shows to the line's end.")
        touches.end()

        try await waitUntil("the line is marked") { !self.marks(on: fixture.page).isEmpty }
        XCTAssertNotNil(coveredText(in: fixture.pdfView), "The text covered stays over the mark until PDFKit has drawn it.")
        try await waitUntil("only the mark shows once lifted") { self.coveredText(in: fixture.pdfView) == nil }
    }

    /// A drag whose first move goes far at once, as a quick Pencil's or a finger's can, still selects from the word where
    /// it landed: the pan begins only once the touch has moved and its translation leaves out the first points of the
    /// move, so a finger landing on a line's first word selected from the next one in an iPad simulator (2026-11-17).
    func testADragWhoseFirstMoveGoesFarSelectsFromTheWordWhereItLanded() async throws {
        guard SynthesizedTouches.canMakePencilTouches else { throw TouchesUnavailable(reason: "UIKit's setter of a touch's type was not found") }
        let fixture = try await openTextPDF()
        _ = try await canvasMarkingText(in: fixture)
        let (start, end) = try lineEnds(in: fixture)

        let touches = SynthesizedTouches(window: fixture.window, touchType: .pencil)
        touches.begin(at: [start])
        await touches.slide(to: [CGPoint(x: (start.x + end.x) / 2, y: start.y)], steps: 1)
        await touches.slide(to: [end], steps: 4)
        touches.end()

        try await waitUntil("the line is marked") { !self.marks(on: fixture.page).isEmpty }
        let markedText = try XCTUnwrap(markedStrings(on: fixture.page).first)
        XCTAssertEqual(markedText, Self.pageText, "From the first word, where the Pencil landed, to the last.")
    }

    /// The layer showing the text covered while the touch is down, when it shows any.
    private func coveredText(in pdfView: PDFView) -> CAShapeLayer? {
        let layer = pdfView.layer.sublayers?.first { $0.name == PDFTextHighlighterInteraction.coveredTextLayerName } as? CAShapeLayer
        return layer?.path == nil ? nil : layer
    }

    /// The eraser, dragged by the Pencil over a highlight, removes it, and one Undo puts it back: the owner found no way
    /// to erase a mark (2026-11-17).
    func testThePencilsEraserRemovesAHighlightItPassesOverAsOneStep() async throws {
        guard SynthesizedTouches.canMakePencilTouches else { throw TouchesUnavailable(reason: "UIKit's setter of a touch's type was not found") }
        let fixture = try await openTextPDF()
        _ = try await canvasMarkingText(in: fixture)
        let (start, end) = try lineEnds(in: fixture)
        await SynthesizedTouches(window: fixture.window, touchType: .pencil).drag(from: start, to: end, steps: 24, holdSeconds: 0.1)
        try await waitUntil("the line is marked") { self.marks(on: fixture.page).count == 1 }

        PencilToolbox.shared.use(.eraser)
        let canvas = try XCTUnwrap(try editingCanvas(in: fixture))
        try await waitUntil("the canvas erases") { canvas.chosenTool is PKEraserTool }
        let across = CGPoint(x: (start.x + end.x) / 2, y: start.y)
        await SynthesizedTouches(window: fixture.window, touchType: .pencil)
            .drag(from: CGPoint(x: across.x, y: across.y - 40), to: CGPoint(x: across.x, y: across.y + 40), steps: 12, holdSeconds: 0.05)

        try await waitUntil("the highlight is erased") { self.marks(on: fixture.page).isEmpty }
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Remove \(PDFMarkupKind.highlight.title)")
        fixture.session.undoAvailability.undo()
        try await waitUntil("one undo puts it back") { self.marks(on: fixture.page).count == 1 }
        XCTAssertTrue(fixture.page.annotations.allSatisfy(\.shouldDisplay), "The mark put back shows.")
    }

    /// The Pencil rested on the first word before it moves, as a hand often does, still marks the line once: no long
    /// press of PDFKit's, PencilKit's or the page's takes the touch from the tool while it is still.
    func testAPencilHeldStillBeforeItsDragStillMarksTheTextOnce() async throws {
        guard SynthesizedTouches.canMakePencilTouches else { throw TouchesUnavailable(reason: "UIKit's setter of a touch's type was not found") }
        let fixture = try await openTextPDF()
        let canvas = try await canvasMarkingText(in: fixture)

        let (start, end) = try lineEnds(in: fixture)
        let touches = SynthesizedTouches(window: fixture.window, touchType: .pencil)
        touches.begin(at: [start])
        await touches.hold(seconds: 0.8)
        await touches.slide(to: [end], steps: 24)
        await touches.hold(seconds: 0.1)
        touches.end()

        try await waitUntil("the line is marked") { !self.marks(on: fixture.page).isEmpty }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        XCTAssertEqual(marks(on: fixture.page).count, 1, "One mark for one drag.")
        XCTAssertTrue(canvas.drawing.strokes.isEmpty, "The drag drew no stroke.")
        XCTAssertNil(fixture.pdfView.window?.rootViewController?.presentedViewController, "No menu or sheet opened.")
    }

    /// With finger drawing off, fingers scroll; a finger's long press then drag selects the line, and with the text
    /// highlighter chosen lifting marks it in the style chosen, here Underline, instead of showing the menu.
    func testAFingersLongPressWithTheTextHighlighterMarksTheSelectionOnLift() async throws {
        restoreDevicePreferences.append(HostedDevicePreferences.set(PDFMarkupStyle.underline.rawValue, forKey: PDFAnnotationPreferenceKey.markupStyle))
        let fixture = try await openTextPDF()
        _ = try await canvasMarkingText(in: fixture)

        try await longPressAndDrag(across: fixture)

        try await waitUntil("the line is underlined") { !self.marks(on: fixture.page).isEmpty }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        XCTAssertEqual(marks(on: fixture.page).map(\.kind), [.underline])
        XCTAssertEqual(fixture.session.undoManager.undoActionName, PDFMarkupKind.underline.title)
    }

    /// Without the text highlighter, the same long press leaves the text selected and unmarked, for the selection menu.
    func testWithAPenTheLongPressLeavesTheSelectionForTheMenu() async throws {
        let fixture = try await openTextPDF()
        PencilToolbox.shared.usePreset(at: 0)
        let canvas = try XCTUnwrap(try editingCanvas(in: fixture))
        try await waitUntil("the canvas draws") { !canvas.marksText && canvas.isDrawingEnabled }

        try await longPressAndDrag(across: fixture)

        try await waitUntil("the line is selected") { !(fixture.pdfView.currentSelection?.string ?? "").isEmpty }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        XCTAssertTrue(marks(on: fixture.page).isEmpty, "Only the menu marks text selected with a pen chosen.")
    }

    /// A Pencil stroke given to PencilKit's own drawing recognizer draws nothing while the text highlighter is chosen,
    /// and draws once a pen is chosen again: no ink is drawn while the tool marks text.
    func testAPencilStrokeDrawsNoInkWhileTheTextHighlighterIsChosen() async throws {
        let fixture = try await openTextPDF()
        let canvas = try await canvasMarkingText(in: fixture)
        let (start, end) = try lineEnds(in: fixture)

        let strokeWithTheTool = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: start, to: end),
                                                                  in: fixture.window, touchType: .pencil)
        XCTAssertNil(strokeWithTheTool)
        XCTAssertTrue(canvas.drawing.strokes.isEmpty)

        PencilToolbox.shared.usePreset(at: 0)
        try await waitUntil("the canvas draws again") { !canvas.marksText && canvas.isDrawingEnabled }
        let strokeWithAPen = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: start, to: end),
                                                               in: fixture.window, touchType: .pencil)
        XCTAssertNotNil(strokeWithAPen, "The same stroke draws with a pen, so the one before was held back by the tool.")
        XCTAssertTrue(marks(on: fixture.page).isEmpty)
    }

    /// The "+" beside the text highlighter opens the system colour picker; the colour picked is saved with the text-mark
    /// colours, shows as one more dot, and becomes the highlighter's style.
    func testThePlusBesideTheToolSavesAPickedColourAndMarksWithIt() async throws {
        restoreDevicePreferences.append(HostedDevicePreferences.saving([PDFAnnotationPreferenceKey.textMarkColors]))
        HostedDevicePreferences.remove(forKey: PDFAnnotationPreferenceKey.textMarkColors)
        let fixture = try await openTextPDF()
        _ = try await canvasMarkingText(in: fixture)
        try await waitForTheBarToSettle()
        // SwiftUI's buttons take no touches sent through UIKit's event path, so the "+" is pressed as VoiceOver does.
        try PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(true)
        defer { try? PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(false) } // Off again if the test stops early.
        var plus: NSObject?
        try await waitUntil("the bar shows the plus beside the highlighter's colours") {
            plus = PencilBarPlacementHostedTests.accessibilityElements(in: fixture.window).first { element in
                element.accessibilityLabel == "Add Highlight Color"
            }
            return plus != nil
        }
        XCTAssertTrue(try XCTUnwrap(plus).accessibilityActivate())
        // Turned off at once: left on, it changes how the page's touches are delivered, and slows the tests after.
        try PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(false)

        var picker: UIColorPickerViewController?
        try await waitUntil("the colour picker is shown") {
            picker = fixture.window.rootViewController?.presentedViewController as? UIColorPickerViewController
            // Shown and done appearing: a tap outside a popover still appearing does not close it.
            return picker != nil && picker?.isBeingPresented == false
        }
        let shownPicker = try XCTUnwrap(picker)
        let orange = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: orange, continuously: false)
        // Closed as a person closes the popover, which has no close button: a tap outside it.
        let outside = CGPoint(x: 40, y: fixture.window.bounds.maxY - 60)
        let tap = SynthesizedTouches(window: fixture.window)
        tap.begin(at: [outside])
        await tap.hold(seconds: 0.05)
        tap.end()
        try await waitUntil("the colour picker is gone") { fixture.window.rootViewController?.presentedViewController == nil }

        let pickedColor = PDFMarkupColor(platformColor: orange)
        let saved = PDFTextMarkColors(decoding: HostedDevicePreferences.value(forKey: PDFAnnotationPreferenceKey.textMarkColors) as? Data)
        XCTAssertEqual(saved.colors, PDFMarkupColor.highlightColors + [pickedColor], "The colour picked is saved after the standard ones.")
        let storedStyle = HostedDevicePreferences.value(forKey: PDFAnnotationPreferenceKey.markupStyle) as? String
        XCTAssertEqual(storedStyle.flatMap(PDFMarkupStyle.init(rawValue:)), .highlight(pickedColor))

        let (start, end) = try lineEnds(in: fixture)
        restoreDevicePreferences.append(SynthesizedStrokes.letFingersDraw())
        try await waitUntil("fingers draw") { (try? self.editingCanvas(in: fixture))?.drawingPolicy == .anyInput }
        await SynthesizedTouches(window: fixture.window).drag(from: start, to: end, steps: 24, holdSeconds: 0.1)
        try await waitUntil("the line is marked") { !self.marks(on: fixture.page).isEmpty }
        XCTAssertEqual(marks(on: fixture.page).map(\.color.hex), [pickedColor.hex], "Marked once, in the colour picked.")
        attachScreenshot(of: fixture.window, named: "A colour added with the plus beside the text highlighter")
    }

    /// The tool's drag takes Apple Pencil always, a finger only where fingers draw, and never a pointer.
    func testTheToolTakesThePencilAndAFingerOnlyWhereFingersDraw() {
        XCTAssertTrue(TextHighlighterToolController.takesTouch(ofType: .pencil, fingersDraw: false))
        XCTAssertTrue(TextHighlighterToolController.takesTouch(ofType: .direct, fingersDraw: true))
        XCTAssertFalse(TextHighlighterToolController.takesTouch(ofType: .direct, fingersDraw: false), "A finger scrolls; its long press selects.")
        XCTAssertFalse(TextHighlighterToolController.takesTouch(ofType: .indirectPointer, fingersDraw: true))
    }

    // MARK: Fixture

    private struct TouchesUnavailable: Error {
        let reason: String
    }

    private struct Fixture {
        let session: PDFSession
        let window: UIWindow
        let pdfView: PDFView
        let page: PDFPage
    }

    /// A one-page PDF with `pageText` in large type, open for writing in a PDF pane with the fixed bar.
    private func openTextPDF() async throws -> Fixture {
        let location = hostedTemporaryLocation(named: "TextHighlighter").appendingPathExtension("pdf")
        locations.append(location)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdfData = UIGraphicsPDFRenderer(bounds: pageBounds).pdfData { context in
            context.beginPage()
            NSAttributedString(string: Self.pageText, attributes: [.font: UIFont.systemFont(ofSize: 30)]).draw(at: CGPoint(x: 60, y: 140))
        }
        try pdfData.write(to: location)
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        session.isWriting = true
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the PDF view shows the page") { session.pdfView?.window != nil }
        let pdfView = try XCTUnwrap(session.pdfView)
        let fixture = Fixture(session: session, window: window, pdfView: pdfView, page: page)
        try await waitUntil("the page's canvas edits it") { (try? self.editingCanvas(in: fixture)) != nil }
        return fixture
    }

    private func editingCanvas(in fixture: Fixture) throws -> PDFPageCanvasView? {
        (fixture.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator?.editingCanvas(for: fixture.page)
    }

    /// Chooses the text highlighter on the bar's toolbox and waits for the page's canvas to take it.
    private func canvasMarkingText(in fixture: Fixture) async throws -> PDFPageCanvasView {
        PencilToolbox.shared.use(.textHighlighter)
        let canvas = try XCTUnwrap(try editingCanvas(in: fixture))
        try await waitUntil("the canvas marks text") { canvas.marksText && !canvas.isDrawingEnabled }
        return canvas
    }

    /// The window points just inside the line's first and last letters, at the middle of its height.
    private func lineEnds(in fixture: Fixture) throws -> (start: CGPoint, end: CGPoint) {
        let text = try XCTUnwrap(fixture.page.string)
        let lineRange = (text as NSString).range(of: Self.pageText)
        XCTAssertNotEqual(lineRange.location, NSNotFound, "The page's text is readable.")
        let lineSelection = try XCTUnwrap(fixture.page.selection(for: lineRange))
        let lineInView = fixture.pdfView.convert(lineSelection.bounds(for: fixture.page), from: fixture.page)
        let lineInWindow = fixture.pdfView.convert(lineInView, to: fixture.window)
        return (CGPoint(x: lineInWindow.minX + 4, y: lineInWindow.midY), CGPoint(x: lineInWindow.maxX - 4, y: lineInWindow.midY))
    }

    /// A finger held on the line's first word past the long press's time, slid to its end, and lifted.
    private func longPressAndDrag(across fixture: Fixture) async throws {
        let (start, end) = try lineEnds(in: fixture)
        let touches = SynthesizedTouches(window: fixture.window)
        touches.begin(at: [start])
        await touches.hold(seconds: 0.6)
        await touches.slide(to: [end], steps: 24)
        await touches.hold(seconds: 0.1)
        touches.end()
    }

    /// Waits until the bar keeps its form for 600 ms: a regular width's sidebar slides in, and the bar beside it is
    /// condensed until the slide ends, so a "+" found before then can leave the window as the bar changes form.
    private func waitForTheBarToSettle() async throws {
        var lastForm = String(describing: PencilToolRowForm.lastShown?.arrangement)
        var sameSince = Date()
        try await waitUntil("the bar's form settles") {
            let form = String(describing: PencilToolRowForm.lastShown?.arrangement)
            if form != lastForm { lastForm = form; sameSince = Date() }
            return Date().timeIntervalSince(sameSince) >= 0.6
        }
    }

    private func marks(on page: PDFPage) -> [PDFMarkup] {
        page.annotations.compactMap { annotation in PDFMarkup(annotation: annotation) }
    }

    /// The text under each mark on the page.
    private func markedStrings(on page: PDFPage) -> [String] {
        page.annotations.filter { annotation in PDFMarkup(annotation: annotation) != nil }.map { annotation in
            PDFMarkup.lineRectangles(of: annotation).compactMap { lineRectangle in
                page.selection(for: lineRectangle.insetBy(dx: 1, dy: lineRectangle.height / 4))?.string
            }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
