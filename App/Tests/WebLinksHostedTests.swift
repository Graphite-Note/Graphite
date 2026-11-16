/**
 * File: WebLinksHostedTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: On the iPad, a bare web address in Live Preview is drawn as a link and its long-press menu offers Use
 *              Page Title and Show Preview, and a YouTube embed on its line is a video card in Live Preview and in the
 *              reading view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The hosted workspace's own editor and reading view of a note with pasted addresses and a YouTube embed.
@MainActor
final class WebLinksHostedTests: XCTestCase {
    private var window: UIWindow?

    private static let playlist = "https://www.youtube.com/playlist?list=PL5Q2soXY2Zi9OtbGJyUVHp1Gp3c_0Dymh"
    private static let note = "# Links\n\n\(playlist)\n\nSee [the course](https://example.com/course) and https://example.com/page.\n\n"
        + "![Computer Architecture lectures](\(playlist))\n\nAfter the card\n"

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

    /// The pasted address has the colour of a Markdown link's text, and the menu at it offers the
    /// page's title; at a YouTube address it offers the preview too.
    func testABareAddressIsDrawnAsALinkAndItsMenuOffersTheTitleAndThePreview() async throws {
        let (session, controller) = try await openNote(viewMode: .livePreview)
        let editor = try await visibleEditor(in: controller, showing: session)
        let text = editor.text as NSString
        let bareAddress = text.range(of: "https://example.com/page")
        let markdownLinkText = text.range(of: "the course")
        let plainText = text.range(of: "See ")
        func color(at location: Int) -> UIColor? { editor.attributedText.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor }
        try await waitUntil("the note is styled") {
            color(at: markdownLinkText.location) != color(at: plainText.location)
        }
        XCTAssertEqual(color(at: bareAddress.location + 4), color(at: markdownLinkText.location), "The bare address is drawn as a link.")
        XCTAssertEqual(color(at: NSMaxRange(bareAddress)), color(at: plainText.location), "The full stop after it is not part of it.")

        XCTAssertEqual(Self.menuTitles(of: editor, at: bareAddress.location + 4).prefix(1), ["Use Page Title"])
        XCTAssertFalse(Self.menuTitles(of: editor, at: bareAddress.location + 4).contains("Show Preview"), "Only YouTube has a preview.")
        let youTubeTitles = Self.menuTitles(of: editor, at: text.range(of: "playlist?list").location)
        XCTAssertEqual(youTubeTitles.prefix(2), ["Use Page Title", "Show Preview"])
        XCTAssertFalse(Self.menuTitles(of: editor, at: plainText.location).contains("Use Page Title"), "Plain text has no web link entries.")

        _ = try await element(in: controller) { element in (element.accessibilityLabel ?? "").hasPrefix("YouTube playlist: ") }
        attachScreenshot(named: "Live Preview: bare addresses as links and the playlist's card")
    }

    /// The embed's card is drawn in the reading view as well, and the bare address is a link there.
    func testTheReadingViewDrawsTheCardAndLinksTheBareAddress() async throws {
        let (_, controller) = try await openNote(viewMode: .reading)
        let card = try await element(in: controller) { element in (element.accessibilityLabel ?? "").hasPrefix("YouTube playlist: ") }
        XCTAssertTrue(card.accessibilityTraits.contains(.link), "The card opens YouTube.")
        XCTAssertLessThanOrEqual(card.accessibilityFrame.width, WebVideoCard.maximumWidth + 1)
        attachScreenshot(named: "Reading view: the playlist's card")
    }

    // MARK: Helpers

    private static func menuTitles(of editor: MarkdownTextView, at location: Int) -> [String] {
        editor.selectedRange = NSRange(location: location, length: 0)
        let menu = editor.delegate?.textView?(editor, editMenuForTextIn: editor.selectedRange, suggestedActions: [])
        func titles(_ elements: [UIMenuElement]) -> [String] {
            elements.flatMap { element -> [String] in
                if let submenu = element as? UIMenu { return titles(submenu.children) }
                return [element.title]
            }
        }
        return titles(menu?.children ?? [])
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    private func openNote(viewMode: NoteViewMode) async throws -> (MarkdownSession, UIViewController) {
        let vault = try TemporaryVault.make(prefix: "WebLinks", files: ["Links.md": Self.note], for: self)
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: [try VaultPath("Links.md")], root: vault.root)
        workspace.index = index
        await workspace.open(try VaultPath("Links.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = viewMode
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return (session, controller)
    }

    private func visibleEditor(in controller: UIViewController, showing session: MarkdownSession) async throws -> MarkdownTextView {
        func editors() -> [MarkdownTextView] { descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil } }
        try await waitUntil("the note is shown") { editors().contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        return try XCTUnwrap(editors().first { editor in editor.text == session.text })
    }

    /// The first accessibility element on screen that satisfies `matches`, once there is one.
    private func element(in controller: UIViewController, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil("the element is on screen") {
            found = self.accessibilityElements(in: controller.view).first(where: matches)
            return found != nil
        }
        return try XCTUnwrap(found)
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

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { matchingChild in [matchingChild] } ?? []) + descendants(of: child, matching: type)
        }
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
}
#endif
