/**
 * File: PDFTurnHostedTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Hosted test of a PDF written on while the 11-inch iPad turns from sideways to upright: the sidebar stays
 *              as it was, the page stays fitted, and the Pencil bar stays a centered row over the page (HUNT-311).
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

/// The owner's report of 2026-11-04: "when I'm in vertical or horizontal, it's not the same view". Measured here in a
/// real window turned from 1,194 by 834 points to 834 by 1,194. Nothing here plays sound.
@MainActor
final class PDFTurnHostedTests: XCTestCase {
    private var deviceDefaults: UserDefaults?
    private var savedToolbarStyle: Any?

    override func tearDown() async throws {
        guard let deviceDefaults else { return }
        if let savedToolbarStyle { deviceDefaults.set(savedToolbarStyle, forKey: PencilToolbarStyle.preferenceKey) }
        else { deviceDefaults.removeObject(forKey: PencilToolbarStyle.preferenceKey) }
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

    /// Waits until `measure` has given the same answer for 15 polls in a row.
    private func waitUntilSettled(_ description: String, _ measure: () -> CGRect) async throws {
        var lastAnswer = CGRect.null
        var unchangedPolls = 0
        try await waitUntil(description) {
            let answer = measure()
            unchangedPolls = answer == lastAnswer ? unchangedPolls + 1 : 0
            lastAnswer = answer
            return unchangedPolls >= 15
        }
    }

    func testTurningTheIPadKeepsTheSidebarTheFittedPageAndTheCenteredBar() async throws {
        let directory = try TemporaryVault.make(prefix: "Turn", for: self).root
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 4).write(to: directory.appendingPathComponent("Paper.pdf"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Paper.pdf"))
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        deviceDefaults = workspace.deviceDefaults
        savedToolbarStyle = workspace.deviceDefaults.object(forKey: PencilToolbarStyle.preferenceKey)
        workspace.deviceDefaults.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)

        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        window.frame = CGRect(origin: .zero, size: CGSize(width: 1_194, height: 834))
        window.rootViewController = controller
        PencilToolRowForm.lastShown = nil
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        try await waitUntilSettled("the sideways layout has settled") { pdfView.convert(pdfView.bounds, to: window) }
        attachScreenshot(of: window, named: "Sideways")
        let sidewaysFrame = pdfView.convert(pdfView.bounds, to: window)
        let isSidebarBesideSideways = sidewaysFrame.width < window.bounds.width - 200
        XCTAssertEqual(pdfView.scaleFactor, pdfView.scaleFactorForSizeToFit, accuracy: 0.01, "The page fits its width sideways")

        window.frame = CGRect(origin: .zero, size: CGSize(width: 834, height: 1_194))
        try await waitUntilSettled("the upright layout has settled") { pdfView.convert(pdfView.bounds, to: window) }
        attachScreenshot(of: window, named: "Upright, after the turn")
        let uprightFrame = pdfView.convert(pdfView.bounds, to: window)
        XCTAssertEqual(uprightFrame.width < window.bounds.width - 200, isSidebarBesideSideways,
                       "The sidebar is as it was before the turn (beside the documents sideways: \(isSidebarBesideSideways))")
        XCTAssertEqual(pdfView.scaleFactor, pdfView.scaleFactorForSizeToFit, accuracy: 0.01, "The page still fits its width")
        XCTAssertTrue(session.pdfView === pdfView, "The same view, turned")
        let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
        XCTAssertEqual(shownRow.frameInWindow.midX, uprightFrame.midX, accuracy: 24, "The bar is centered over the page upright too")
        XCTAssertLessThanOrEqual(shownRow.frameInWindow.maxX, uprightFrame.maxX + 1)
    }
}
#endif
