/**
 * File: UiEditorMacBlockHandlesTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The block handle of the Mac's Live Preview driven by mouse events: shown on hover, a heading's section
 *              dragged to the end, a paragraph turned into a callout from its menu, each undone in one step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiEditorMacBlockHandlesTests: XCTestCase {
    private var windows: [NSWindow] = []
    private let note = "# One\n\nText of one.\n\n# Two\n\nText of two.\n"

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        try await super.tearDown()
    }

    private func makeEditor(text: String, mode: EditingMode = .livePreview) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = mode
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let noteView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        scrollView.frame = noteView.bounds
        noteView.addSubview(scrollView)
        let window = NSWindow(contentRect: noteView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        windows.append(window)
        window.contentView = noteView
        window.showInvisibly()
        window.makeFirstResponder(textView)
        textView.layoutSubtreeIfNeeded()
        return (coordinator, textView)
    }

    /// A point of the window at the height of the line holding `text`, over the text.
    private func windowPoint(at text: String, in textView: NSTextView, xOffset: CGFloat = 20) throws -> CGPoint {
        let location = (textView.string as NSString).range(of: text).location
        XCTAssertNotEqual(location, NSNotFound, text)
        let screenRect = textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
        let window = try XCTUnwrap(textView.window)
        let rect = window.convertFromScreen(screenRect)
        return CGPoint(x: rect.minX + xOffset, y: rect.midY)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in textView: NSTextView) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: 0, windowNumber: textView.window?.windowNumber ?? 0,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: type == .mouseMoved ? 0 : 1))
    }

    private func handleView(in textView: NSTextView) throws -> MacBlockHandleView {
        try XCTUnwrap(textView.subviews.compactMap { view in view as? MacBlockHandleView }.first { view in !view.isHidden }, "The handle shows.")
    }

    private func hover(_ text: String, in textView: NSTextView) throws {
        textView.mouseMoved(with: try mouseEvent(.mouseMoved, at: try windowPoint(at: text, in: textView), in: textView))
    }

    func testTheHandleShowsBesideTheBlockUnderThePointerAndGoesWhenItLeaves() async throws {
        let (coordinator, textView) = try await makeEditor(text: note)
        try hover("Text of one", in: textView)
        XCTAssertEqual(coordinator.blockHandles.shownBlock?.kind, .paragraph)
        let handle = try handleView(in: textView)
        let lineY = textView.convert(try windowPoint(at: "Text of one", in: textView), from: nil).y
        XCTAssertEqual(handle.frame.midY, lineY, accuracy: 4, "The handle is at the block's first line.")
        XCTAssertLessThan(handle.frame.maxX, textView.textContainerOrigin.x + 4, "It is in the left margin.")
        try hover("# Two", in: textView)
        XCTAssertEqual(coordinator.blockHandles.shownBlock?.kind, .heading(level: 1))
        let exit = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: textView.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                                                         trackingNumber: 0, userData: nil))
        textView.mouseExited(with: exit)
        XCTAssertFalse(coordinator.blockHandles.isShown, "No handle stays when the pointer leaves the note.")
    }

    func testDraggingAHeadingsHandleMovesItsSectionAndOneUndoPutsItBack() async throws {
        let (coordinator, textView) = try await makeEditor(text: note)
        try hover("# One", in: textView)
        let handle = try handleView(in: textView)
        let handleCenter = textView.convert(CGPoint(x: handle.frame.midX, y: handle.frame.midY), to: nil)
        handle.mouseDown(with: try mouseEvent(.leftMouseDown, at: handleCenter, in: textView))
        let belowTheNote = try windowPoint(at: "Text of two", in: textView)
        let target = CGPoint(x: belowTheNote.x, y: belowTheNote.y - 40)
        handle.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: target, in: textView))
        XCTAssertEqual(coordinator.blockHandles.dragDestination, (note as NSString).length, "Dragged below the last line, the block goes to the end.")
        handle.mouseUp(with: try mouseEvent(.leftMouseUp, at: target, in: textView))
        XCTAssertEqual(textView.string, "# Two\n\nText of two.\n\n# One\n\nText of one.\n")
        XCTAssertEqual(coordinator.session.text, textView.string)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, note, "One undo puts the section back.")
    }

    func testTheMenuTurnsAParagraphIntoACallout() async throws {
        let (coordinator, textView) = try await makeEditor(text: note)
        try hover("Text of two", in: textView)
        let block = try XCTUnwrap(coordinator.blockHandles.shownBlock)
        let menu = coordinator.blockHandles.menu(for: block)
        XCTAssertEqual(menu.items.map(\.title).filter { title in !title.isEmpty }, ["Turn Into", "Duplicate", "Delete"])
        let turnInto = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(turnInto.items.map(\.title), ["Heading 1", "Heading 2", "Heading 3", "Quote", "Callout", "Task"])
        let calloutIndex = try XCTUnwrap(turnInto.items.firstIndex { item in item.title == "Callout" })
        turnInto.performActionForItem(at: calloutIndex)
        XCTAssertEqual(textView.string, "# One\n\nText of one.\n\n# Two\n\n> [!note]\n> Text of two.\n")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, note)
    }

    func testAHeadingsMenuOffersItsOtherLevelsAndBody() async throws {
        let (coordinator, textView) = try await makeEditor(text: note)
        try hover("# Two", in: textView)
        let menu = coordinator.blockHandles.menu(for: try XCTUnwrap(coordinator.blockHandles.shownBlock))
        XCTAssertEqual(menu.items.first?.submenu?.items.map(\.title), ["Heading 2", "Heading 3", "Body"])
    }

    func testSourceModeShowsNoHandleAndDoesNotWatchThePointer() async throws {
        let (coordinator, textView) = try await makeEditor(text: note, mode: .source)
        try hover("Text of one", in: textView)
        XCTAssertFalse(coordinator.blockHandles.isShown)
        XCTAssertFalse(coordinator.blockHandles.watchesPointer)
    }

    func testCancellingADragMovesNothing() async throws {
        let (coordinator, textView) = try await makeEditor(text: note)
        try hover("# One", in: textView)
        let handle = try handleView(in: textView)
        let handleCenter = textView.convert(CGPoint(x: handle.frame.midX, y: handle.frame.midY), to: nil)
        handle.mouseDown(with: try mouseEvent(.leftMouseDown, at: handleCenter, in: textView))
        let target = try windowPoint(at: "Text of two", in: textView)
        handle.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: CGPoint(x: target.x, y: target.y - 40), in: textView))
        XCTAssertNotNil(coordinator.blockHandles.dragDestination)
        // What Escape does during a drag.
        coordinator.blockHandles.cancelDrag()
        handle.cancelTracking()
        handle.mouseUp(with: try mouseEvent(.leftMouseUp, at: target, in: textView))
        XCTAssertEqual(textView.string, note, "A cancelled drag moves nothing.")
    }

    func testTypingHidesTheHandle() async throws {
        let (coordinator, textView) = try await makeEditor(text: note)
        try hover("Text of one", in: textView)
        XCTAssertTrue(coordinator.blockHandles.isShown)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        XCTAssertFalse(coordinator.blockHandles.isShown)
    }
}
#endif
