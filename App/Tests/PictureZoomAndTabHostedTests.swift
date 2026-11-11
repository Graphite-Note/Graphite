/**
 * File: PictureZoomAndTabHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Hosted tests of a note's pictures in the reading view: a picture in a table cell, one in a sentence
 *              and one on its own line offer Zoom In and Open in New Tab, zoom over the note and open their files
 *              in tabs of their own; the note keeps its place and its tab, and a web picture opens no tab.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The owner, 2026-10-22: a picture in a table should be easy to see larger, by zooming in over the note
/// or by opening it in a new tab. The commands are reached here as VoiceOver reaches them, through each
/// picture's accessibility actions, which are made from the same `PictureCommand`s as its menu and its
/// buttons; synthesized touches do not reach SwiftUI's gestures in a hosted test.
@MainActor
final class PictureZoomAndTabHostedTests: XCTestCase {
    private var window: UIWindow?

    private static let notePath = "Lecture.md"
    private static let tablePicture = "Figures/Scan.png"
    private static let inlinePicture = "Figures/Inline.png"
    private static let blockPicture = "Figures/Block.png"

    /// Enough text above the pictures that the note scrolls to them.
    private static let note: String = {
        let paragraphs = (1...60).map { number in "Paragraph \(number) of the lecture, long enough to fill a line of the note and then some more." }
        return "# Lecture\n\n" + paragraphs.joined(separator: "\n\n")
            + "\n\nThe detector, ![[Inline.png|60]], sits at the end of the beam line.\n\n"
            + "| Figure | Caption |\n| --- | --- |\n| ![[Scan.png\\|120]] | The scan |\n| ![chart](https://example.com/chart.png) | From the web |\n\n"
            + "![[Block.png|240]]\n\n" + paragraphs.joined(separator: "\n\n") + "\n"
    }()

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements only while an assistive technology asks for them.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    // MARK: Zoom

    /// A picture in a table cell and one in a sentence offer the picture's commands; Zoom In shows the
    /// picture over the window, and closing it leaves the note scrolled where it was.
    func testATableCellPictureAndAnInlinePictureZoomOverTheNoteWhichKeepsItsPlace() async throws {
        let workspace = try await makeWorkspace()
        let controller = try host(workspace)
        let scrollView = try await scrollToThePictures(in: controller)

        for (label, rawPath) in [("Scan", Self.tablePicture), ("Inline", Self.inlinePicture)] {
            let picture = try await pictureElement(labelled: label, in: controller)
            XCTAssertEqual(Set(actionNames(of: picture)).isSuperset(of: ["Zoom In", "Open in New Tab", workspace.openOnOtherSideTitle]), true,
                           "\(label): \(actionNames(of: picture))")
            let offsetBefore = scrollView.contentOffset.y
            try perform("Zoom In", on: picture)
            try await waitUntil("\(label) is zoomed into") { workspace.viewedImage?.rawValue == rawPath }
            // The zoom shows the file's name over the picture, and its own close button. A window's
            // `drawHierarchy` leaves the zoom out, so it is found by its elements, not in a screenshot.
            let fileName = try VaultPath(rawPath).name
            try await waitUntil("the zoom shows \(fileName)") { self.zoomElements(named: fileName, in: controller) != nil }
            let close = try XCTUnwrap(zoomElements(named: fileName, in: controller)?.close)
            XCTAssertTrue(close.accessibilityActivate(), "The zoom's close button closes it.")
            try await waitUntil("the zoom closes") { workspace.viewedImage == nil }
            try await waitUntil("the zoom is gone from the window") { self.zoomElements(named: fileName, in: controller) == nil }
            XCTAssertGreaterThan(offsetBefore, 500, "The note was scrolled down to its pictures.")
            XCTAssertEqual(scrollView.contentOffset.y, offsetBefore, accuracy: 1, "The note is where it was after zooming into \(label).")
            XCTAssertEqual(workspace.layout.allTabs.count, 1, "Zooming opens no tab.")
        }
        attachScreenshot(named: "The note after zooming in and out")
    }

    // MARK: Tabs

    /// Open in New Tab on the table's picture and on the picture on its own line opens each file in a tab
    /// of its own, with the file's name, through `workspace.open(_:placement: .newTab)`; the note's tab stays.
    func testOpenInNewTabOnATableCellPictureAndABlockPictureOpensTheirFilesBesideTheNote() async throws {
        let workspace = try await makeWorkspace()
        let controller = try host(workspace)
        _ = try await scrollToThePictures(in: controller)
        let noteTab = try XCTUnwrap(workspace.layout.allTabs.first)

        try perform("Open in New Tab", on: try await pictureElement(labelled: "Scan", in: controller))
        try await waitUntil("the table's picture opens in a new tab") { workspace.layout.activeTab.path?.rawValue == Self.tablePicture }
        XCTAssertEqual(workspace.layout.allTabs.map(\.path?.rawValue), [Self.notePath, Self.tablePicture])
        XCTAssertEqual(workspace.title(ofTab: workspace.layout.activeTab), "Scan.png")
        XCTAssertNil(workspace.viewedImage, "The tab opens without zooming.")
        // The image tab (`ImagePane`) shows the file at its own size in a zooming view.
        try await waitUntil("the picture's tab shows it") {
            self.descendants(of: controller.view, matching: UIImageView.self).contains { imageView in
                guard imageView.window != nil, let image = imageView.image else { return false }
                return image.size.width * image.scale == 400 && image.size.height * image.scale == 300
            }
        }
        attachScreenshot(named: "The table's picture in its own tab")

        workspace.activateTab(noteTab.id)
        try await waitUntil("the note's tab is back") { workspace.markdownSession?.path.rawValue == Self.notePath }
        _ = try await scrollToThePictures(in: controller)
        let blockPicture = try await element(in: controller) { element in
            element.accessibilityHint == "Opens the image to zoom" && self.actionNames(of: element).contains("Open in New Tab")
        }
        try perform("Open in New Tab", on: blockPicture)
        try await waitUntil("the block picture opens in a new tab") { workspace.layout.activeTab.path?.rawValue == Self.blockPicture }
        // A new tab opens beside the tab it is opened from.
        XCTAssertEqual(Set(workspace.layout.allTabs.compactMap(\.path?.rawValue)), [Self.notePath, Self.tablePicture, Self.blockPicture])
        XCTAssertEqual(workspace.layout.allTabs.count, 3)
        XCTAssertEqual(workspace.document(for: noteTab.id).markdownSession?.path.rawValue, Self.notePath, "The note's tab still shows the note.")
    }

    /// A picture from the web is not drawn from the vault: no picture of the note that offers a tab is it,
    /// and no tab opens for it.
    func testAWebPictureInATableOffersNoTab() async throws {
        let workspace = try await makeWorkspace()
        let controller = try host(workspace)
        _ = try await scrollToThePictures(in: controller)
        _ = try await pictureElement(labelled: "Scan", in: controller)
        let tabbedLabels = elements(in: controller).filter { element in actionNames(of: element).contains("Open in New Tab") }.compactMap(\.accessibilityLabel)
        XCTAssertFalse(tabbedLabels.contains { label in label.localizedCaseInsensitiveContains("chart") }, "\(tabbedLabels)")
        XCTAssertEqual(workspace.layout.allTabs.count, 1)
    }

    // MARK: Live Preview

    /// In Live Preview a table is a rendered block: its menu, opened on the table's picture, starts with the
    /// picture's commands, and the picture opens in a new tab beside the note.
    func testATablePictureInLivePreviewHasItsCommandsInTheTablesMenuAndOpensInANewTab() async throws {
        let workspace = try await makeWorkspace()
        try XCTUnwrap(workspace.markdownSession).viewMode = .livePreview
        let controller = try host(workspace)
        _ = try await scrollToThePictures(in: controller)
        var tableView: UIView?
        var picture: NSObject?
        try await waitUntil("the table's picture is drawn in its block") {
            guard let element = self.elements(in: controller).first(where: { element in
                element.accessibilityLabel == "Scan" && self.actionNames(of: element).contains("Zoom In")
            }) else { return false }
            let center = CGPoint(x: element.accessibilityFrame.midX, y: element.accessibilityFrame.midY)
            // The picture's accessibility frame is in the screen's coordinates, which are the window's here.
            tableView = self.descendants(of: controller.view, matching: UIView.self).last { view in
                view.window != nil && self.isRenderedBlock(view) && view.convert(view.bounds, to: nil).contains(center)
            }
            picture = element
            return tableView != nil
        }
        let blockView = try XCTUnwrap(tableView), tablePicture = try XCTUnwrap(picture)
        attachScreenshot(named: "Live Preview with the table's picture")
        let menu = try XCTUnwrap(renderedBlockMenu(of: blockView))
        let pictureFrame = tablePicture.accessibilityFrame
        let pointOnPicture = blockView.convert(CGPoint(x: pictureFrame.midX, y: pictureFrame.midY), from: nil)
        func titles(of element: UIMenuElement) -> [String] {
            if let submenu = element as? UIMenu { return submenu.children.flatMap(titles(of:)) }
            return [(element as? UIAction)?.title].compactMap { $0 }
        }
        let titlesOnPicture = titles(of: menu.makeMenu(at: pointOnPicture))
        XCTAssertEqual(Array(titlesOnPicture.prefix(3)), ["Zoom In", "Open in New Tab", workspace.openOnOtherSideTitle], "\(titlesOnPicture)")
        XCTAssertTrue(titlesOnPicture.contains("Edit Source"))
        let titlesOffPicture = titles(of: menu.makeMenu(at: CGPoint(x: pointOnPicture.x, y: blockView.bounds.maxY - 4)))
        XCTAssertFalse(titlesOffPicture.contains("Open in New Tab"), "Away from the picture the menu is the table's: \(titlesOffPicture)")

        try perform("Open in New Tab", on: tablePicture)
        try await waitUntil("the table's picture opens in a new tab") { workspace.layout.activeTab.path?.rawValue == Self.tablePicture }
        XCTAssertEqual(Set(workspace.layout.allTabs.compactMap(\.path?.rawValue)), [Self.notePath, Self.tablePicture])
    }

    /// The rendered block's own hosting view, whose controller carries the block's menu.
    private func isRenderedBlock(_ view: UIView) -> Bool {
        renderedBlockMenu(of: view) != nil
    }

    private func renderedBlockMenu(of view: UIView) -> RenderedBlockEditSourceMenu? {
        var responder = view.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if let host = currentResponder as? UIHostingController<AnyView> {
                return objc_getAssociatedObject(host, &RenderedBlockEditSourceMenu.associationKey) as? RenderedBlockEditSourceMenu
            }
            responder = currentResponder.next
        }
        return nil
    }

    // MARK: Helpers

    private func makeWorkspace() async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "PictureTabs", files: [Self.notePath: Self.note], for: self)
        let figures = vault.root.appendingPathComponent("Figures")
        try FileManager.default.createDirectory(at: figures, withIntermediateDirectories: true)
        for (rawPath, color) in [(Self.tablePicture, UIColor.systemTeal), (Self.inlinePicture, .systemOrange), (Self.blockPicture, .systemPurple)] {
            try Self.pictureData(color: color).write(to: vault.root.appendingPathComponent(rawPath))
        }
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: [Self.notePath, Self.tablePicture, Self.inlinePicture, Self.blockPicture].map { name in try VaultPath(name) },
                                root: vault.root)
        workspace.index = index
        await workspace.open(try VaultPath(Self.notePath))
        try XCTUnwrap(workspace.markdownSession).viewMode = .reading
        return workspace
    }

    /// A picture with a frame, so it can be told from the paper around it.
    private static func pictureData(color: UIColor) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        return renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            UIColor.white.setFill()
            context.fill(CGRect(x: 40, y: 40, width: 320, height: 220))
            color.setFill()
            context.fill(CGRect(x: 120, y: 100, width: 160, height: 100))
        }
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<GraphiteRootView> {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    /// The reading view's scroll view, scrolled so the sentence, the table and the picture on its own line are on screen.
    private func scrollToThePictures(in controller: UIViewController) async throws -> UIScrollView {
        var readingScrollView: UIScrollView?
        try await waitUntil("the note is laid out taller than the window") {
            readingScrollView = self.descendants(of: controller.view, matching: UIScrollView.self)
                .filter { scrollView in scrollView.window != nil && scrollView.contentSize.height > scrollView.bounds.height + 400 }
                .max { leftScrollView, rightScrollView in leftScrollView.contentSize.height < rightScrollView.contentSize.height }
            return readingScrollView != nil
        }
        let scrollView = try XCTUnwrap(readingScrollView)
        // The lazy stack lays out rows as they come into view, and some below it; the note is scrolled
        // until the picture on its own line, below the table, is inside the window.
        let windowBounds = try XCTUnwrap(window).bounds
        try await waitUntil("the pictures come into view", timeoutSeconds: 30) {
            if self.elements(in: controller).contains(where: { element in
                element.accessibilityHint == "Opens the image to zoom" && windowBounds.insetBy(dx: 0, dy: 100).contains(element.accessibilityFrame)
            }) { return true }
            let nextOffset = min(scrollView.contentOffset.y + 300, max(0, scrollView.contentSize.height - scrollView.bounds.height))
            scrollView.setContentOffset(CGPoint(x: 0, y: nextOffset), animated: false)
            return false
        }
        // The rows above have their sizes by now, so the offset no longer moves by itself.
        var lastOffset = -1.0
        var unchangedPolls = 0
        try await waitUntil("the note stays where it was scrolled") {
            unchangedPolls = abs(scrollView.contentOffset.y - lastOffset) < 0.5 ? unchangedPolls + 1 : 0
            lastOffset = scrollView.contentOffset.y
            return unchangedPolls >= 15
        }
        return scrollView
    }

    private func pictureElement(labelled label: String, in controller: UIViewController) async throws -> NSObject {
        try await element(in: controller) { element in
            element.accessibilityLabel == label && self.actionNames(of: element).contains("Zoom In")
        }
    }

    private func actionNames(of element: NSObject) -> [String] {
        (element.accessibilityCustomActions ?? []).map(\.name)
    }

    /// Runs the accessibility action VoiceOver lists under `name`.
    private func perform(_ name: String, on element: NSObject) throws {
        let action = try XCTUnwrap(element.accessibilityCustomActions?.first { action in action.name == name }, "\(actionNames(of: element))")
        if let handler = action.actionHandler {
            XCTAssertTrue(handler(action))
        } else {
            let target = try XCTUnwrap(action.target as? NSObject)
            _ = target.perform(action.selector, with: action)
        }
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    /// The first accessibility element on screen that satisfies `matches`, once there is one.
    private func element(in controller: UIViewController, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil {
            found = self.elements(in: controller).first(where: matches)
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func elements(in controller: UIViewController) -> [NSObject] {
        accessibilityElements(in: controller.view)
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
    }

    /// The zoom's title and its close button, the right-most "Close" in the window (each tab has one too);
    /// nil while no zoom shows `fileName`.
    private func zoomElements(named fileName: String, in controller: UIViewController) -> (title: NSObject, close: NSObject)? {
        let shown = elements(in: controller)
        guard let title = shown.first(where: { element in element.accessibilityLabel == fileName && !element.accessibilityTraits.contains(.button) }),
              let close = shown.filter({ element in element.accessibilityLabel == "Close" && element.accessibilityTraits.contains(.button) })
                .max(by: { leftElement, rightElement in leftElement.accessibilityFrame.maxX < rightElement.accessibilityFrame.maxX }),
              close.accessibilityFrame.minY < 120 else { return nil }
        return (title, close)
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
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
            ((child as? View).map { matchingChild in [matchingChild] } ?? []) + descendants(of: child, matching: type)
        }
    }
}
#endif
