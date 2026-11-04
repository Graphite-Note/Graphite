/**
 * File: PDFTabSwitchHostedTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Hosted tests of a PDF shown again: after another tab, and after another file opened in its tab, it comes
 *              back with the same view, canvases, zoom and place, reading, laying out and decoding nothing (HUNT-308).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The owner's recording of 2026-11-04: back on a PDF, its page showed at another zoom, then blank for about three
/// seconds, then zoomed in, then jumped to a fitted zoom. Each showing built a new view: the document laid out again,
/// each page's ink decoded again into a new canvas, the zoom fitted before the place was restored; opening the PDF
/// again in the same tab read the file again too. Counted here on one switch: the view and canvases made, the ink
/// decoded, the file read, and the zoom. Nothing here plays sound.
@MainActor
final class PDFTabSwitchHostedTests: XCTestCase {
    private var scene: UIWindowScene {
        get throws { try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) }
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

    /// A vault with a note and two four-page PDFs; the note and the first PDF open in two tabs.
    private func workspace(named name: String) async throws -> WorkspaceModel {
        let directory = try TemporaryVault.make(prefix: name, for: self).root
        for fileName in ["Q7.pdf", "Q8.pdf"] {
            try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 4).write(to: directory.appendingPathComponent(fileName))
        }
        try Data("# Untitled\n".utf8).write(to: directory.appendingPathComponent("Untitled.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Q7.pdf"), placement: .newTab)
        return workspace
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIWindow {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: try scene)
        window.frame = CGRect(origin: .zero, size: CGSize(width: 1_194, height: 834))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    /// Shows the PDF, zooms it to twice the fitting zoom and scrolls into its second page, and waits until it settles.
    private func zoomedPDF(_ session: PDFSession, in window: UIWindow) async throws -> GraphitePDFDisplayView {
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        try await waitUntil("the PDF has its width") { pdfView.bounds.width > 100 && pdfView.scaleFactorForSizeToFit > 0 }
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit * 2
        if let secondPage = session.document.page(at: 1) { pdfView.go(to: secondPage) }
        var lastScale: CGFloat = 0
        var unchangedPolls = 0
        try await waitUntil("the zoom has settled") {
            unchangedPolls = abs(pdfView.scaleFactor - lastScale) < 0.0001 ? unchangedPolls + 1 : 0
            lastScale = pdfView.scaleFactor
            return unchangedPolls >= 15
        }
        return pdfView
    }

    /// Another tab and back: the same view, coordinator and canvases, no ink decoded, the same zoom and place.
    func testAPDFShownAgainAfterAnotherTabComesBackAsItWasLeft() async throws {
        let workspace = try await workspace(named: "TabSwitch")
        let session = try XCTUnwrap(workspace.pdfSession)
        let window = try host(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }
        let pdfView = try await zoomedPDF(session, in: window)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let canvases = Set(coordinator.canvasesByPage.values.map(ObjectIdentifier.init))
        let decodes = coordinator.storedInkDecodeCount
        let zoom = pdfView.scaleFactor
        let place = try XCTUnwrap(pdfView.pagePlace)
        let zoomChanges = pdfView.zoomChangesForWidth
        let shownAgain = workspace.hiddenPDFViews.shownAgainCount
        attachScreenshot(of: window, named: "PDF zoomed in, before the switch")

        let noteTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Untitled.md")))
        let pdfTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Q7.pdf")))
        workspace.activateTab(noteTab)
        try await waitUntil("the note is in front") { pdfView.window == nil }
        workspace.activateTab(pdfTab)
        try await waitUntil("the PDF is in front again") { session.pdfView?.window === window }
        attachScreenshot(of: window, named: "First frame back on the PDF")

        XCTAssertTrue(session.pdfView === pdfView, "The same view: nothing laid out or drawn again")
        XCTAssertTrue(pdfView.annotationCoordinator === coordinator)
        XCTAssertEqual(Set(coordinator.canvasesByPage.values.map(ObjectIdentifier.init)), canvases, "The same canvases")
        XCTAssertEqual(coordinator.storedInkDecodeCount, decodes, "No ink decoded")
        XCTAssertEqual(pdfView.scaleFactor, zoom, accuracy: 0.0001, "The zoom it was left at, at once")
        XCTAssertEqual(pdfView.pagePlace, place, "The place it was left at")
        XCTAssertEqual(pdfView.zoomChangesForWidth, zoomChanges, "No zoom chosen again")
        XCTAssertEqual(workspace.hiddenPDFViews.shownAgainCount, shownAgain + 1)
    }

    /// Another file opened in the PDF's tab, then the PDF again: the same session, so the file is not read again, and
    /// the same view at the same zoom.
    func testAPDFOpenedAgainInItsTabIsNotReadAgain() async throws {
        let workspace = try await workspace(named: "SameTab")
        let session = try XCTUnwrap(workspace.pdfSession)
        let window = try host(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }
        let pdfView = try await zoomedPDF(session, in: window)
        let zoom = pdfView.scaleFactor

        await workspace.open(try VaultPath("Q8.pdf"))
        try await waitUntil("Q8 shows in the tab") { workspace.pdfSession?.location.lastPathComponent == "Q8.pdf" && pdfView.window == nil }
        await workspace.open(try VaultPath("Q7.pdf"))
        try await waitUntil("Q7 shows again") { workspace.pdfSession === session && session.pdfView?.window === window }
        attachScreenshot(of: window, named: "Q7 opened again in its tab")

        XCTAssertTrue(workspace.pdfSession === session, "The file is not read again")
        XCTAssertTrue(session.pdfView === pdfView, "The same view")
        XCTAssertEqual(pdfView.scaleFactor, zoom, accuracy: 0.0001, "The zoom it was left at")
    }
}
#endif
