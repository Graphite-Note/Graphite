/**
 * File: NotebookImportHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A Goodnotes and a Notability notebook imported through the app's own Import call on the iPad, then
 *              opened in the PDF pane: their ink is PencilKit strokes on the page's canvas and their typed text is text
 *              boxes drawn over it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// The synthetic notebooks of `Tests/SyntheticNotebooks` (built from the documented formats, nothing from a real
/// notebook) imported on the iPad as the New menu's Import and every drop import them (`WorkspaceModel.importFiles`),
/// then opened in the PDF pane as a person opens them: the imported ink is on the page's PencilKit canvas, to be
/// erased, lassoed and written on like Graphite's own, and the typed text is Graphite's text boxes, drawn over the
/// canvas. A picture of each page shown is attached to the result.
@MainActor
final class NotebookImportHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
    }

    /// `Tests/SyntheticNotebooks` of the repository, read from the Mac's disk as the simulator shares it.
    private static let syntheticNotebooks = FixtureFolders.syntheticNotebooks

    func testImportedNotebooksOpenWithTheirInkOnTheCanvasAndTheirTextAsTextBoxes() async throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportHosted", for: self)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let sources = ["Synthetic text boxes.goodnotes", "Synthetic typed note.note"].map { name in Self.syntheticNotebooks.appendingPathComponent(name) }
        await workspace.importFiles(from: sources, into: .root)
        try await waitUntil("the notebook import has ended", timeoutSeconds: 60) {
            if case .finished = workspace.notebookImport?.state { true } else { false }
        }
        guard case .finished(let summary)? = workspace.notebookImport?.state else { return XCTFail("The import did not end.") }
        workspace.endNotebookImport()
        XCTAssertEqual(summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue), ["Synthetic text boxes.pdf", "Synthetic typed note.pdf"])

        let textBoxes = try await shown(vault.location(of: "Synthetic text boxes.pdf"))
        let textBoxesStrokeCount = try await canvasStrokeCount(of: textBoxes.session, in: textBoxes.controller)
        XCTAssertEqual(textBoxesStrokeCount, 1, "The imported ink is the canvas's to edit.")
        try await waitUntil("the page's text boxes are drawn over the canvas") { self.shownTextBoxCount(in: textBoxes.controller) == 4 }
        attachScreenshot(of: textBoxes.controller, named: "Imported Goodnotes text boxes")

        let typedNote = try await shown(vault.location(of: "Synthetic typed note.pdf"))
        let typedNoteStrokeCount = try await canvasStrokeCount(of: typedNote.session, in: typedNote.controller)
        XCTAssertEqual(typedNoteStrokeCount, 1)
        try await waitUntil("the first page's flowing text is drawn") { self.shownTextBoxCount(in: typedNote.controller) >= 1 }
        XCTAssertEqual(typedNote.session.document.pageCount, 2, "The typed text flows onto a page of its own.")
        attachScreenshot(of: typedNote.controller, named: "Imported Notability typed note")
    }

    // MARK: Showing a PDF

    private func shown(_ location: URL) async throws -> (session: PDFSession, controller: UIViewController) {
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return (session, controller)
    }

    /// The strokes of the first page's canvas once its stored ink is restored.
    private func canvasStrokeCount(of session: PDFSession, in controller: UIViewController) async throws -> Int {
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        var canvas: PDFPageCanvasView?
        try await waitUntil("the first page's ink is on its canvas") {
            canvas = self.descendants(of: controller.view, matching: PDFPageCanvasView.self).first { canvas in
                canvas.page === firstPage && canvas.window != nil && canvas.hasRestoredStoredInk && !canvas.isRestoringStoredInk
            }
            return canvas.map { canvas in !canvas.drawing.strokes.isEmpty } ?? false
        }
        return try XCTUnwrap(canvas).drawing.strokes.count
    }

    private func shownTextBoxCount(in controller: UIViewController) -> Int {
        descendants(of: controller.view, matching: PDFPageTextBoxesView.self).reduce(0) { count, view in
            count + (view.layer.sublayers?.first?.sublayers?.count ?? 0)
        }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let window = controller.view.window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
