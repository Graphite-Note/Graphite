/**
 * File: LayoutNarrowWindowsHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the layout in narrow windows: tools beside a split, the tool row's forms, a phone held
 *              sideways, the smallest zoom, a split PDF turned to landscape and back, and the three-dot menu's icons.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 05/11/2026
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

    /// HUNT-106: a PDF beside a note, written on, its view holding first responder for the Pencil's history (beside
    /// another side the fixed bar is in effect, so Apple's palette does not show). Closing its tab, and showing another
    /// file in its place, dismantle the PDF's view in the middle of SwiftUI's update; the view gave up first responder
    /// there, the known cause of the app computing without end. Each time the main queue answers, the PDF's view gives
    /// up first responder after the update, and the note beside it stays.
    func testClosingOrLeavingAPDFBesideANoteThatHoldsFirstResponderLeavesTheAppAnswering() async throws {
        let directory = try makeDirectory("PDFLeavingBesideNote")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 2).write(to: directory.appendingPathComponent("Paper.pdf"))
        try Data("# Lecture\n\nText beside the PDF.\n".utf8).write(to: directory.appendingPathComponent("Lecture.md"))
        try Data("# Other\n".utf8).write(to: directory.appendingPathComponent("Other.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Lecture.md"))
        let (window, _) = try host(workspace, size: CGSize(width: 1194, height: 834), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        let paper = try VaultPath("Paper.pdf")

        for (attempt, leavesByClosing) in [true, false, true].enumerated() {
            await workspace.open(paper, placement: .otherGroup)
            let session = try XCTUnwrap(workspace.tabDocuments.values.compactMap(\.pdfSession).first { pdf in pdf.location.lastPathComponent == "Paper.pdf" })
            session.isWriting = true
            try await waitUntil("the PDF is shown beside the note, attempt \(attempt)") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
            try await waitUntil("the PDF's view holds first responder, attempt \(attempt)") {
                self.descendants(of: window, matching: PencilToolPickerHostView.self).contains { host in host.isFirstResponder }
            }
            let toolPickerHost = try XCTUnwrap(descendants(of: window, matching: PencilToolPickerHostView.self).first { host in host.isFirstResponder })
            XCTAssertFalse(descendants(of: window, matching: MarkdownTextView.self).isEmpty, "The note is beside the PDF")
            attachScreenshot(of: window, named: "PDF beside a note, attempt \(attempt)")
            let pdfTabID = try XCTUnwrap(workspace.layout.tabID(showing: paper))
            if leavesByClosing {
                await workspace.closeTab(pdfTabID)
            } else {
                // Another file in the PDF's tab: its view goes as the tab shows the note.
                await workspace.open(try VaultPath("Other.md"))
                XCTAssertNil(workspace.layout.tabID(showing: paper), "The PDF's tab shows the other note")
            }
            var hasMainQueueAnswered = false
            DispatchQueue.main.async { hasMainQueueAnswered = true }
            try await waitUntil("the main queue answers after the PDF went, attempt \(attempt)", timeoutSeconds: 5) { hasMainQueueAnswered }
            try await waitUntil("the PDF's view has gone from the window, attempt \(attempt)") { toolPickerHost.window == nil || !toolPickerHost.isFirstResponder }
            XCTAssertFalse(toolPickerHost.isFirstResponder, "First responder was given up, attempt \(attempt)")
            window.layoutIfNeeded()
            XCTAssertFalse(descendants(of: window, matching: MarkdownTextView.self).isEmpty, "The note stays, attempt \(attempt)")
            if !leavesByClosing, let otherTabID = workspace.layout.tabID(showing: try VaultPath("Other.md")) { await workspace.closeTab(otherTabID) }
        }
    }

    /// HUNT-262, HUNT-289: the tool row is whole, compact or condensed in any width, never wider than its room. Only its
    /// colors may scroll, in a strip of whole colors, where they do not all fit even at the mini size (HUNT-317).
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
            let scrollViews = descendants(of: controller.view, matching: UIScrollView.self)
            if case .compactWithScrollingColors(let visibleSwatchCount) = shownRow.arrangement {
                let stripWidth = CGFloat(Double(visibleSwatchCount) * PencilToolRowLayout.Density.tightest.swatchPitch)
                XCTAssertFalse(scrollViews.isEmpty, "At \(Int(width)) points the colors scroll in their strip.")
                for scrollView in scrollViews {
                    XCTAssertEqual(scrollView.bounds.width, stripWidth, accuracy: 0.5, "At \(Int(width)) points only the strip of whole colors scrolls.")
                }
            } else {
                XCTAssertTrue(scrollViews.isEmpty, "At \(Int(width)) points nothing scrolls sideways.")
            }
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

        /// The navigation bar over the note: a sidebar beside it, as an iPad's window this wide shows it on the
        /// owner's iPad, keeps its own bar, which is not over the note.
        func visibleNavigationBarHeight() -> CGFloat {
            let noteFrames = descendants(of: window, matching: MarkdownTextView.self).filter { editor in editor.window === window }
                .map { editor in editor.convert(editor.bounds, to: window) }
            return descendants(of: window, matching: UINavigationBar.self)
                .filter { bar in !bar.isHidden && bar.alpha > 0.01 && bar.window === window }
                .map { bar in bar.convert(bar.bounds, to: window).intersection(window.bounds) }
                .filter { barFrame in noteFrames.contains { noteFrame in min(barFrame.maxX, noteFrame.maxX) - max(barFrame.minX, noteFrame.minX) > 40 } }
                .map(\.height)
                .max() ?? 0
        }
        func describeNavigationBars(_ moment: String) {
            let bars = descendants(of: window, matching: UINavigationBar.self).filter { bar in bar.window === window }
                .map { bar in "\(bar.convert(bar.bounds, to: window)) hidden \(bar.isHidden) alpha \(bar.alpha)" }
            let notes = descendants(of: window, matching: MarkdownTextView.self).map { editor in editor.convert(editor.bounds, to: window) }
            print("KEYBOARD \(moment): navigation bars \(bars), note at \(notes), bar over the note \(visibleNavigationBarHeight())")
        }
        try await waitUntil("the navigation bar shows without the keyboard") { visibleNavigationBarHeight() > 20 }
        describeNavigationBars("without the keyboard")
        attachScreenshot(of: window, named: "Phone held sideways, no keyboard")

        // A device has a software keyboard, which a simulator with a hardware keyboard never shows: one still leaving
        // the text view of an earlier test sends its hide after the show posted here, and the bar comes back as it
        // should. The owner's iPad timed out here on 2026-11-04 and 2026-11-05. The show is posted once the keyboard is
        // quiet, and again whenever the device's keyboard answered after it.
        let keyboardNotifications = KeyboardNotificationCounter()
        defer { keyboardNotifications.stop() }
        for shownWindow in try scene.windows { shownWindow.endEditing(true) }
        try await waitUntilSettled("the device's keyboard is quiet", quietMilliseconds: 1_000) { CGFloat(keyboardNotifications.count) }
        let notificationsBeforeTheShow = keyboardNotifications.count
        var countAfterTheLastShow = 0
        var postedShows = 0
        try await waitUntil("the navigation bar gives way while the keyboard is up") {
            if visibleNavigationBarHeight() < 4 { return true }
            if postedShows == 0 || keyboardNotifications.count != countAfterTheLastShow {
                NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
                postedShows += 1
                countAfterTheLastShow = keyboardNotifications.count
            }
            return false
        }
        describeNavigationBars("keyboard up, \(postedShows) shows posted, \(keyboardNotifications.count - notificationsBeforeTheShow - postedShows) notifications from the device")
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

    /// HUNT-263 as it was seen: a split in portrait, then the iPad turned to landscape and back. At each size the
    /// first page of the narrowed PDF starts at the top of its pane, with no empty band above it.
    func testThePDFStartsAtTheTopOfASplitPaneAfterTurningToLandscapeAndBack() async throws {
        let directory = try makeDirectory("SplitBandTurned")
        let (workspace, session) = try await pdfWorkspace(in: directory)
        let (window, _) = try host(workspace, size: CGSize(width: 834, height: 1194), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        func measure() -> CGFloat {
            guard let pdfView = session.pdfView, pdfView.window === window, let page = session.document.page(at: 0) else { return .infinity }
            return pdfView.bounds.width * 1_000 + pdfView.convert(page.bounds(for: .cropBox), from: page).minY
        }
        func firstPageTop() -> CGFloat {
            guard let pdfView = session.pdfView, let page = session.document.page(at: 0) else { return .infinity }
            return pdfView.convert(page.bounds(for: .cropBox), from: page).minY
        }
        workspace.splitRight()
        try await waitUntil("the split narrows the pane") { (session.pdfView?.window === window) && (session.pdfView?.bounds.width ?? 1_000) < 500 }
        try await waitUntilSettled("the narrowed PDF has laid out in portrait") { measure() }
        XCTAssertLessThan(firstPageTop(), 40, "The first page starts at the top of the narrowed pane in portrait.")
        for (size, orientation) in [(CGSize(width: 1194, height: 834), "landscape"), (CGSize(width: 834, height: 1194), "portrait again")] {
            window.frame = CGRect(origin: .zero, size: size)
            try await waitUntil("the PDF's pane follows the window to \(orientation)") { session.pdfView?.window === window }
            try await waitUntilSettled("the PDF has laid out in \(orientation)") { measure() }
            attachScreenshot(of: window, named: "Split PDF, \(orientation)")
            XCTAssertLessThan(firstPageTop(), 40, "In \(orientation) the first page starts at the top of its pane, with no band above it.")
        }
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

    /// HUNT-144: the keyboard's format bar on an iPhone held upright (393 points wide). The links, the tag and the
    /// lists come right after Bold and Italic, the link on the first screen of the row, Find stays in view, and the
    /// row's trailing edge fades while buttons wait beyond it; scrolled to its end, the fade goes. The row is laid out for a phone on this iPad
    /// simulator through the device kind it is given.
    func testOnAPhoneTheKeyboardBarShowsLinksListsAndTasksFirstAndFadesWhereItScrolls() throws {
        var actions = EditorActions()
        actions.attach = {}
        actions.draw = {}
        let toolbar = EditorKeyboardToolbar(actions: actions, idiom: .phone, run: { _ in })
        toolbar.overrideUserInterfaceStyle = .light
        let window = UIWindow(windowScene: try scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 200)
        window.traitOverrides.horizontalSizeClass = .compact
        window.addSubview(toolbar)
        window.isHidden = false
        defer { window.isHidden = true }
        toolbar.frame = CGRect(x: 0, y: 100, width: 393, height: EditorKeyboardToolbar.height)
        toolbar.layoutIfNeeded()
        let scrollView = try XCTUnwrap(descendants(of: toolbar, matching: UIScrollView.self).first)
        let rowButtons = descendants(of: scrollView, matching: UIButton.self).filter { button in !button.isHidden && !(button.superview?.isHidden ?? false) }
            .sorted { leftButton, rightButton in leftButton.convert(leftButton.bounds, to: scrollView).minX < rightButton.convert(rightButton.bounds, to: scrollView).minX }
        let order = rowButtons.compactMap(\.accessibilityLabel)
        print("KEYBOARD-BAR phone order: \(order)")
        XCTAssertEqual(Array(order.prefix(10)), ["Undo", "Redo", "Heading", "Bold", "Italic", "Link to note", "Tag", "Bulleted list", "Numbered list", "Task"])
        let visibleWidth = scrollView.bounds.width
        let onFirstScreen = rowButtons.filter { button in button.convert(button.bounds, to: scrollView).maxX - scrollView.contentOffset.x <= visibleWidth + 0.5 }.compactMap(\.accessibilityLabel)
        print("KEYBOARD-BAR phone first screen of \(visibleWidth) points: \(onFirstScreen)")
        XCTAssertTrue(onFirstScreen.contains("Link to note"), "The link comes before the rarer marks, on the first screen: \(onFirstScreen)")
        XCTAssertTrue(descendants(of: toolbar, matching: UIButton.self).contains { button in button.accessibilityLabel == "Find in note" && !button.isDescendant(of: scrollView) },
                      "Find stays in view at the trailing end")
        XCTAssertGreaterThan(scrollView.contentSize.width, visibleWidth, "The rarer buttons wait beyond the edge")
        let scrollContainer = try XCTUnwrap(scrollView.superview)
        XCTAssertNotNil(scrollContainer.layer.mask, "The trailing edge fades while buttons wait beyond it")
        attachScreenshot(of: window, named: "Keyboard bar on an iPhone held upright")
        scrollView.setContentOffset(CGPoint(x: scrollView.contentSize.width - visibleWidth, y: 0), animated: false)
        toolbar.layoutIfNeeded()
        XCTAssertNil(scrollContainer.layer.mask, "At the row's end nothing waits, and nothing fades")
    }

    /// HUNT-155: while the sidebar's search shows its results, no panel of the picker above them is lit, as on an
    /// iPhone held upright; choosing a panel ends the search and lights that panel.
    func testWhileSearchingNoPanelOfTheSidebarsPickerIsLitAndChoosingOneEndsTheSearch() async throws {
        let directory = try makeDirectory("SidebarSearchPicker")
        try Data("# Lecture\n".utf8).write(to: directory.appendingPathComponent("Lecture.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let controller = UIHostingController(rootView: NavigationStack {
            VaultSidebar(workspace: workspace, creation: .constant(nil), showsSettings: .constant(false), showsVaultManager: .constant(false))
        })
        controller.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(windowScene: try scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func panelPicker() -> UISegmentedControl? {
            descendants(of: window, matching: UISegmentedControl.self).first { control in control.numberOfSegments > 1 && control.window != nil }
        }
        try await waitUntil("the sidebar's panel picker shows") { panelPicker() != nil }
        let picker = try XCTUnwrap(panelPicker())
        XCTAssertNotEqual(picker.selectedSegmentIndex, UISegmentedControl.noSegment, "A panel is lit before searching")

        workspace.searchQuery = "lecture"
        try await waitUntil("no panel is lit while the results show") { panelPicker()?.selectedSegmentIndex == UISegmentedControl.noSegment }
        attachScreenshot(of: window, named: "Sidebar searching on a phone's width")

        let shownPicker = try XCTUnwrap(panelPicker())
        shownPicker.selectedSegmentIndex = 1
        shownPicker.sendActions(for: .valueChanged)
        try await waitUntil("choosing a panel ends the search") { workspace.searchQuery.isEmpty }
        try await waitUntil("the chosen panel is lit") { panelPicker()?.selectedSegmentIndex == 1 }
    }

    /// What the navigation bar shows: whether a control with this system image is on it, and the frames of its titles
    /// and buttons. UIKit's bar buttons carry no label of their own a test can read.
    private func navigationBarContents(in window: UIWindow) -> (symbolNames: [String], titles: [CGRect], buttons: [CGRect]) {
        var symbolNames: [String] = [], titles: [CGRect] = [], buttons: [CGRect] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            let kind = String(describing: type(of: view))
            if kind.contains("TitleControl") { titles.append(view.convert(view.bounds, to: window)) }
            if kind.contains("ButtonBarButton") { buttons.append(view.convert(view.bounds, to: window)) }
            if let imageView = view as? UIImageView, let image = imageView.image { symbolNames.append(image.description) }
            view.subviews.forEach(visit)
        }
        descendants(of: window, matching: UINavigationBar.self).forEach(visit)
        return (symbolNames, titles, buttons)
    }

    /// HUNT-146: the sidebar open beside a PDF about 430 points wide: pages and find are on the bar beside the title
    /// and More, adding pages is in More, and nothing covers the title. Reported on a portrait iPad; since HUNT-317 an
    /// upright window shows its sidebar over the documents, so the documents are this narrow beside the sidebar in a
    /// window wider than tall, as Stage Manager or Split View gives one.
    func testAPDFsBarKeepsPagesAndFindWithTheSidebarOpenInPortrait() async throws {
        let directory = try makeDirectory("PortraitSidebar")
        let (workspace, session) = try await pdfWorkspace(in: directory)
        let (window, _) = try host(workspace, size: CGSize(width: 750, height: 600), horizontalSizeClass: .regular)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        workspace.searchResultsRevealRequest += 1
        let pdfView = try XCTUnwrap(session.pdfView)
        try await waitUntil("the sidebar opens beside the PDF") { pdfView.convert(pdfView.bounds, to: window).minX > 200 }
        try await waitUntilSettled("the bar has laid out") { pdfView.bounds.width }
        XCTAssertEqual(pdfView.bounds.width, 430, accuracy: 40, "The width of the report.")
        try await waitUntil("pages and find reach the bar") {
            let contents = self.navigationBarContents(in: window)
            let showsBothSymbols = contents.symbolNames.contains { name in name.contains("magnifyingglass") } && contents.symbolNames.contains { name in name.contains("square.grid.2x2") }
            // Back, Forward, recording and More are four; a symbol drawn by SwiftUI has no image to read, but its button counts.
            return showsBothSymbols || contents.buttons.count >= 5
        }
        attachScreenshot(of: window, named: "PDF bar with the sidebar open, 430 points")
        let bar = navigationBarContents(in: window)
        XCTAssertTrue(bar.symbolNames.contains { name in name.contains("ellipsis") }, "More stays.")
        XCTAssertFalse(bar.symbolNames.contains { name in name.contains("plus.rectangle.on.rectangle") }, "Adding pages is in More.")
        for title in bar.titles {
            XCTAssertGreaterThanOrEqual(title.width, 60, "The title shortens but stays readable.")
            XCTAssertFalse(bar.buttons.contains { button in button.intersects(title.insetBy(dx: 1, dy: 1)) }, "No button covers the title.")
        }
        for button in bar.buttons { XCTAssertLessThanOrEqual(button.maxX, window.bounds.width + 0.5, "Every button is inside the window.") }
    }

    /// The relative contrast of two colors, as WCAG defines it, resolved in dark appearance.
    private func darkContrast(of color: UIColor, against background: UIColor) -> Double {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func luminance(_ color: UIColor) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            color.resolvedColor(with: dark).getRed(&red, green: &green, blue: &blue, alpha: nil)
            func linear(_ component: CGFloat) -> Double {
                component <= 0.03928 ? Double(component) / 12.92 : pow((Double(component) + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let (first, second) = (luminance(color), luminance(background))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Every window of the scene in one picture, in their order: a menu shows in a window of its own or over the bar.
    private func attachScreenshotOfEveryWindow(in scene: UIWindowScene, size: CGSize, named name: String) {
        let screenshot = UIGraphicsImageRenderer(size: size).image { _ in
            for window in scene.windows.sorted(by: { first, second in first.windowLevel < second.windowLevel }) where !window.isHidden {
                window.drawHierarchy(in: window.frame, afterScreenUpdates: true)
            }
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The symbol images shown in the scene's windows, by identity, to tell the ones a menu adds.
    private func shownSymbolImageViews(in scene: UIWindowScene) -> [UIImageView] {
        func symbols(in view: UIView) -> [UIImageView] {
            guard !view.isHidden, view.alpha > 0.01 else { return [] }
            let own = (view as? UIImageView).map { imageView in imageView.image?.isSymbolImage == true ? [imageView] : [] } ?? []
            return own + view.subviews.flatMap(symbols)
        }
        return scene.windows.filter { window in !window.isHidden }.flatMap(symbols)
    }

    /// HUNT-280: the icons of the bar's three-dot menu read in dark appearance. The bars take the label color, the
    /// documents keep the accent. The menu is opened, and each icon it adds must have an effective tint (the color
    /// UIKit draws a template symbol in) of at least 3 to 1 against the dark menu; the accent's dark blue was about 1.5.
    func testTheThreeDotMenusIconsReadInDarkAppearance() async throws {
        let directory = try makeDirectory("DarkMenu")
        let (workspace, session) = try await pdfWorkspace(in: directory)
        // A dark blue accent, as the vault of the report had; it is the vault's, so nothing is stored on the device.
        let previousVaultAccentHex = workspace.preferences.vaultAccentHex
        workspace.preferences.vaultAccentHex = "#1E3A8A"
        defer { workspace.preferences.vaultAccentHex = previousVaultAccentHex }
        let windowScene = try scene
        let size = CGSize(width: 834, height: 1194)
        let (window, _) = try host(workspace, size: size, horizontalSizeClass: .regular)
        window.overrideUserInterfaceStyle = .dark
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        try await waitUntil("More shows") { self.navigationBarContents(in: window).symbolNames.contains { name in name.contains("ellipsis") } }
        func showsMore(_ view: UIView) -> Bool {
            (view as? UIImageView)?.image?.description.contains("ellipsis") == true || view.subviews.contains(where: showsMore)
        }
        let bar = try XCTUnwrap(descendants(of: window, matching: UINavigationBar.self).first { bar in !bar.isHidden && showsMore(bar) })
        let accent = try XCTUnwrap(UIColor.graphiteAccent(hex: workspace.preferences.accentHex))
        // The menu's material in dark appearance, about this gray; 3 to 1 is what a graphic needs to be made out (WCAG 1.4.11).
        let platter = UIColor(white: 0.17, alpha: 1)
        XCTAssertGreaterThan(darkContrast(of: try XCTUnwrap(bar.tintColor), against: accent), 1.1, "The bar does not take the accent, whose icons were dark blue on the dark menu.")

        var moreImageView: UIImageView?
        func findMore(_ view: UIView) {
            if let imageView = view as? UIImageView, imageView.image?.description.contains("ellipsis") == true { moreImageView = imageView }
            view.subviews.forEach(findMore)
        }
        findMore(bar)
        let more = try XCTUnwrap(moreImageView)
        XCTAssertGreaterThanOrEqual(darkContrast(of: more.tintColor, against: platter), 3, "The bar's own ••• reads: \(more.tintColor.description)")

        let symbolsBefore = Set(shownSymbolImageViews(in: windowScene).map(ObjectIdentifier.init))
        func menuIcons() -> [UIImageView] {
            shownSymbolImageViews(in: windowScene).filter { imageView in !symbolsBefore.contains(ObjectIdentifier(imageView)) }
        }
        // A finger's tap on •••, as the screen delivers it; where that does not open the menu, the button's own
        // accessibility action, as VoiceOver opens it.
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let frame = more.convert(more.bounds, to: window)
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        await SynthesizedTouches(window: window).move(paths: [(middle, middle)], steps: 1, stepSeconds: 0.03, holdSeconds: 0.05)
        try? await waitUntil("the menu opens from a tap", timeoutSeconds: 5) { menuIcons().count >= 3 }
        if menuIcons().count < 3 {
            let button = sequence(first: more as UIView) { view in view.superview }.first { view in view is UIControl || view.isAccessibilityElement }
            _ = button?.accessibilityActivate()
        }
        try await waitUntil("the menu opens and shows its icons", timeoutSeconds: 10) { menuIcons().count >= 3 }
        attachScreenshotOfEveryWindow(in: windowScene, size: size, named: "Three-dot menu of a PDF, dark appearance")
        let icons = menuIcons()
        print("HUNT-280: \(icons.count) menu icons, tints \(icons.map { icon in icon.tintColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).description })")
        XCTAssertGreaterThanOrEqual(icons.count, 3, "The menu's icons were found, so their color is checked, not left to a picture.")
        for icon in icons {
            XCTAssertGreaterThanOrEqual(darkContrast(of: icon.tintColor, against: platter), 3, "A menu icon reads: \(icon.image?.description ?? "")")
        }
    }
}

/// Counts the keyboard's notifications, which a device's software keyboard sends as it comes and goes, until `stop`.
@MainActor
private final class KeyboardNotificationCounter {
    private(set) var count = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        observers = [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.count += 1 }
            }
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}
#endif
