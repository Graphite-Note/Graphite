/**
 * File: PDFTextBoxEndTypingHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Hosted iPad tests of the end of typing in a PDF text box, by the bar's Done and by another tool on the
 *              fixed bar: the text typed is kept and the main thread comes back (HUNT-367).
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

/// Typing ended in a SwiftUI update of the pane had the text view give up first responder
/// there, which recursed in UIKit without end and froze the app (HUNT-367). Each test ends
/// typing as a person does and waits on the main thread, which a freeze never gives back.
@MainActor
final class PDFTextBoxEndTypingHostedTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var restoreToolbox: (() -> Void)?
    /// The pane's preferences, a suite of its own holding the fixed bar the physical iPad uses.
    private let preferencesSuiteName = "PDFTextBoxEndTypingHostedTests.\(UUID().uuidString)"

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        restoreToolbox?()
        restoreToolbox = nil
        UserDefaults(suiteName: preferencesSuiteName)?.removePersistentDomain(forName: preferencesSuiteName)
    }

    func testDoneEndsTypingKeepsTheTextAndGivesTheMainThreadBack() async throws {
        try await typeThenEnd("Ended with Done") { session, _ in session.textBoxActivity = .idle }
    }

    func testAnotherToolOnTheBarEndsTypingKeepsTheTextAndGivesTheMainThreadBack() async throws {
        try await typeThenEnd("Ended by the pen") { _, toolbox in toolbox.use(.ink) }
    }

    func testEndingTypingWithNothingTypedLeavesNoBoxAndGivesTheMainThreadBack() async throws {
        try await typeThenEnd(nil) { session, _ in session.textBoxActivity = .idle }
    }

    /// Starts a box with the fixed bar's text tool, types `text` (or nothing), ends typing with
    /// `end`, and checks the main thread returns, the text view is gone and the text is kept.
    private func typeThenEnd(_ text: String?, end: (PDFSession, PencilToolbox) -> Void) async throws {
        let toolbox = PencilToolbox.shared
        let toolBefore = toolbox.toolInUse
        restoreToolbox = { toolbox.use(toolBefore) }
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesSuiteName))
        preferences.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        toolbox.use(.text)
        let session = try await openNotebook()
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }.defaultAppStorage(preferences)))
        let page = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: page, in: session)
        try await waitUntil("the canvas takes the text tool's taps") { canvas.textToolTapped != nil }

        let tapPoint = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.height / 3), to: nil)
        canvas.textToolTapped?(tapPoint)
        try await waitUntil("typing starts") { session.textBoxActivity.isEditing }
        let textView = try XCTUnwrap(descendants(of: controller.view, matching: UITextView.self).first { textView in textView.isFirstResponder })
        if let text { textView.insertText(text) }

        end(session, toolbox)
        // A freeze keeps the main thread, so this never gets its turn and the test times out.
        try await waitUntil("typing ends and the text view goes") { !session.textBoxActivity.isEditing && textView.window == nil }
        XCTAssertFalse(textView.isFirstResponder)
        XCTAssertNil(session.errorMessage)

        let typedBoxes = session.textBoxes(on: page).filter { box in !box.plainText.isEmpty }
        guard let text else {
            XCTAssertTrue(typedBoxes.isEmpty, "Nothing typed leaves no box.")
            return
        }
        XCTAssertEqual(typedBoxes.map(\.plainText), [text], "The text typed is kept.")
        try await session.save()
        let savedPage = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        XCTAssertTrue(savedPage.annotations.contains { annotation in
            annotation.type == PDFTextBox.annotationTypeName && annotation.contents == text
        }, "The saved file has the box with its text.")
        // The page still answers: a second box can be started and ended.
        canvas.textToolTapped?(canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.height * 2 / 3), to: nil))
        try await waitUntil("typing starts again") { session.textBoxActivity.isEditing }
        session.textBoxActivity = .idle
        try await waitUntil("typing ends again") { !session.textBoxActivity.isEditing }
    }

    private func openNotebook() async throws -> PDFSession {
        let location = try TemporaryVault.make(prefix: "TextBoxEndTyping", for: self).root.appendingPathComponent("Notebook.pdf")
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

    private func descendants<View: UIView>(of view: UIView, matching type: View.Type) -> [View] {
        view.subviews.flatMap { subview in [subview as? View].compactMap { $0 } + descendants(of: subview, matching: type) }
    }
}
#endif
