/**
 * File: PagePreviewCardHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Page Preview's card over the hosted workspace on the iPad: a tap on a link inside the card opens its note, and the pointer resting on a link shows the card after its delay.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Page Preview's card over the hosted workspace's panes on the iPad, with the window's own
/// cards (`LinkPreviewLayer`) as the app's root view gives them: a card held open from a link
/// in Live Preview, then a tap on a link inside it, and the editor's hover recognizer
/// reporting the pointer on a link, whose card shows once the delay of the workspace's clock
/// ends.
@MainActor
final class PagePreviewCardHostedTests: XCTestCase {
    private var window: UIWindow?

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements only while an assistive technology asks
        // for them; the tests switch the accessibility runtime on to find where the card's
        // link is drawn, as `ReadingLinkFollowingTests` does.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    private static let notes = [
        "Note.md": "# Links\n\nPlain words, then [[Target|the target]].\n",
        // The link alone on its line, so the element found is the link's own text and a tap near its start lands on it.
        "Target.md": "[[Third]]\n\nThe target's own words.\n",
        "Third.md": "The third note.\n",
    ]

    /// The card's text is selectable reading-view text: its selection model, which finds the
    /// link under a tap, has to hold the text's laid-out lines (Textual patch 20).
    func testATapOnALinkInsideTheCardOpensItsNote() async throws {
        if let reason = SynthesizedTouches.unavailableReason {
            XCTFail(reason)
            return
        }
        let workspace = try await makeWorkspace(clock: LiveApplicationClock())
        let (editor, coordinator) = try await openNoteInLivePreview(in: workspace)
        let cards = try await windowsCards(of: coordinator)

        XCTAssertTrue(coordinator.linkPreviews.press(at: try windowPoint(atStartOf: "the target", in: editor), in: editor))
        try await waitUntil("the held link's card shows") { self.shownPath(of: cards) == "Target.md" }
        let link = try await accessibilityElement(in: editor.window) { element in
            element.accessibilityLabel == "Third" && element.accessibilityTraits.contains(.staticText)
        }
        let window = try XCTUnwrap(window)
        let linkPoint = CGPoint(x: link.accessibilityFrame.minX + 8, y: link.accessibilityFrame.midY)
        try await waitUntil("the card's text selection overlay covers its link") {
            window.hitTest(linkPoint, with: nil).map(Self.isTextSelectionView) ?? false
        }
        attachScreenshot(named: "The card held open")

        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [linkPoint])
        touches.end()
        try await waitUntil("the card's link opens Third", timeoutSeconds: 5) { workspace.markdownSession?.path.rawValue == "Third.md" }
        guard case .hidden = cards.phase else { return XCTFail("Following a link of the card closes it: \(cards.phase)") }
    }

    /// The recognizer's handler, called as UIKit calls it for a trackpad's pointer or Apple
    /// Pencil hovering: the card is asked for at once and shows only when the workspace's
    /// clock ends `LinkPreviewModel.showDelay`; moving off the link closes it after
    /// `LinkPreviewModel.hideDelay`.
    func testThePointerRestingOnALinkShowsItsCardAfterTheDelay() async throws {
        let clock = HostedControlledClock()
        let workspace = try await makeWorkspace(clock: clock)
        let (editor, coordinator) = try await openNoteInLivePreview(in: workspace)
        let cards = try await windowsCards(of: coordinator)
        let hover = PointerHover(over: editor)
        let handler = NSSelectorFromString("handleLinkHover:")
        XCTAssertTrue(coordinator.responds(to: handler), "The editor's hover recognizer calls this handler.")

        hover.move(to: try windowPoint(atStartOf: "the target", in: editor), state: .began)
        _ = coordinator.perform(handler, with: hover)
        guard case .waiting(let request) = cards.phase else { return XCTFail("The card is on its way: \(cards.phase)") }
        XCTAssertEqual(request.target, "Target")
        XCTAssertEqual(request.trigger, .hover)
        try await waitUntil("the card waits for its delay") { clock.requestedDurations.contains(LinkPreviewModel.showDelay) }
        XCTAssertNil(shownPath(of: cards), "Before the delay ends, no card shows.")
        clock.endSleeps()
        try await waitUntil("the card shows once the delay ends") { self.shownPath(of: cards) == "Target.md" }
        // The card's title, a button that opens the note.
        _ = try await accessibilityElement(in: editor.window) { element in
            element.accessibilityLabel == "Target" && element.accessibilityTraits.contains(.button)
        }
        attachScreenshot(named: "The card shown by hovering")

        hover.move(to: try windowPoint(atStartOf: "Plain", in: editor), state: .changed)
        _ = coordinator.perform(handler, with: hover)
        try await waitUntil("off the link, the card waits to close") { clock.requestedDurations.contains(LinkPreviewModel.hideDelay) }
        XCTAssertEqual(shownPath(of: cards), "Target.md", "The card stays while the pointer could still reach it.")
        clock.endSleeps()
        try await waitUntil("the card closes once its delay ends") { if case .hidden = cards.phase { true } else { false } }
    }

    // MARK: Helpers

    /// A hover recognizer that reports a pointer at a chosen point, given to the editor's
    /// handler in place of the one UIKit drives: a hosted test cannot move a pointer.
    private final class PointerHover: UIHoverGestureRecognizer {
        private weak var hoveredView: UIView?
        private var windowPoint = CGPoint.zero
        private var reportedState = UIGestureRecognizer.State.possible

        init(over hoveredView: UIView) {
            self.hoveredView = hoveredView
            super.init(target: nil, action: nil)
        }

        func move(to windowPoint: CGPoint, state: UIGestureRecognizer.State) {
            self.windowPoint = windowPoint
            reportedState = state
        }

        override var view: UIView? { hoveredView }

        override var state: UIGestureRecognizer.State {
            get { reportedState }
            set { reportedState = newValue }
        }

        override func location(in view: UIView?) -> CGPoint {
            view.map { view in view.convert(windowPoint, from: nil) } ?? windowPoint
        }
    }

    private func makeWorkspace(clock: any ApplicationClock) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "PagePreviewCard", files: Self.notes, for: self)
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = WorkspaceModel(processServices: .live(), clock: clock)
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: Self.notes.keys.map { name in try VaultPath(name) }, root: vault.root)
        workspace.index = index
        return workspace
    }

    /// `Note.md` in Live Preview in the workspace's panes, in a window of its own, under the
    /// window's preview cards as `GraphiteRootView` puts them there while Page Preview is on.
    private func openNoteInLivePreview(in workspace: WorkspaceModel) async throws -> (MarkdownTextView, NativeMarkdownEditor.Coordinator) {
        let path = try VaultPath("Note.md")
        await workspace.open(path, placement: .currentTab)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }.modifier(LinkPreviewLayer(isEnabled: true, vault: workspace.linkPreviewVault))))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        func editors() -> [MarkdownTextView] { descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil } }
        try await waitUntil { editors().contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        let editor = try XCTUnwrap(editors().first { editor in editor.text == session.text })
        editor.layoutIfNeeded()
        return (editor, try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator))
    }

    /// The window's cards, once the editor was given them from the environment.
    private func windowsCards(of coordinator: NativeMarkdownEditor.Coordinator) async throws -> LinkPreviewModel {
        try await waitUntil("the editor watches the pointer for the window's cards") { coordinator.linkPreviews.model != nil }
        return try XCTUnwrap(coordinator.linkPreviews.model)
    }

    private func shownPath(of cards: LinkPreviewModel) -> String? {
        if case .shown(_, let content) = cards.phase { content.path.rawValue } else { nil }
    }

    /// The middle of the first character of `substring`, in window coordinates.
    private func windowPoint(atStartOf substring: String, in editor: MarkdownTextView) throws -> CGPoint {
        editor.layoutIfNeeded()
        let location = (editor.text as NSString).range(of: substring).location
        let start = try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: location))
        let end = try XCTUnwrap(editor.position(from: start, offset: 1))
        let rect = editor.convert(editor.firstRect(for: try XCTUnwrap(editor.textRange(from: start, to: end))), to: nil)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    private static func isTextSelectionView(_ view: UIView) -> Bool {
        String(describing: type(of: view)) == "UITextInteractionView"
    }

    /// The first accessibility element in `window` that satisfies `matches`, once there is one.
    private func accessibilityElement(in window: UIWindow?, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        let window = try XCTUnwrap(window)
        var found: NSObject?
        try await waitUntil("the accessibility element") {
            found = self.accessibilityElements(in: window).first(where: matches)
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
