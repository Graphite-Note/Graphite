/**
 * File: LayoutNarrowWindowsHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the layout in narrow windows: tools beside a split, the tool row's forms, a phone held
 *              sideways and the smallest zoom.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The iPad and iPhone layout in narrow windows, in a real window (section 13 of the bug hunt): the Pencil tools
/// stay with a PDF that is written on while the other side of a split has the focus, the tool row never scrolls
/// however narrow its room, and a phone held sideways gives the note its screen while the keyboard is up.
/// Nothing here plays sound or shows anything on a screen a person looks at.
@MainActor
final class LayoutNarrowWindowsHostedTests: XCTestCase {
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

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    /// A vault holding a note and a four-page PDF, with the PDF open in the second tab and written on.
    private func pdfWorkspace(in directory: URL) async throws -> (WorkspaceModel, PDFSession) {
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 4).write(to: directory.appendingPathComponent("Paper.pdf"))
        try Data("# Untitled\n".utf8).write(to: directory.appendingPathComponent("Untitled.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Paper.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        return (workspace, session)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        try TemporaryVault.make(prefix: name, for: self).root
    }

    /// Waits until `measure` has given the same answer for `quietMilliseconds`: a layout that has settled.
    private func waitUntilSettled(_ description: String, quietMilliseconds: Int = 600, _ measure: () -> CGFloat) async throws {
        var lastAnswer = measure()
        var lastChange = ContinuousClock.now
        try await waitUntil(description) {
            let answer = measure()
            if abs(answer - lastAnswer) > 0.5 {
                lastAnswer = answer
                lastChange = ContinuousClock.now
                return false
            }
            return ContinuousClock.now - lastChange >= .milliseconds(quietMilliseconds)
        }
    }

    private func host(_ workspace: WorkspaceModel, size: CGSize, horizontalSizeClass: UIUserInterfaceSizeClass,
                      verticalSizeClass: UIUserInterfaceSizeClass = .regular) throws -> (window: UIWindow, controller: UIHostingController<GraphiteRootView>) {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = horizontalSizeClass
        controller.traitOverrides.verticalSizeClass = verticalSizeClass
        let window = UIWindow(windowScene: try scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return (window, controller)
    }

    /// HUNT-261, HUNT-264, HUNT-262: a PDF written on, with a new empty side beside it that has the focus, in a
    /// portrait iPad (834 points), keeps its Pencil tools; they sit inside the PDF's side and do not scroll.
    func testAPDFKeepsItsPencilToolsWhileTheNewSideBesideItHasTheFocus() async throws {
        let directory = try makeDirectory("SplitTools")
        let (workspace, session) = try await pdfWorkspace(in: directory)
        workspace.splitRight()
        XCTAssertNotEqual(workspace.layout.focusedGroup.id, workspace.layout.groups.first?.id, "The new empty side has the focus.")
        PencilToolRowForm.lastShown = nil
        let (window, _) = try host(workspace, size: CGSize(width: 834, height: 1194), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        try await waitUntil("the PDF's tools show although its side is not the focused one") { PencilToolRowForm.lastShown != nil }
        let pdfView = try XCTUnwrap(session.pdfView)
        try await waitUntilSettled("the split has laid out") { pdfView.bounds.width }
        attachScreenshot(of: window, named: "PDF beside a new empty side, portrait iPad")
        let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
        let pdfFrame = pdfView.convert(pdfView.bounds, to: window)
        XCTAssertGreaterThanOrEqual(shownRow.frameInWindow.minX, pdfFrame.minX - 1, "The tools are inside the PDF's side.")
        XCTAssertLessThanOrEqual(shownRow.frameInWindow.maxX, pdfFrame.maxX + 1, "The tools do not run past the PDF's side.")
        XCTAssertLessThanOrEqual(shownRow.frameInWindow.maxX, window.bounds.width + 0.5)
    }

    /// HUNT-262, HUNT-289: the tool row is whole, compact or condensed in any width, never wider than its room.
    func testThePencilToolRowFitsAnyWidthWithoutScrolling() async throws {
        let scene = try scene
        var formsByWidth: [CGFloat: PencilToolRowForm] = [:]
        for width in [140, 180, 245, 320, 400, 640, 1_100] as [CGFloat] {
            PencilToolRowForm.lastShown = nil
            let controller = UIHostingController(rootView: PencilToolRow(toolbox: PencilToolbox.shared, drawsShapes: .constant(false), addImage: {},
                                                                         offersReadAloudPen: true, offersTextBoxes: true)
                .frame(width: width, height: PencilToolbarMetrics.height)
                .background(Color(uiColor: .systemBackground)))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 100, width: width, height: 60)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await waitUntil("the row shows at \(Int(width)) points") { PencilToolRowForm.lastShown != nil }
            let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown)
            attachScreenshot(of: window, named: "Pencil tool row at \(Int(width)) points: \(shownRow.form)")
            XCTAssertLessThanOrEqual(shownRow.frameInWindow.width, width + 0.5, "At \(Int(width)) points the row is no wider than its room.")
            XCTAssertGreaterThanOrEqual(shownRow.frameInWindow.minX, -0.5)
            XCTAssertTrue(descendants(of: controller.view, matching: UIScrollView.self).isEmpty, "At \(Int(width)) points nothing scrolls sideways.")
            formsByWidth[width] = shownRow.form
            window.isHidden = true
            window.rootViewController = nil
        }
        XCTAssertEqual(formsByWidth[1_100], .full)
        XCTAssertEqual(formsByWidth[140], .condensed, "Too narrow for every tool: the rest is behind the one control.")
        XCTAssertEqual(formsByWidth[245], .condensed)
    }

    /// HUNT-260, HUNT-274: a phone held sideways (a Max one is a regular width and a compact height) gives the note
    /// its screen while the keyboard is up: the navigation bar goes, and comes back with the keyboard's going.
    func testTheNavigationBarGivesWayWhileTheKeyboardIsUpInACompactHeight() async throws {
        let directory = try makeDirectory("SidewaysPhone")
        try Data("# Lecture\n\nText.\n".utf8).write(to: directory.appendingPathComponent("Lecture.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Lecture.md"))
        let (window, controller) = try host(workspace, size: CGSize(width: 932, height: 430), horizontalSizeClass: .regular, verticalSizeClass: .compact)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { !self.descendants(of: controller.view, matching: MarkdownTextView.self).isEmpty }

        func visibleNavigationBarHeight() -> CGFloat {
            descendants(of: window, matching: UINavigationBar.self)
                .filter { bar in !bar.isHidden && bar.alpha > 0.01 }
                .map { bar in bar.convert(bar.bounds, to: window).intersection(window.bounds).height }
                .max() ?? 0
        }
        try await waitUntil("the navigation bar shows without the keyboard") { visibleNavigationBarHeight() > 20 }
        attachScreenshot(of: window, named: "Phone held sideways, no keyboard")

        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        try await waitUntil("the navigation bar gives way while the keyboard is up") { visibleNavigationBarHeight() < 4 }
        attachScreenshot(of: window, named: "Phone held sideways, keyboard up")

        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        try await waitUntil("the navigation bar comes back with the keyboard's going") { visibleNavigationBarHeight() > 20 }
    }

    /// HUNT-266: pages cannot be pinched down to a stamp: the smallest zoom is half of the one that fits the width.
    func testPagesCannotBeShrunkBelowHalfOfTheFittingZoom() async throws {
        let directory = try makeDirectory("SmallestZoom")
        let (workspace, session) = try await pdfWorkspace(in: directory)
        let (window, _) = try host(workspace, size: CGSize(width: 834, height: 1194), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        try await waitUntilSettled("the PDF has laid out") { pdfView.scaleFactorForSizeToFit }
        let fittingScale = pdfView.scaleFactorForSizeToFit
        try await waitUntil("the smallest zoom is half of the fitting one") {
            abs(pdfView.minScaleFactor - fittingScale * GraphitePDFDisplayView.smallestZoomAsFractionOfFitting) < 0.01
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = fittingScale * 0.2
        XCTAssertGreaterThanOrEqual(pdfView.scaleFactor, fittingScale * 0.5 - 0.01, "A pinch down to 20 percent stops at half of the fitting zoom.")
    }

    /// HUNT-263: opening a split narrows the PDF's pane; its first page still starts at the top of the pane, not
    /// a hundred points lower under an empty band.
    func testThePDFStillStartsAtTheTopWhenASplitNarrowsItsPane() async throws {
        let directory = try makeDirectory("SplitBand")
        let (workspace, session) = try await pdfWorkspace(in: directory)
        let (window, _) = try host(workspace, size: CGSize(width: 834, height: 1194), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        // The split builds the PDF's pane again, so the view is asked for each time.
        func measure() -> CGFloat {
            guard let pdfView = session.pdfView, pdfView.window === window, let page = session.document.page(at: 0) else { return .infinity }
            return pdfView.bounds.width * 1_000 + pdfView.convert(page.bounds(for: .cropBox), from: page).minY
        }
        func firstPageTop() -> CGFloat {
            guard let pdfView = session.pdfView, let page = session.document.page(at: 0) else { return .infinity }
            return pdfView.convert(page.bounds(for: .cropBox), from: page).minY
        }
        try await waitUntilSettled("the whole-width PDF has laid out") { measure() }
        XCTAssertLessThan(firstPageTop(), 40, "The first page starts at the top of the whole-width pane.")

        workspace.splitRight()
        try await waitUntil("the split narrows the pane") { (session.pdfView?.window === window) && (session.pdfView?.bounds.width ?? 1_000) < 500 }
        try await waitUntilSettled("the narrowed PDF has laid out") { measure() }
        attachScreenshot(of: window, named: "PDF pane narrowed by a split")
        XCTAssertLessThan(firstPageTop(), 40, "The first page still starts at the top of the narrowed pane.")
    }

    /// HUNT-275: touching the other side of a split moves nothing on the side touched. A note beside a PDF, in a
    /// portrait iPad, has the same top whether or not its side has the focus.
    func testANoteBesideAPDFKeepsItsTopWhetherOrNotItsSideHasTheFocus() async throws {
        let directory = try makeDirectory("SplitFocusJump")
        try Data("# Untitled\n\nA line of text.\n".utf8).write(to: directory.appendingPathComponent("Untitled.md"))
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 2).write(to: directory.appendingPathComponent("Paper.pdf"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Untitled.md"))
        let noteGroupID = workspace.layout.focusedGroupID
        await workspace.open(try VaultPath("Paper.pdf"), placement: .otherGroup)
        XCTAssertNotEqual(workspace.layout.focusedGroupID, noteGroupID, "The PDF's side has the focus.")
        let (window, controller) = try host(workspace, size: CGSize(width: 834, height: 1194), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { !self.descendants(of: controller.view, matching: MarkdownTextView.self).isEmpty }
        let editor = try XCTUnwrap(descendants(of: controller.view, matching: MarkdownTextView.self).first)
        func editorTop() -> CGFloat { editor.convert(editor.bounds, to: window).minY }
        try await waitUntilSettled("the note beside the PDF has laid out") { editorTop() }
        let topWithoutFocus = editorTop()

        workspace.focusGroup(noteGroupID)
        try await waitUntilSettled("the note's side has the focus and has laid out") { editorTop() + (workspace.layout.focusedGroupID == noteGroupID ? 10_000 : 0) }
        attachScreenshot(of: window, named: "Note side focused beside a PDF")
        let topWithFocus = editorTop()
        XCTAssertEqual(topWithFocus, topWithoutFocus, accuracy: 1, "The note does not jump when its side gains the focus.")
    }

    /// HUNT-268: the keyboard's format bar on an iPad held upright (834 points) scrolls, but Find and Hide Keyboard
    /// stand at its trailing end outside the scrolling row, and its buttons are 44 points tall.
    func testTheKeyboardBarKeepsFindAndHideKeyboardInViewWhenItScrolls() throws {
        var actions = EditorActions()
        actions.attach = {}
        actions.draw = {}
        let toolbar = EditorKeyboardToolbar(actions: actions, run: { _ in })
        toolbar.frame = CGRect(x: 0, y: 0, width: 834, height: EditorKeyboardToolbar.height)
        toolbar.layoutIfNeeded()
        let buttons = descendants(of: toolbar, matching: UIButton.self)
        let scrollView = try XCTUnwrap(descendants(of: toolbar, matching: UIScrollView.self).first)
        XCTAssertGreaterThan(scrollView.contentSize.width, scrollView.bounds.width, "The format buttons are wider than the iPad's portrait width and scroll.")
        for label in ["Find in note", "Hide keyboard"] {
            let button = try XCTUnwrap(buttons.first { button in button.accessibilityLabel == label }, label)
            let frame = button.convert(button.bounds, to: toolbar)
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(label) is inside the bar.")
            XCTAssertLessThanOrEqual(frame.maxX, toolbar.bounds.width, "\(label) is inside the bar, not past its end.")
            XCTAssertFalse(button.isDescendant(of: scrollView), "\(label) does not scroll away.")
        }
        for button in buttons {
            XCTAssertGreaterThanOrEqual(button.bounds.height, 43.5, "\(button.accessibilityLabel ?? "A button") is a 44-point target.")
        }
    }
}
#endif
