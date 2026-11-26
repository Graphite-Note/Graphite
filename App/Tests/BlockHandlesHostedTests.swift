/**
 * File: BlockHandlesHostedTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The block handle of Live Preview on the iPad driven by synthesized touches: a finger's long press in the
 *              margin lifts and moves a heading's section, and neither a press on the text nor Apple Pencil lifts one.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Docs/Slash-menu-and-block-handles-todo.md, section 3, in the hosted workspace's own text
/// view, with touches sent through UIKit's event path as the screen sends them.
@MainActor
final class BlockHandlesHostedTests: XCTestCase {
    private var window: UIWindow?
    private let note = "# One\n\nText of one.\n\n# Two\n\nText of two.\n"

    override func tearDown() async throws {
        window?.endEditing(true)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private struct SynthesizedTouchesUnavailable: Error {}

    /// Touches are made through IOKit's digitizer events, which the simulator has.
    private func requireTouches() throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { throw SynthesizedTouchesUnavailable() }
    }

    func testALongPressInTheMarginLiftsAHeadingAndDraggingMovesItsSection() async throws {
        try requireTouches()
        let (editor, session, window) = try await openNote(note)
        let coordinator = try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
        let start = try marginPoint(at: "# One", in: editor, window: window)
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [start])
        await holdUntilLifted(touches, at: start, coordinator)
        XCTAssertEqual(coordinator.blockHandles.liftedBlock?.kind, .heading(level: 1), "The press lifts the heading beside it.")
        XCTAssertTrue(coordinator.blockHandles.isShown)
        attachScreenshot(named: "A heading lifted by a long press in the margin")
        let end = try marginPoint(at: "Text of two", in: editor, window: window, below: 40)
        await touches.slide(to: [end], steps: 12)
        await touches.hold(seconds: 0.2)
        XCTAssertEqual(coordinator.blockHandles.dragDestination, (note as NSString).length, "Dragged below the last line, it goes to the end.")
        attachScreenshot(named: "The drop line under the last block")
        touches.end()
        try await waitUntil("the section moved") { session.text == "# Two\n\nText of two.\n\n# One\n\nText of one.\n" }
        XCTAssertFalse(coordinator.blockHandles.isShown)
        editor.undoManager?.undo()
        try await waitUntil("one undo puts it back") { session.text == self.note }
    }

    func testALongPressWithoutMovingOpensTheBlocksMenu() async throws {
        try requireTouches()
        let (editor, session, window) = try await openNote(note)
        let coordinator = try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
        let touches = SynthesizedTouches(window: window)
        let pressPoint = try marginPoint(at: "Text of two", in: editor, window: window)
        XCTAssertFalse(editor.isFirstResponder)
        touches.begin(at: [pressPoint])
        await holdUntilLifted(touches, at: pressPoint, coordinator)
        touches.end()
        let block = try XCTUnwrap(coordinator.blockHandles.liftedBlock)
        XCTAssertEqual(block.kind, .paragraph)
        let menu = coordinator.blockHandles.menu(for: block)
        XCTAssertEqual(menu.children.map(\.title), ["Turn Into", "Duplicate", "Delete"])
        XCTAssertEqual((menu.children.first as? UIMenu)?.children.map(\.title), ["Heading 1", "Heading 2", "Heading 3", "Quote", "Callout", "Task"])
        await Task.yield()
        attachScreenshot(named: "The block's menu after a long press")
        XCTAssertEqual(session.text, note, "Opening the menu changes nothing.")
        XCTAssertFalse(editor.isFirstResponder, "The press in the margin does not start editing or move the cursor.")
    }

    func testALongPressOnTheTextLiftsNoBlock() async throws {
        try requireTouches()
        let (editor, session, window) = try await openNote(note)
        let coordinator = try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
        let onText = try marginPoint(at: "Text of one", in: editor, window: window, intoTheText: true)
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [onText])
        await holdUntilLifted(touches, at: onText, coordinator)
        touches.end()
        XCTAssertNil(coordinator.blockHandles.liftedBlock, "A press on the text is the text view's, for the cursor and selection.")
        XCTAssertFalse(coordinator.blockHandles.isShown)
        XCTAssertEqual(session.text, note)
    }

    func testApplePencilInTheMarginLiftsNoBlock() async throws {
        try requireTouches()
        XCTAssertTrue(SynthesizedTouches.canMakePencilTouches, "UIKit lets a made touch be marked as Apple Pencil's.")
        let (editor, session, window) = try await openNote(note)
        let coordinator = try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
        let pencil = SynthesizedTouches(window: window, touchType: .pencil)
        let pencilPoint = try marginPoint(at: "# One", in: editor, window: window)
        pencil.begin(at: [pencilPoint])
        await holdUntilLifted(pencil, at: pencilPoint, coordinator)
        pencil.end()
        XCTAssertNil(coordinator.blockHandles.liftedBlock, "Apple Pencil never lifts a block.")
        XCTAssertEqual(session.text, note)
    }

    // MARK: Helpers

    /// Holds the finger until the press lifts a block, or two seconds have passed. A made
    /// touch held still sends nothing UIKit's press timer counts, so the finger trembles by half
    /// a point, as a resting finger on the screen does, well within the press's allowed movement.
    private func holdUntilLifted(_ touches: SynthesizedTouches, at point: CGPoint, _ coordinator: NativeMarkdownEditor.Coordinator) async {
        for step in 0..<20 where coordinator.blockHandles.liftedBlock == nil {
            await touches.hold(seconds: 0.1)
            touches.moveTo([CGPoint(x: point.x, y: point.y + (step.isMultiple(of: 2) ? 0.5 : 0))])
        }
    }

    /// A point of the window in the left margin at the height of the line holding `text`, or
    /// on the text itself; `below` moves it down by that many points.
    private func marginPoint(at text: String, in editor: MarkdownTextView, window: UIWindow, below: CGFloat = 0, intoTheText: Bool = false) throws -> CGPoint {
        let location = (editor.text as NSString).range(of: text).location
        XCTAssertNotEqual(location, NSNotFound, text)
        let start = try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: location))
        let caret = editor.caretRect(for: start)
        let x = intoTheText ? caret.minX + 30 : editor.textContainerInset.left / 2
        return editor.convert(CGPoint(x: x, y: caret.midY + below), to: window)
    }

    private func openNote(_ text: String) async throws -> (MarkdownTextView, MarkdownSession, UIWindow) {
        let directory = try TemporaryVault.make(prefix: "BlockHandles", files: ["Blocks.md": text], for: self).root
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Blocks.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        var found: MarkdownTextView?
        try await waitUntil("the note's editor") {
            found = Self.descendants(of: controller.view).first { editor in editor.window != nil && editor.text == session.text && editor.bounds.width > 0 }
            return found != nil
        }
        let editor = try XCTUnwrap(found)
        editor.layoutIfNeeded()
        return (editor, session, window)
    }

    private static func descendants(of parent: UIView) -> [MarkdownTextView] {
        parent.subviews.flatMap { child in ((child as? MarkdownTextView).map { [$0] } ?? []) + descendants(of: child) }
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
