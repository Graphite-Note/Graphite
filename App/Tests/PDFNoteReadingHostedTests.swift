/**
 * File: PDFNoteReadingHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Notes on the iPad: a note written into a PDF as the Mac and Preview write it shows its icon on the page,
 *              and a finger's tap on the icon, through UIKit's event path, opens its text to read, while reading the
 *              PDF and while writing on it; a tap beside it opens nothing.
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
final class PDFNoteReadingHostedTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []

    override func tearDown() async throws {
        for window in windows {
            window.rootViewController?.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
    }

    private static let noteText = "Why does the sampling rate double?"

    func testATapOnANotesIconOpensItsTextWhileReadingAndWhileWriting() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let (session, controller, page) = try await openNotebookWithANote()
        let window = try XCTUnwrap(controller.view.window)
        let pdfView = try XCTUnwrap(session.pdfView)
        let note = try XCTUnwrap(page.annotations.compactMap(PDFNote.init(annotation:)).first)
        let iconCenter = pdfView.convert(CGPoint(x: note.iconBounds.midX, y: note.iconBounds.midY), from: page)
        let iconInWindow = pdfView.convert(iconCenter, to: window)
        attachScreenshot(of: window, named: "The note's icon on the page")

        for isWriting in [false, true] {
            session.isWriting = isWriting
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
            await tap(at: iconInWindow, in: window)
            try await waitUntil("the note opens (writing: \(isWriting))") { self.shownReader(in: window) != nil }
            let reader = try XCTUnwrap(shownReader(in: window))
            XCTAssertEqual(reader.note.contents, Self.noteText)
            XCTAssertTrue(reader.textView?.text.contains(Self.noteText) == true)
            XCTAssertTrue(reader.textView?.text.hasPrefix("Ada") == true, "Its author above the text.")
            attachScreenshot(of: window, named: "The note open, writing: \(isWriting)")
            reader.dismiss(animated: false)
            try await waitUntil("the note closes") { self.shownReader(in: window) == nil }
        }

        session.isWriting = false
        await tap(at: CGPoint(x: iconInWindow.x + 120, y: iconInWindow.y + 120), in: window)
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        XCTAssertNil(shownReader(in: window), "A tap beside the icon opens no note.")
    }

    // MARK: The PDF

    private func openNotebookWithANote() async throws -> (PDFSession, UIHostingController<AnyView>, PDFPage) {
        let location = try makeHostedBlankNotebook(named: "NoteReading")
        locations.append(location)
        let written = try XCTUnwrap(PDFDocument(url: location))
        let cropBox = try XCTUnwrap(written.page(at: 0)).bounds(for: .cropBox)
        let note = PDFNote(contents: Self.noteText, iconBounds: CGRect(x: cropBox.midX - 12, y: cropBox.midY - 12, width: 24, height: 24), author: "Ada")
        try PDFPageManager.apply(.addNote(page: 0, note: note), to: written)
        XCTAssertTrue(written.write(to: location))
        let session = try await PDFSession.open(location)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the note's reader is installed") {
            (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator?.noteReading != nil
        }
        return (session, controller, page)
    }

    private func shownReader(in window: UIWindow) -> PDFNoteReaderController? {
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            if let reader = presented as? PDFNoteReaderController, !reader.isBeingDismissed { return reader }
            controller = presented
        }
        return nil
    }

    private func tap(at point: CGPoint, in window: UIWindow) async {
        await SynthesizedTouches(window: window).move(paths: [(point, point)], steps: 1, stepSeconds: 0.03, holdSeconds: 0.05)
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

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["GRAPHITE_SCREENSHOT_FOLDER"], let data = screenshot.pngData() else { return }
        // A picture that cannot be written is only not looked at; the attachment has it.
        try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }
}
#endif
