/**
 * File: PDFEmbedDocumentAnalysisHostedTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: A PDF embedded in a note is shown without PDFKit's page analysis, and the PDF opened in its own tab keeps
 *              it (HUNT-366).
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
import GraphiteIndex
@testable import GraphiteUI

/// HUNT-366: the iPhone froze for good during the release pass's embeds part, with dozens of PDFKit's page analyses
/// (Vision's text and form recognition, one per page of every embedded PDF view on screen) waiting on each other and on
/// a layer the main thread was committing. Embedded PDF views now leave the analysis off (`PDFViewDocumentAnalysis`).
@MainActor
final class PDFEmbedDocumentAnalysisHostedTests: XCTestCase {
    func testAnEmbeddedPDFIsNotAnalysedAndThePDFInItsOwnTabIs() async throws {
        let directory = try TemporaryVault.make(prefix: "PDFEmbedAnalysis", for: self).root
        try Self.threePagePDF().write(to: directory.appendingPathComponent("Slides.pdf"))
        try Data("# Week 1\n\n![[Slides.pdf]]\n\nThe end.\n".utf8).write(to: directory.appendingPathComponent("Week 1.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        // The reading view shows a note only with the vault's index.
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        await workspace.open(try VaultPath("Week 1.md"), placement: .currentTab)
        let session = try XCTUnwrap(workspace.markdownSession)
        let window = try show(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }

        for viewMode in [NoteViewMode.livePreview, .reading] {
            session.viewMode = viewMode
            var embeddedViews: [PDFView] = []
            try await waitUntil("the note shows its PDF in \(viewMode)") {
                window.layoutIfNeeded()
                embeddedViews = Self.descendants(of: window, matching: PDFView.self).filter { view in view.document != nil }
                return !embeddedViews.isEmpty
            }
            for view in embeddedViews {
                XCTAssertEqual(PDFViewDocumentAnalysis.isOn(in: view), false, "\(viewMode): the embedded PDF view does not analyse its pages")
            }
        }

        await workspace.open(try VaultPath("Slides.pdf"), placement: .currentTab)
        let pdfSession = try XCTUnwrap(workspace.pdfSession)
        try await waitUntil("the PDF's own tab shows it") {
            window.layoutIfNeeded()
            return pdfSession.pdfView != nil
        }
        let tabView = try XCTUnwrap(pdfSession.pdfView)
        XCTAssertEqual(PDFViewDocumentAnalysis.isOn(in: tabView), true, "The PDF's own tab keeps PDFKit's analysis (Live Text on scans)")
    }

    private func show(_ workspace: WorkspaceModel) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        window.makeKeyAndVisible()
        return window
    }

    private static func threePagePDF() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { context in
            for pageNumber in 1...3 {
                context.beginPage()
                ("Page \(pageNumber)" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 36)])
            }
        }
    }

    private static func descendants<Found: UIView>(of parent: UIView, matching type: Found.Type) -> [Found] {
        parent.subviews.flatMap { child in ((child as? Found).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}
#endif
