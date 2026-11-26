/**
 * File: MacPDFMarkupInAppHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The Mac's PDF markup row used in Graphite's own window inside the running Mac app: the toolbar's markup
 *              button and the row's buttons pressed by mouse events through AppKit, text marked, a text box, a shape,
 *              ink and a signature placed, with pictures of each step written for a person to look at.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Docs/Mac-PDF-markup-todo.md: the checks "in the running app". Computer use was declined and a Mac UI test needs
/// Automation Mode, so this runs inside the app as a hosted test: Graphite's root view in a window of the app, its
/// controls found through the accessibility the app vends and pressed with mouse events sent through the window, as a
/// click arrives. Runs only with `TEST_RUNNER_GRAPHITE_MAC_MARKUP` given to xcodebuild as a folder, where it writes a
/// picture of each step and the window's accessibility tree; a person looks at them.
@MainActor
final class MacPDFMarkupInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_MARKUP"
    private var outputFolder: URL?
    private var openedSession: PDFSession?
    private var pictureCount = 0

    func testTheMarkupRowInTheRunningApp() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        let opened = try await openLectureSlides()
        let window = opened.window
        try await settle(window)
        try writePicture("pdf open", of: window)
        try writeTree("tree before", of: window)
        try writeToolbarItems(of: window)
        try note("window \(window.frame) on screen \(window.screen?.frame ?? .zero), app active \(NSApp.isActive), pointer \(NSEvent.mouseLocation), "
                 + "buttons \(NSEvent.pressedMouseButtons)")
        try await click(atWindowPoint: try toolbarItemCenter(labelled: "Show Markup Toolbar", in: window), in: window)
        try writePicture("row shown", of: window)
        try writeTree("tree with row", of: window)
        XCTAssertEqual(try toolbarItem(labelled: "Hide Markup Toolbar", in: window).toolTip, "Hide Markup Toolbar", "the button now hides the row")
        let session = try XCTUnwrap(opened.workspace.pdfSession)
        openedSession = session
        // AppKit closes the undo group an event opened when the app's event loop finishes that event, but XCTest runs the
        // whole test inside one turn of that loop: the group stayed open (2026-11-16: still open after two idle seconds,
        // and one Undo took back every step), and closing it by hand put AppKit's grouping out of step. Each action of
        // the test is one group of its own instead (`asOneAction`), as each of a person's clicks is.
        session.undoManager.groupsByEvent = false
        let pdfView = try XCTUnwrap(ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: GraphiteMacPDFView.self).first)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let pages = PageInWindow(view: pdfView, page: page)

        // Highlight: the green swatch, then a drag across the first line of text.
        window.makeKey()
        try await choose(.highlight, atRowX: 417, in: window, view: pdfView)
        try await selectAndLetGo(of: "A continuous signal", in: session, view: pdfView, window: window)
        try note("after the highlight drag: key=\(window.isKeyWindow) first responder=\(String(describing: window.firstResponder)) "
                 + "selection=\(pdfView.currentSelection?.string ?? "none") hit=\(String(describing: window.contentView?.hitTest(try pages.acrossText("A continuous signal", in: session)[2])))")
        try writePicture("green highlight", of: window)
        try note("\(Self.undoState(session)) after \("green highlight")")
        try writeAnnotations("after highlight", of: page)
        XCTAssertEqual(markups(on: page, of: .highlight).count, 1, "the line is highlighted once")

        // Underline: its button, then a drag across the second line.
        try await choose(.highlight, atRowX: 543, in: window, view: pdfView, style: "Underline")
        try await selectAndLetGo(of: "The sampling rate", in: session, view: pdfView, window: window)
        try writePicture("underline", of: window)
        XCTAssertEqual(markups(on: page, of: .underline).count, 1, "the line is underlined once")

        // Draw: a zigzag under the text.
        try await choose(.draw, atRowX: 662, in: window, view: pdfView)
        try await drag(through: (0...8).map { step in pages.windowPoint(CGPoint(x: 120 + Double(step) * 30, y: 140 + Double(step % 2) * 30)) }, in: window)
        try writePicture("drawn", of: window)
        try note("\(Self.undoState(session)) after \("drawn")")
        try writeAnnotations("after drawing", of: page)

        // Text Box: a click places a box, typing fills it, Escape ends typing.
        try await choose(.textBox, atRowX: 734, in: window, view: pdfView)
        try await click(atWindowPoint: pages.windowPoint(CGPoint(x: 420, y: 120)), in: window)
        try await type("Sampling theorem", in: window)
        try await press(.escape, in: window)
        try writePicture("text box", of: window)
        try note("\(Self.undoState(session)) after \("text box")")
        XCTAssertEqual(session.textBoxes(on: page).map(\.plainText), ["Sampling theorem"])

        // Shapes: a rectangle dragged over the box's corner.
        try await choose(.shapes, atRowX: 798, in: window, view: pdfView)
        try await drag(through: [pages.windowPoint(CGPoint(x: 400, y: 90)), pages.windowPoint(CGPoint(x: 470, y: 120)), pages.windowPoint(CGPoint(x: 540, y: 160))], in: window)
        try writePicture("shape", of: window)
        try note("\(Self.undoState(session)) after \("shape")")
        try writeAnnotations("after shape", of: page)

        // Undo from the toolbar takes the shape back, Redo puts it back.
        let annotationCountWithShape = page.annotations.count
        try note("after the shape: \(page.annotations.map { annotation in annotation.type ?? "?" })")
        try note("before Undo: can undo \(session.undoManager.canUndo) named \(session.undoManager.undoActionName)")
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Undo", share: 0.25, in: window), in: window, isUndoOrRedo: true)
        try note("after Undo: \(page.annotations.map { annotation in annotation.type ?? "?" }), next undo \(session.undoManager.undoActionName)")
        XCTAssertEqual(page.annotations.count, annotationCountWithShape - 1, "Undo took the shape off")
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Redo", share: 0.25, in: window), in: window, isUndoOrRedo: true)
        XCTAssertEqual(page.annotations.count, annotationCountWithShape, "Redo put it back")
        try writePicture("undone and redone", of: window)

        // The right-click menu of the shape, with its Arrange commands.
        let shapePoint = pages.windowPoint(CGPoint(x: 530, y: 150))
        let viewUnderPointer = try XCTUnwrap(window.contentView?.hitTest(shapePoint))
        try note("under the shape: \(viewUnderPointer)")
        let shapeMenu = viewUnderPointer.menu(for: try mouseEvent(.rightMouseDown, at: shapePoint, in: window))
        try writeMenu("shape right-click", shapeMenu)
        let sendToBack = try XCTUnwrap(shapeMenu.flatMap { menu in item(titled: "Send Item to Back", in: menu) }, "the shape's menu has Send Item to Back")
        let sendToBackMenu = try XCTUnwrap(sendToBack.menu)
        try note("choosing Send to Back, item \(sendToBackMenu.index(of: sendToBack))")
        try await asOneAction {
            sendToBackMenu.performActionForItem(at: sendToBackMenu.index(of: sendToBack))
            try await settle(window)
        }
        try note("after Send to Back: \(page.annotations.map { annotation in annotation.type ?? "?" })")
        let shapeIndex = try XCTUnwrap(page.annotations.firstIndex { annotation in annotation.type == "Square" })
        XCTAssertLessThan(shapeIndex, try XCTUnwrap(page.annotations.firstIndex { annotation in annotation.type == "FreeText" }), "sent under the box")
        try writeAnnotations("after send to back", of: page)
        try writePicture("shape sent to back", of: window)

        // Eraser across the zigzag.
        try await choose(.eraseInk, atRowX: 695, in: window, view: pdfView)
        try await drag(through: [pages.windowPoint(CGPoint(x: 150, y: 120)), pages.windowPoint(CGPoint(x: 260, y: 190))], in: window)
        try writePicture("erased", of: window)
        try writeAnnotations("after eraser", of: page)

        // The text box by the pointer and the keyboard: selected by a click, moved by a drag, made bold from the row,
        // duplicated with Command-D, its right-click menu, deleted with Delete.
        try await choose(.textBox, atRowX: 734, in: window, view: pdfView)
        let boxBefore = try freeTextBounds(on: page)
        try await click(atWindowPoint: pages.windowPoint(onPage: CGPoint(x: boxBefore.midX, y: boxBefore.midY)), in: window)
        try await drag(through: [0.0, 0.5, 1.0].map { share in
            pages.windowPoint(onPage: CGPoint(x: boxBefore.midX + share * 60, y: boxBefore.midY - share * 60))
        }, in: window)
        let boxMoved = try freeTextBounds(on: page)
        try note("box moved from \(boxBefore.integral) to \(boxMoved.integral), undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(boxMoved.midX - boxBefore.midX, 60, accuracy: 2, "moved right with the pointer")
        XCTAssertEqual(boxMoved.midY - boxBefore.midY, -60, accuracy: 2, "moved down with the pointer")
        try await click(atWindowPoint: Self.rowPoint(x: 1087), in: window)
        try note("after Bold: bold \(session.textBoxes(on: page).first?.leadingAttributes.isBold ?? false), undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(session.textBoxes(on: page).first?.leadingAttributes.isBold, true, "the row's Bold made the selected box bold")
        try writePicture("box moved and bold", of: window)
        try await pressKey("d", keyCode: 2, modifiers: .command, in: window)
        try note("after Command-D: \(session.textBoxes(on: page).count) boxes, undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(session.textBoxes(on: page).count, 2, "Command-D duplicated the box")
        try writePicture("box duplicated", of: window)
        let duplicatePoint = pages.windowPoint(onPage: CGPoint(x: try freeTextBounds(on: page, last: true).midX, y: try freeTextBounds(on: page, last: true).midY))
        let boxMenuView = try XCTUnwrap(window.contentView?.hitTest(duplicatePoint))
        try writeMenu("text box right-click", boxMenuView.menu(for: try mouseEvent(.rightMouseDown, at: duplicatePoint, in: window)))
        try await pressKey(String(UnicodeScalar(UInt8(127))), keyCode: 51, modifiers: [], in: window)
        try note("after Delete: \(session.textBoxes(on: page).count) boxes, undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(session.textBoxes(on: page).count, 1, "Delete removed the selected box")

        // The remaining box made wider by the handle on its trailing side, then a double-click to type at its end.
        let boxToResize = try freeTextBounds(on: page)
        try await click(atWindowPoint: pages.windowPoint(onPage: CGPoint(x: boxToResize.midX, y: boxToResize.midY)), in: window)
        try await drag(through: [0.0, 0.5, 1.0].map { share in
            pages.windowPoint(onPage: CGPoint(x: boxToResize.maxX + share * 40, y: boxToResize.midY))
        }, in: window)
        let boxResized = try freeTextBounds(on: page)
        try note("box resized from \(boxToResize.integral) to \(boxResized.integral), undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(boxResized.width - boxToResize.width, 40, accuracy: 2, "the handle widened the box")
        XCTAssertEqual(boxResized.minX, boxToResize.minX, accuracy: 1, "its leading side stayed")
        // Three quarters across: the handle at the trailing side takes a press within its reach, double or not.
        let typingPoint = pages.windowPoint(onPage: CGPoint(x: boxResized.minX + boxResized.width * 0.75, y: boxResized.midY))
        try await asOneAction {
            for clickCount in 1...2 {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    NSApp.postEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: typingPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)),
                                    atStart: false)
                }
            }
            try await settle(window)
        }
        try note("after the double-click: first responder \(String(describing: window.firstResponder).prefix(120))")
        try await type(" (Nyquist)", in: window)
        try await press(.escape, in: window)
        try note("after a double-click and typing: \(session.textBoxes(on: page).map(\.plainText)), undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(session.textBoxes(on: page).first?.plainText.contains("(Nyquist)"), true, "a double-click typed in the box")
        try writePicture("box resized and typed in", of: window)

        // A picture with the Images tool, and its right-click menu's Bring to Front.
        try await asOneAction { try await session.addPicture(imageData: try Self.redSquarePNG(), placement: (pageIndex: 0, center: CGPoint(x: 480, y: 470))) }
        try await choose(.pictures, atRowX: 882, in: window, view: pdfView)
        let picturePoint = pages.windowPoint(onPage: CGPoint(x: 480, y: 470))
        let pictureMenuView = try XCTUnwrap(window.contentView?.hitTest(picturePoint))
        let pictureMenu = pictureMenuView.menu(for: try mouseEvent(.rightMouseDown, at: picturePoint, in: window))
        try writeMenu("picture right-click", pictureMenu)
        XCTAssertEqual(pictureMenu?.items.first?.title, "Bring Image to Front", "the menu opens on its first command, not a line")
        try note("before Bring to Front: \(page.annotations.map { annotation in annotation.type ?? "?" })")
        let bringToFront = try XCTUnwrap(pictureMenu.flatMap { menu in item(titled: "Bring Image to Front", in: menu) }, "the picture's menu has Bring Image to Front")
        let bringToFrontMenu = try XCTUnwrap(bringToFront.menu)
        try await asOneAction {
            bringToFrontMenu.performActionForItem(at: bringToFrontMenu.index(of: bringToFront))
            try await settle(window)
        }
        try note("after Bring to Front: \(page.annotations.map { annotation in annotation.type ?? "?" }), undo named \"\(session.undoManager.undoActionName)\"")
        try writePicture("picture brought to front", of: window)

        // A note: the Note tool, a click on the page opens it, typing fills it, closing it places it.
        try await choose(.note, atRowX: 766, in: window, view: pdfView)
        try await click(atWindowPoint: pages.windowPoint(CGPoint(x: 60, y: 300)), in: window)
        let noteEditor = try XCTUnwrap(pdfView.markupInteraction?.openNoteEditor, "the note opened to type in")
        XCTAssertTrue(noteEditor.isOpen)
        try writePicture("note open", of: window)
        try await asOneAction {
            let textView = try XCTUnwrap(noteEditor.textView)
            textView.insertText("Ask about aliasing", replacementRange: NSRange(location: 0, length: 0))
            noteEditor.close()
            try await settle(window)
        }
        let placedNote = try XCTUnwrap(page.annotations.compactMap(PDFNote.init(annotation:)).first)
        try note("note placed: \(placedNote.contents) at \(placedNote.iconBounds.integral), undo named \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(placedNote.contents, "Ask about aliasing")
        try writePicture("note placed", of: window)
        try writeMenu("note right-click", pdfView.menu(for: try mouseEvent(.rightMouseDown, at: pages.windowPoint(onPage: CGPoint(x: placedNote.iconBounds.midX, y: placedNote.iconBounds.midY)), in: window)))

        // Saved and read back from the file, as another application reads it.
        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: session.location))
        try writeAnnotations("saved file", of: try XCTUnwrap(saved.page(at: 0)))
        try FileManager.default.copyItem(at: session.location, to: try XCTUnwrap(outputFolder).appendingPathComponent("Lecture slides marked.pdf"))
    }

    /// A place in the markup row: its middle line, `x` points from the window's left edge (read from a picture of the row
    /// in this window of 1,280 by 860 points, as a person finds a control).
    private static func undoState(_ session: PDFSession) -> String {
        "grouping level \(session.undoManager.groupingLevel), by event \(session.undoManager.groupsByEvent), undo named \"\(session.undoManager.undoActionName)\""
    }

    private static func rowPoint(x: Double) -> CGPoint {
        CGPoint(x: x, y: 860 - 113)
    }

    /// The bounds of the page's first text box (or its last), in the page's space.
    private func freeTextBounds(on page: PDFPage, last: Bool = false) throws -> CGRect {
        let boxes = page.annotations.filter { annotation in annotation.type == "FreeText" }
        return try XCTUnwrap(last ? boxes.last : boxes.first, "a text box on the page").bounds
    }

    private static func redSquarePNG() throws -> Data {
        let representation = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4,
                                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    private func markups(on page: PDFPage, of subtype: PDFAnnotationSubtype) -> [PDFAnnotation] {
        page.annotations.filter { annotation in annotation.type == subtype.rawValue.replacingOccurrences(of: "/", with: "") }
    }

    // MARK: The window

    private struct OpenedPDF {
        let window: NSWindow
        let workspace: WorkspaceModel
    }

    private func openLectureSlides() async throws -> OpenedPDF {
        let vaultRoot = try TemporaryVault.make(prefix: "MacMarkupInApp", for: self).root
        let slides = FixtureFolders.releaseVault.appendingPathComponent("PDFs/Lecture slides.pdf")
        try FileManager.default.copyItem(at: slides, to: vaultRoot.appendingPathComponent("Lecture slides.pdf"))
        try Data("# Notes\n".utf8).write(to: vaultRoot.appendingPathComponent("Notes.md"))
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        _ = await workspace.open(try VaultPath("Lecture slides.pdf"), placement: .currentTab)
        try await waitUntil("the PDF is shown", timeoutSeconds: 30) { (workspace.pdfSession?.pageCount ?? 0) > 0 }
        return OpenedPDF(window: window, workspace: workspace)
    }

    /// Runs one action of a person's (a click, a drag, a word typed) as one undo group.
    private func asOneAction(_ action: () async throws -> Void) async throws {
        guard let undoManager = openedSession?.undoManager else { return try await action() }
        undoManager.beginUndoGrouping()
        var thrown: (any Error)?
        do { try await action() } catch { thrown = error }
        undoManager.endUndoGrouping()
        if let thrown { throw thrown }
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 20).measure({}, until: { true })
    }

    // MARK: Pressing controls

    private func element(labelled label: String, in window: NSWindow) throws -> MacAccessibilityTree.Element {
        try XCTUnwrap(MacAccessibilityTree.find(labelled: label, in: window), "no control labelled \(label)")
    }

    /// Clicks a tool of the markup row at `x` and waits until the PDF view has it (and the style, for a mark), clicking
    /// again when a click was lost: a click that comes within a double-click's time of the last one at another place
    /// was seen to be dropped (2026-11-16, the Draw button after a triple-click on the text).
    private func choose(_ tool: PDFMarkupTool, atRowX x: Double, in window: NSWindow, view: GraphiteMacPDFView, style: String? = nil) async throws {
        let hasIt = { @MainActor in
            view.markupInteraction?.input.markupTool == tool && (style.map { title in view.markupInteraction?.input.markupStyle.title == title } ?? true)
        }
        for _ in 1...3 where !hasIt() {
            try await click(atWindowPoint: Self.rowPoint(x: x), in: window)
            for _ in 0..<5 where !hasIt() { try await settle(window) }
        }
        XCTAssertTrue(hasIt(), "the row chose \(tool.title)")
    }

    /// A toolbar item by the label SwiftUI gives it (the button's title).
    private func toolbarItem(labelled label: String, in window: NSWindow) throws -> NSToolbarItem {
        try XCTUnwrap(window.toolbar?.items.first { item in item.label == label }, "no toolbar item labelled \(label)")
    }

    private func toolbarItemCenter(labelled label: String, in window: NSWindow) throws -> CGPoint {
        try toolbarItemPoint(labelled: label, share: 0.5, in: window)
    }

    /// A point `share` of the way across the item, for an item whose arrow menu takes its right half (Undo, Redo).
    private func toolbarItemPoint(labelled label: String, share: Double, in window: NSWindow) throws -> CGPoint {
        let view = try XCTUnwrap(try toolbarItem(labelled: label, in: window).view)
        let frame = view.convert(view.bounds, to: nil)
        return CGPoint(x: frame.minX + share * frame.width, y: frame.midY)
    }

    /// A press and release of the left button at `windowPoint` (the window's own coordinates, origin at the bottom
    /// left), sent through the window as a click arrives.
    /// `isUndoOrRedo` for Undo and Redo themselves, which must not open a group of their own: an undo with a group open
    /// takes back that empty group.
    private func click(atWindowPoint windowPoint: CGPoint, in window: NSWindow, isUndoOrRedo: Bool = false) async throws {
        if isUndoOrRedo {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { NSApp.postEvent(try mouseEvent(type, at: windowPoint, in: window), atStart: false) }
            return try await settle(window)
        }
        // Through the application's queue, as a hand's click arrives: each event is its own turn of the run loop, which
        // closes the undo group an action opened.
        try await asOneAction {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { NSApp.postEvent(try mouseEvent(type, at: windowPoint, in: window), atStart: false) }
            try await settle(window)
        }
    }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    /// The line of `text` selected as a drag across it leaves it, then the mouse button let go through the view, which is
    /// where Graphite's highlighter marks it. PDFKit follows a selection drag by the buttons the hardware holds, which an
    /// event put in the queue does not press; posted triple-clicks selected the line in one run of 2026-11-16 and left
    /// PDFKit swallowing every later click in the next.
    private func selectAndLetGo(of text: String, in session: PDFSession, view: GraphiteMacPDFView, window: NSWindow) async throws {
        let found = try XCTUnwrap(session.document.findString(text, withOptions: []).first)
        let line = try XCTUnwrap(found.selectionsByLine().first)
        line.extendForLineBoundaries()
        try await asOneAction {
            view.setCurrentSelection(line, animate: false)
            let page = try XCTUnwrap(line.pages.first)
            let bounds = line.bounds(for: page)
            view.mouseUp(with: try mouseEvent(.leftMouseUp, at: view.convert(view.convert(CGPoint(x: bounds.maxX, y: bounds.midY), from: page), to: nil), in: window))
            try await settle(window)
        }
    }

    /// A press, a drag through the points and a release, put in the application's queue in order, so that a view
    /// tracking the drag in a loop of its own (PDFKit's text selection) reads them as it reads a hand's.
    private func drag(through windowPoints: [CGPoint], in window: NSWindow) async throws {
        guard let first = windowPoints.first, let last = windowPoints.last else { return }
        var events = [try mouseEvent(.leftMouseDown, at: first, in: window)]
        for point in windowPoints.dropFirst() { events.append(try mouseEvent(.leftMouseDragged, at: point, in: window)) }
        events.append(try mouseEvent(.leftMouseUp, at: last, in: window))
        try await asOneAction {
            for event in events { NSApp.postEvent(event, atStart: false) }
            try await settle(window)
        }
    }

    private func type(_ text: String, in window: NSWindow) async throws {
        try await asOneAction {
            for character in text {
                let characters = String(character)
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
                NSApp.postEvent(event, atStart: false)
            }
            try await settle(window)
        }
    }

    private enum Key { case escape }

    private func press(_ key: Key, in window: NSWindow) async throws {
        let characters = String(UnicodeScalar(UInt8(27)))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: characters,
                                                   charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 53))
        try await asOneAction {
            NSApp.postEvent(event, atStart: false)
            try await settle(window)
        }
    }

    private func pressKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in window: NSWindow) async throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: characters,
                                                   charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        try await asOneAction {
            NSApp.postEvent(event, atStart: false)
            try await settle(window)
        }
    }

    private func item(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let submenu = item.submenu, let found = self.item(titled: title, in: submenu) { return found }
        }
        return nil
    }

    // MARK: Output

    private var notes: [String] = []

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    private func writeMenu(_ name: String, _ menu: NSMenu?) throws {
        func lines(_ menu: NSMenu, depth: Int) -> [String] {
            menu.items.flatMap { item in
                [String(repeating: "  ", count: depth) + (item.isSeparatorItem ? "—" : item.title) + (item.isEnabled ? "" : " (dimmed)")]
                    + (item.submenu.map { submenu in lines(submenu, depth: depth + 1) } ?? [])
            }
        }
        let text = menu.map { menu in lines(menu, depth: 0).joined(separator: "\n") } ?? "no menu"
        try Data(text.utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("\(name).txt"))
    }

    private func writeAnnotations(_ name: String, of page: PDFPage) throws {
        let lines = page.annotations.map { annotation in
            "\(annotation.type ?? "?") \(annotation.bounds.integral) colour=\(annotation.color.usingColorSpace(.sRGB).map { color in String(format: "%.2f %.2f %.2f", color.redComponent, color.greenComponent, color.blueComponent) } ?? "?") "
                + "contents=\"\(annotation.contents ?? "")\""
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("\(name).txt"))
    }

    /// The window's content with the PDF's pages drawn in, and its whole frame with the toolbar (whose pages are blank).
    private func writePicture(_ name: String, of window: NSWindow) throws {
        let pngData = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        pictureCount += 1
        let folder = try XCTUnwrap(outputFolder)
        try pngData.write(to: folder.appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let representation = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: representation)
        try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            .write(to: folder.appendingPathComponent(String(format: "%02d %@ (frame).png", pictureCount, name)))
    }

    private func writeToolbarItems(of window: NSWindow) throws {
        let folder = try XCTUnwrap(outputFolder)
        let lines = (window.toolbar?.items ?? []).map { item in
            "\(item.itemIdentifier.rawValue) label=\"\(item.label)\" tip=\"\(item.toolTip ?? "")\" view=\(item.view.map { view in String(describing: Swift.type(of: view)) } ?? "nil") "
                + "frame=\(item.view.map { view in view.convert(view.bounds, to: nil) } ?? .zero)"
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: folder.appendingPathComponent("toolbar items.txt"))
    }

    private func writeTree(_ name: String, of window: NSWindow) throws {
        let folder = try XCTUnwrap(outputFolder)
        let lines = MacAccessibilityTree.elements(in: window).map { element in
            "\(String(repeating: "  ", count: element.depth))\(element.role) \"\(element.label)\" \(element.screenFrame.integral)"
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: folder.appendingPathComponent("\(name).txt"))
    }
}

/// A page of a PDF view and the window's coordinates of its points.
@MainActor
private struct PageInWindow {
    let view: PDFView
    let page: PDFPage

    /// `pagePoint` in the page's own space, from its top left corner as a person measures it on the page.
    func windowPoint(_ pointFromTop: CGPoint) -> CGPoint {
        let box = page.bounds(for: view.displayBox)
        let pagePoint = CGPoint(x: box.minX + pointFromTop.x, y: box.maxY - pointFromTop.y)
        return view.convert(view.convert(pagePoint, from: page), to: nil)
    }

    /// `pagePoint` in the page's own space (from its bottom left corner, as PDFKit measures).
    func windowPoint(onPage pagePoint: CGPoint) -> CGPoint {
        view.convert(view.convert(pagePoint, from: page), to: nil)
    }

    /// A drag from just before the first letter of `text` on the page to just after its last, along its middle.
    func acrossText(_ text: String, in session: PDFSession) throws -> [CGPoint] {
        let found = try XCTUnwrap(session.document.findString(text, withOptions: []).first { selection in selection.pages.contains(page) })
        let bounds = found.bounds(for: page)
        return [0.0, 0.25, 0.5, 0.75, 1.0].map { share in
            let pagePoint = CGPoint(x: bounds.minX + 1 + share * (bounds.width - 2), y: bounds.midY)
            return view.convert(view.convert(pagePoint, from: page), to: nil)
        }
    }
}

/// The accessibility elements a window of this app vends, read in its own process.
@MainActor
enum MacAccessibilityTree {
    struct Element {
        let object: NSObject
        let role: String
        let label: String
        let screenFrame: CGRect
        let depth: Int
    }

    static func elements(in window: NSWindow) -> [Element] {
        var found: [Element] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 60, visited.insert(ObjectIdentifier(object)).inserted else { return }
            let label = ["accessibilityLabel", "accessibilityTitle", "accessibilityHelp"].lazy
                .compactMap { key in attribute(key, of: object) as? String }.first { text in !text.isEmpty } ?? ""
            let role = (attribute("accessibilityRole", of: object) as? String) ?? ""
            let frame = (attribute("accessibilityFrame", of: object) as? NSValue)?.rectValue ?? .zero
            found.append(Element(object: object, role: role, label: label, screenFrame: frame, depth: depth))
            for child in (attribute("accessibilityChildren", of: object) as? [Any]) ?? [] {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
        }
        visit(window, depth: 0)
        return found
    }

    /// An attribute of the NSAccessibility protocol read by its getter's name, which every element answers whatever its
    /// class: AppKit's views, SwiftUI's own elements and the window.
    private static func attribute(_ getter: String, of object: NSObject) -> Any? {
        guard object.responds(to: Selector(getter)) else { return nil }
        return object.value(forKey: getter)
    }

    static func find(labelled label: String, in window: NSWindow) -> Element? {
        elements(in: window).first { element in element.label == label }
    }
}
#endif
