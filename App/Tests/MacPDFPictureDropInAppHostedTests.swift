/**
 * File: MacPDFPictureDropInAppHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Pictures dragged onto a page of a PDF in Graphite's own window inside the running Mac app: a picture file
 *              as the Finder's drag carries it, a PDF file, and image data, each told to the window's views as AppKit
 *              tells a drag destination, with the toolbar's Undo pressed by mouse events and pictures of each step; and
 *              a PDF from the Finder dropped between, after and before the pages of the sidebar's page list.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Docs/PDF-annotation-todo.md section 1: the Mac's PDF view taking a dropped picture, in the running app. AppKit's
/// own drags come from the window server, which follows a hand on the hardware pointer to a visible window, and the
/// owner declined computer use; so the drags here are told to the window's views as AppKit tells them
/// (`PasteboardDrag`): a real pasteboard written as the Finder and an image-dragging app write it, the view under each
/// point that registered for its types, entered, updated, the drop handed over only after an operation that is not
/// none. Runs only with `TEST_RUNNER_GRAPHITE_MAC_PICTURE_DROPS` given to xcodebuild as a folder, where it writes a
/// picture of each step, its notes and the saved PDF; a person looks at them.
@MainActor
final class MacPDFPictureDropInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_PICTURE_DROPS"
    private static let refusedPDFMessage = "A PDF can't be placed on a page as an image. Drop a picture, such as a PNG or JPEG."
    private var outputFolder: URL?
    private var openedSession: PDFSession?
    private var pictureCount = 0
    private var notes: [String] = []

    func testPicturesDroppedOntoAPageInTheRunningApp() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        let opened = try await openWorksheet()
        let window = opened.window
        try await settle(window)
        let session = try XCTUnwrap(opened.workspace.pdfSession)
        openedSession = session
        // XCTest runs the whole test inside one turn of the event loop, so AppKit never closes an undo group by event:
        // each action is a group of its own (`asOneAction`), as each of a person's drops is.
        session.undoManager.groupsByEvent = false
        let pdfView = try XCTUnwrap(ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: GraphiteMacPDFView.self).first)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let markupToolbar = try XCTUnwrap(pdfView.markupInteraction?.toolbar, "the pane's markup row")
        try writePicture("pdf open", of: window)
        try note("window \(window.frame), PDF view \(pdfView.convert(pdfView.bounds, to: nil)), registered for \(pdfView.registeredDraggedTypes.map(\.rawValue))")
        XCTAssertFalse(markupToolbar.isRowShown, "the row starts folded away, the text tool in hand")

        // 1. A picture file from the Finder: its address on the pasteboard, as the Finder writes it.
        let finderPasteboard = dragPasteboard { pasteboard in pasteboard.writeObjects([opened.pictureFile as NSURL]) }
        try note("the Finder's pasteboard: \(finderPasteboard.types?.map(\.rawValue) ?? [])")
        let finderDropPoint = windowPoint(onPageFromTop: CGPoint(x: 200, y: 260), page: page, view: pdfView)
        let finderPagePoint = pagePoint(underWindowPoint: finderDropPoint, page: page, view: pdfView)
        let finderOutcome = try await drop(finderPasteboard, at: finderDropPoint, view: pdfView, window: window) { session.pictures(on: page).count == 1 }
        try assertTaken(finderOutcome, by: pdfView)
        try assertPlacedPicture(session.pictures(on: page).last, middleAt: finderPagePoint)
        // The row unfolded above the page as the drop chose its tool; the page stayed, so the picture is still under
        // the pointer (2026-11-17: it moved down 22 page points with the row, `MacPDFPagesHeldStill`).
        try assertPointer(at: finderDropPoint, isOverPagePoint: finderPagePoint, page: page, view: pdfView, after: "the row unfolded")
        try await waitUntil("the row chose its Images tool", timeoutSeconds: 5) { pdfView.markupInteraction?.input.markupTool == .pictures }
        XCTAssertTrue(markupToolbar.isRowShown, "the drop unfolded the row")
        XCTAssertEqual(session.selectedPicture?.pictureName, session.pictures(on: page).last?.name, "the dropped picture is selected")
        XCTAssertEqual(session.undoManager.undoActionName, "Add Image")
        try writePicture("finder file dropped", of: window)
        try await assertSavedFileHasStamps(1, of: session, named: "after the Finder drop")
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Undo", share: 0.25, in: window), in: window)
        try note("after Undo: \(session.pictures(on: page).count) pictures, next undo \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(session.pictures(on: page).count, 0, "one Undo took the dropped picture back")
        try writePicture("finder file undone", of: window)

        // 2. A PDF file from the Finder: no "+" on the pointer, and its drop says why in the banner.
        let pdfPasteboard = dragPasteboard { pasteboard in pasteboard.writeObjects([opened.otherPDFFile as NSURL]) }
        let pdfDropPoint = windowPoint(onPageFromTop: CGPoint(x: 300, y: 400), page: page, view: pdfView)
        let pdfOutcome = try await drop(pdfPasteboard, at: pdfDropPoint, view: pdfView, window: window) { session.errorMessage != nil }
        try note("the PDF drag: \(describe(pdfOutcome))")
        XCTAssertTrue(pdfOutcome.destinations.allSatisfy { destination in destination === pdfView }, "the PDF view is the drag's destination")
        XCTAssertFalse(pdfOutcome.operations.contains { operation in operation.contains(.copy) }, "no + on the pointer")
        XCTAssertTrue(pdfOutcome.wasHandedOver)
        XCTAssertFalse(pdfOutcome.wasTaken, "the drop is turned away")
        XCTAssertEqual(session.errorMessage, Self.refusedPDFMessage)
        XCTAssertEqual(session.pictures(on: page).count, 0)
        try writePicture("pdf file refused with the banner", of: window)
        session.errorMessage = nil

        // 3. Image data with no file, as an app dragging a picture writes it: the row folded away first, so the drop
        // chooses the Images tool again.
        let foldingPoint = windowPoint(onPageFromTop: CGPoint(x: 300, y: 300), page: page, view: pdfView)
        let pagePointBeforeFolding = pagePoint(underWindowPoint: foldingPoint, page: page, view: pdfView)
        markupToolbar.toggleRow()
        try await waitUntil("the row is folded away", timeoutSeconds: 5) { pdfView.markupInteraction?.input.markupTool == .textSelection }
        try await settle(window)
        try assertPointer(at: foldingPoint, isOverPagePoint: pagePointBeforeFolding, page: page, view: pdfView, after: "the row folded away")
        let imagePasteboard = dragPasteboard { pasteboard in pasteboard.setData(opened.pictureData, forType: .png) }
        let imageDropPoint = windowPoint(onPageFromTop: CGPoint(x: 420, y: 420), page: page, view: pdfView)
        let imagePagePoint = pagePoint(underWindowPoint: imageDropPoint, page: page, view: pdfView)
        let imageOutcome = try await drop(imagePasteboard, at: imageDropPoint, view: pdfView, window: window) { session.pictures(on: page).count == 1 }
        try assertTaken(imageOutcome, by: pdfView)
        try assertPlacedPicture(session.pictures(on: page).last, middleAt: imagePagePoint)
        try assertPointer(at: imageDropPoint, isOverPagePoint: imagePagePoint, page: page, view: pdfView, after: "the row unfolded again")
        try await waitUntil("the row chose its Images tool", timeoutSeconds: 5) { pdfView.markupInteraction?.input.markupTool == .pictures }
        XCTAssertEqual(session.undoManager.undoActionName, "Add Image")
        try writePicture("image data dropped", of: window)
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Undo", share: 0.25, in: window), in: window)
        XCTAssertEqual(session.pictures(on: page).count, 0, "one Undo took the dropped picture back")
        try writePicture("image data undone", of: window)
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Redo", share: 0.25, in: window), in: window)
        XCTAssertEqual(session.pictures(on: page).count, 1, "Redo put it back")
        try writePicture("image data redone", of: window)
        try await assertSavedFileHasStamps(1, of: session, named: "after the image data drop")
    }

    /// Docs/PDF-annotation-todo.md section 1: a PDF dropped onto the sidebar's page list inserts its pages where it is let
    /// go, with a line showing where while it is held, as one undo step. The rows are found in a picture of the window
    /// (the white of the page thumbnails), as a person finds them.
    func testAPDFDroppedOntoThePageListInTheRunningApp() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        let folder = URL(fileURLWithPath: outputPath, isDirectory: true).appendingPathComponent("page list", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        outputFolder = folder
        let opened = try await openWorksheet(pageCount: 2)
        let window = opened.window
        try await settle(window)
        let session = try XCTUnwrap(opened.workspace.pdfSession)
        openedSession = session
        session.undoManager.groupsByEvent = false
        let pdfView = try XCTUnwrap(ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: GraphiteMacPDFView.self).first)
        // The page list, 210 points wide with a divider of one point, slides in where the PDF view started.
        let sidebarMinX = pdfView.convert(pdfView.bounds, to: nil).minX
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Show Pages", share: 0.5, in: window), in: window)
        try await waitUntil("the page list slid in", timeoutSeconds: 5) { pdfView.convert(pdfView.bounds, to: nil).minX >= sidebarMinX + 210 }
        try await settle(window)
        let thumbnailColumnX = sidebarMinX + 38
        let lineColumnX = sidebarMinX + 105
        // Left of the thumbnails and of the tint behind the row in view, where the line still runs, and away from the
        // row's page number, which is in the accent for the page in view.
        let lineProbeX = sidebarMinX + 18
        var rows = try await thumbnailRows(count: 2, atX: thumbnailColumnX, in: window)
        try note("sidebar from x \(sidebarMinX), thumbnails from the window's top \(rows)")
        try writePicture("page list shown", of: window)

        // 1. Between the two pages, from the Finder: the line shows in the gap while the drag is held. The page list
        // reads the Finder's addresses from the drag pasteboard, so it is written there, as the Finder writes it.
        let finderPasteboard = finderDragPasteboard(carrying: opened.otherPDFFile)
        let gapFromTop = (rows[0].upperBound + rows[1].lowerBound) / 2
        try noteViews(atX: lineColumnX, fromTop: gapFromTop, in: window, carrying: finderPasteboard)
        let pageListDestination = try pageListDropDestination(in: window, sidebarMinX: sidebarMinX)
        // The line is drawn halfway between the rows, whose padding reaches past the thumbnails: looked for down the
        // whole space between the thumbnails.
        let gapSpan = rows[0].upperBound...rows[1].lowerBound
        let tintedBefore = try tintedRows(atX: lineProbeX, within: gapSpan, in: window)
        try await dropOnPageList(finderPasteboard, to: pageListDestination, atX: lineColumnX, fromTop: gapFromTop, in: window, named: "between the pages") {
            let tintedWhileHeld = try tintedRows(atX: lineProbeX, within: gapSpan, in: window)
            try note("tinted rows between the thumbnails before the drag \(tintedBefore), while it is held \(tintedWhileHeld)")
            XCTAssertTrue(tintedBefore.isEmpty, "no line before the drag")
            XCTAssertFalse(tintedWhileHeld.isEmpty, "the insertion line shows between the pages while the drag is held")
            try writePicture("held between the pages", of: window)
        } until: { session.pageCount == 3 }
        XCTAssertEqual(pageTitles(of: session), ["Worksheet", "Handout", "Worksheet, page 2"])
        XCTAssertEqual(session.currentPageIndex, 1, "the inserted page is shown")
        XCTAssertEqual(session.undoManager.undoActionName, "Insert PDF")
        try writePicture("pdf inserted between the pages", of: window)
        try await click(atWindowPoint: try toolbarItemPoint(labelled: "Undo", share: 0.25, in: window), in: window)
        XCTAssertEqual(pageTitles(of: session), ["Worksheet", "Worksheet, page 2"], "one Undo took the inserted page out")
        try writePicture("insertion undone", of: window)

        // 2. A picture file is not taken: no line, nothing inserted.
        let picturePasteboard = finderDragPasteboard(carrying: opened.pictureFile)
        let pictureOutcome = try await dropOnPageList(picturePasteboard, to: pageListDestination, atX: lineColumnX, fromTop: gapFromTop, in: window, named: "a picture file") {
            XCTAssertTrue(try tintedRows(atX: lineProbeX, within: gapSpan, in: window).isEmpty, "no line for a picture")
        } until: { true }
        XCTAssertFalse(pictureOutcome.wasTaken, "the page list does not take a picture")
        XCTAssertEqual(session.pageCount, 2)

        // 3. In the empty space below the last page, then 4. above the first page.
        _ = finderDragPasteboard(carrying: opened.otherPDFFile)
        rows = try await thumbnailRows(count: 2, atX: thumbnailColumnX, in: window)
        try await dropOnPageList(finderPasteboard, to: pageListDestination, atX: lineColumnX, fromTop: rows[1].upperBound + 80, in: window, named: "below the last page") {
            try writePicture("held below the last page", of: window)
        } until: { session.pageCount == 3 }
        XCTAssertEqual(pageTitles(of: session), ["Worksheet", "Worksheet, page 2", "Handout"])
        rows = try await thumbnailRows(count: 2, atX: thumbnailColumnX, in: window)
        try await dropOnPageList(finderPasteboard, to: pageListDestination, atX: lineColumnX, fromTop: rows[0].lowerBound + 20, in: window, named: "on the first page's top half") {
            try writePicture("held over the first page's top half", of: window)
        } until: { session.pageCount == 4 }
        XCTAssertEqual(pageTitles(of: session), ["Handout", "Worksheet", "Worksheet, page 2", "Handout"])
        try writePicture("pdf inserted after the last and before the first page", of: window)
        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: session.location))
        XCTAssertEqual(saved.pageCount, 4, "the saved file has the inserted pages")
        try Data(contentsOf: session.location).write(to: folder.appendingPathComponent("Worksheet with inserted pages.pdf"))
    }

    /// The page list's own drop destination: SwiftUI lays a view of its own over each drop destination, and the list's
    /// is the one as wide as the sidebar (each row has one of its own, for pages dragged to reorder them).
    private func pageListDropDestination(in window: NSWindow, sidebarMinX: CGFloat) throws -> NSView {
        let destinations = ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: NSView.self).filter { view in
            let frame = view.convert(view.bounds, to: nil)
            return !view.registeredDraggedTypes.isEmpty && abs(frame.minX - sidebarMinX) < 2 && abs(frame.width - 210) < 2 && frame.height > 300
        }
        try note("the page list's drop destinations: \(destinations.map { view in "\(type(of: view)) \(view.convert(view.bounds, to: nil))" })")
        return try XCTUnwrap(destinations.last, "the page list's drop destination")
    }

    /// The views under a point, from the deepest up, with the drag types each registered, and the pasteboard's types.
    private func noteViews(atX x: CGFloat, fromTop: CGFloat, in window: NSWindow, carrying pasteboard: NSPasteboard) throws {
        let point = CGPoint(x: x, y: window.frame.height - fromTop)
        var view = window.contentView?.superview?.hitTest(point)
        var chain: [String] = []
        while let current = view {
            chain.append("\(type(of: current)) \(current.registeredDraggedTypes.map(\.rawValue))")
            view = current.superview
        }
        try note("pasteboard types \(pasteboard.types?.map(\.rawValue) ?? []); views under the point: \(chain.joined(separator: " < "))")
        let registered = ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: NSView.self).filter { view in !view.registeredDraggedTypes.isEmpty }
        try note("views registered for drags: \(registered.map { view in "\(type(of: view)) \(view.convert(view.bounds, to: nil)) \(view.registeredDraggedTypes.map(\.rawValue))" })")
    }

    /// The system's drag pasteboard, written as the Finder writes it for a drag of `file`; overwritten by the next drag.
    private func finderDragPasteboard(carrying file: URL) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        return pasteboard
    }

    /// The titles of the pages, in order: the first line of each page's text.
    private func pageTitles(of session: PDFSession) -> [String] {
        (0..<session.document.pageCount).map { pageIndex in
            session.document.page(at: pageIndex)?.string?.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        }
    }

    /// A drag that comes down the page list to a point `fromTop` points below the window's top, is held there while
    /// `whileHeld` looks, and lets go, as one action; waits until `isDone`, since the drop reads its files first.
    @discardableResult
    private func dropOnPageList(_ pasteboard: NSPasteboard, to destination: NSView, atX x: CGFloat, fromTop: CGFloat, in window: NSWindow, named name: String,
                                whileHeld: () async throws -> Void, until isDone: @escaping () -> Bool) async throws -> PasteboardDrag.Outcome {
        let height = window.frame.height
        let dropPoint = CGPoint(x: x, y: height - fromTop)
        let path = (0...6).map { step in CGPoint(x: x, y: dropPoint.y + 60 - Double(step) * 10) }
        let drag = PasteboardDrag(pasteboard: pasteboard, window: window, destination: destination)
        try note("\(name): told to \(type(of: destination)) at \(destination.convert(destination.bounds, to: nil))")
        var outcome = PasteboardDrag.Outcome()
        try await asOneAction {
            let hover = drag.hover(through: path)
            try await settle(window)
            try await whileHeld()
            outcome = drag.letGo(hover)
            try await waitUntil("the drop is done", timeoutSeconds: 10, isDone)
            try await settle(window)
        }
        try note("\(name), let go \(Int(fromTop)) points from the top: \(describe(outcome))")
        return outcome
    }

    /// The thumbnails' extents from the window's top, found in a picture of the window as runs of the pages' white down
    /// a column; waits until `count` of them are drawn.
    private func thumbnailRows(count: Int, atX x: CGFloat, in window: NSWindow) async throws -> [ClosedRange<CGFloat>] {
        var rows: [ClosedRange<CGFloat>] = []
        try await waitUntil("\(count) thumbnails are drawn", timeoutSeconds: 15) {
            rows = (try? self.whiteRuns(atX: x, in: window)) ?? []
            return rows.count >= count
        }
        return rows
    }

    private func whiteRuns(atX x: CGFloat, in window: NSWindow) throws -> [ClosedRange<CGFloat>] {
        let picture = try windowPicture(of: window)
        var runs: [ClosedRange<CGFloat>] = []
        var runStart: Int?
        for row in 60..<picture.pixelsHigh {
            let isWhite = picture.colorAt(x: Int(x), y: row).map { color in Self.isPageWhite(color) } ?? false
            if isWhite, runStart == nil { runStart = row }
            if !isWhite, let start = runStart {
                if row - start >= 60 { runs.append(CGFloat(start)...CGFloat(row - 1)) }
                runStart = nil
            }
        }
        return runs
    }

    private func windowPicture(of window: NSWindow) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))))
    }

    /// The rows of the window's picture, from its top, where a column is the accent's colour.
    private func tintedRows(atX x: CGFloat, within span: ClosedRange<CGFloat>, in window: NSWindow) throws -> [Int] {
        let picture = try windowPicture(of: window)
        return (Int(span.lowerBound)...Int(span.upperBound)).filter { row in
            picture.colorAt(x: Int(x), y: row)?.usingColorSpace(.deviceRGB).map(Self.isTinted) == true
        }
    }

    private static func isPageWhite(_ color: NSColor) -> Bool {
        guard let color = color.usingColorSpace(.deviceRGB) else { return false }
        return color.redComponent > 0.985 && color.greenComponent > 0.985 && color.blueComponent > 0.985
    }

    /// The accent itself, not a grey of the list or the pale tint behind the row of the page in view.
    private static func isTinted(_ color: NSColor) -> Bool {
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
        return (components.max() ?? 0) - (components.min() ?? 0) > 0.35
    }

    // MARK: Dragging

    /// A pasteboard of its own for one drag, written as the dragging app writes the drag's.
    private func dragPasteboard(_ write: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("GraphitePictureDrop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        write(pasteboard)
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    /// A drag that comes in over the PDF view's leading edge, crosses to `dropPoint` and lets go there, as one action;
    /// waits until `isDone`, since the drop reads its files and places them after it is taken.
    private func drop(_ pasteboard: NSPasteboard, at dropPoint: CGPoint, view: GraphiteMacPDFView, window: NSWindow,
                      until isDone: @escaping () -> Bool) async throws -> PasteboardDrag.Outcome {
        let viewFrame = view.convert(view.bounds, to: nil)
        let start = CGPoint(x: viewFrame.minX + 6, y: dropPoint.y + 40)
        let path = (0...6).map { step in
            let share = Double(step) / 6
            return CGPoint(x: start.x + share * (dropPoint.x - start.x), y: start.y + share * (dropPoint.y - start.y))
        }
        var outcome = PasteboardDrag.Outcome()
        try await asOneAction {
            outcome = PasteboardDrag(pasteboard: pasteboard, window: window).move(through: path)
            try await waitUntil("the drop is done", timeoutSeconds: 10, isDone)
            try await settle(window)
        }
        try note("drop at (\(Int(dropPoint.x)), \(Int(dropPoint.y))): \(describe(outcome))")
        return outcome
    }

    private func describe(_ outcome: PasteboardDrag.Outcome) -> String {
        "operations \(outcome.operations.map(\.rawValue)), destinations \(Set(outcome.destinations.map { view in String(describing: type(of: view)) })), "
            + "handed over \(outcome.wasHandedOver), taken \(outcome.wasTaken)"
    }

    private func assertTaken(_ outcome: PasteboardDrag.Outcome, by view: GraphiteMacPDFView, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(outcome.destinations.isEmpty, "the drag found a destination", file: file, line: line)
        XCTAssertTrue(outcome.destinations.allSatisfy { destination in destination === view }, "the PDF view is the destination, under every point", file: file, line: line)
        XCTAssertTrue(outcome.operations.allSatisfy { operation in operation == .copy }, "a + on the pointer all the way", file: file, line: line)
        XCTAssertTrue(outcome.wasHandedOver && outcome.wasTaken, "the drop was taken", file: file, line: line)
    }

    /// The page point under a point of the window, read before the drop: the page moves once the row unfolds.
    private func pagePoint(underWindowPoint windowPoint: CGPoint, page: PDFPage, view: PDFView) -> CGPoint {
        view.convert(view.convert(windowPoint, from: nil), to: page)
    }

    /// The page did not move under the pointer while the row unfolded or folded above it.
    private func assertPointer(at windowPoint: CGPoint, isOverPagePoint expected: CGPoint, page: PDFPage, view: PDFView, after change: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let now = pagePoint(underWindowPoint: windowPoint, page: page, view: view)
        try note("after \(change): page point under the pointer \(now), was \(expected)")
        XCTAssertEqual(now.x, expected.x, accuracy: 1, "the page stayed still as \(change)", file: file, line: line)
        XCTAssertEqual(now.y, expected.y, accuracy: 1, "the page stayed still as \(change)", file: file, line: line)
    }

    /// The picture's middle is `pagePoint`, the page point that was under the pointer where the drop let go.
    private func assertPlacedPicture(_ picture: PDFPicture?, middleAt pagePoint: CGPoint, file: StaticString = #filePath, line: UInt = #line) throws {
        let placed = try XCTUnwrap(picture, "a picture on the page", file: file, line: line)
        try note("picture \(placed.bounds.integral), middle \(CGPoint(x: placed.bounds.midX, y: placed.bounds.midY)), page point under the pointer \(pagePoint)")
        // The picture's frame is rounded to whole points.
        XCTAssertEqual(placed.bounds.midX, pagePoint.x, accuracy: 1, file: file, line: line)
        XCTAssertEqual(placed.bounds.midY, pagePoint.y, accuracy: 1, file: file, line: line)
        // 240 pixels with no resolution stated: 120 points.
        XCTAssertEqual(placed.bounds.width, 120, accuracy: 1, file: file, line: line)
    }

    /// Saves, reads the file back as another application reads it and counts its stamp annotations (the pictures), and
    /// the file's objects written as stamps (each also carries Apple's copy of its dictionary, with a second
    /// "/Subtype /Stamp" inside), and keeps a copy for a person to open.
    private func assertSavedFileHasStamps(_ expectedCount: Int, of session: PDFSession, named name: String,
                                          file: StaticString = #filePath, line: UInt = #line) async throws {
        try await session.save()
        let savedData = try Data(contentsOf: session.location)
        let saved = try XCTUnwrap(PDFDocument(data: savedData), file: file, line: line)
        let stamps = (0..<saved.pageCount).compactMap(saved.page(at:)).flatMap(\.annotations).filter { annotation in annotation.type == "Stamp" }
        let objects = String(decoding: savedData, as: Unicode.ASCII.self).components(separatedBy: "endobj")
        let writtenStampCount = objects.filter { object in object.contains("/Subtype /Stamp") }.count
        try note("\(name): saved \(savedData.count) bytes, \(stamps.count) stamp annotations read back, \(writtenStampCount) objects written as stamps")
        XCTAssertEqual(stamps.count, expectedCount, file: file, line: line)
        XCTAssertEqual(writtenStampCount, expectedCount, file: file, line: line)
        try savedData.write(to: try XCTUnwrap(outputFolder).appendingPathComponent("Worksheet \(name).pdf"))
    }

    // MARK: The window

    private struct OpenedWorksheet {
        let window: NSWindow
        let workspace: WorkspaceModel
        /// A picture and a PDF in a folder outside the vault, as the Finder drags them.
        let pictureFile: URL
        let otherPDFFile: URL
        let pictureData: Data
    }

    private func openWorksheet(pageCount: Int = 1) async throws -> OpenedWorksheet {
        let vaultRoot = try TemporaryVault.make(prefix: "MacPictureDropsInApp", for: self).root
        try Self.writeWorksheetPDF(to: vaultRoot.appendingPathComponent("Worksheet.pdf"), title: "Worksheet", pageCount: pageCount)
        try Data("# Notes\n".utf8).write(to: vaultRoot.appendingPathComponent("Notes.md"))
        let finderFolder = try TemporaryVault.make(prefix: "MacPictureDropsFinder", for: self).root
        let pictureData = try Self.diagramPNG()
        let pictureFile = finderFolder.appendingPathComponent("Diagram.png")
        try pictureData.write(to: pictureFile)
        let otherPDFFile = finderFolder.appendingPathComponent("Handout.pdf")
        try Self.writeWorksheetPDF(to: otherPDFFile, title: "Handout")
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        _ = await workspace.open(try VaultPath("Worksheet.pdf"), placement: .currentTab)
        try await waitUntil("the PDF is shown", timeoutSeconds: 30) { (workspace.pdfSession?.pageCount ?? 0) > 0 }
        return OpenedWorksheet(window: window, workspace: workspace, pictureFile: pictureFile, otherPDFFile: otherPDFFile, pictureData: pictureData)
    }

    /// A Letter PDF with a title and ruled lines on each page, so a picture on it is easy to see; pages after the first
    /// say their number after the title.
    private static func writeWorksheetPDF(to location: URL, title: String, pageCount: Int = 1) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let pageTitle = pageIndex == 0 ? title : "\(title), page \(pageIndex + 1)"
            NSAttributedString(string: pageTitle, attributes: [.font: NSFont.boldSystemFont(ofSize: 28)]).draw(at: CGPoint(x: 72, y: 700))
            NSColor(white: 0.75, alpha: 1).setFill()
            for lineIndex in 0..<20 { CGRect(x: 72, y: 640 - Double(lineIndex) * 28, width: 468, height: 1).fill() }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// A PNG of 240 by 160 pixels that states no resolution, so it is placed at 120 by 80 points: blue with an orange
    /// cross through its middle, so a picture shows where its middle is.
    private static func diagramPNG() throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.15, green: 0.45, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.55, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 116, y: 0, width: 8, height: 160))
        context.fill(CGRect(x: 0, y: 76, width: 240, height: 8))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    /// A point of the page measured from its top left corner, as a person measures it, in the window's coordinates.
    private func windowPoint(onPageFromTop pointFromTop: CGPoint, page: PDFPage, view: PDFView) -> CGPoint {
        let box = page.bounds(for: view.displayBox)
        return view.convert(view.convert(CGPoint(x: box.minX + pointFromTop.x, y: box.maxY - pointFromTop.y), from: page), to: nil)
    }

    /// Runs one action of a person's as one undo group.
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

    // MARK: Pressing the toolbar

    /// A point `share` of the way across a toolbar item, for an item whose arrow menu takes its right half (Undo, Redo).
    private func toolbarItemPoint(labelled label: String, share: Double, in window: NSWindow) throws -> CGPoint {
        let item = try XCTUnwrap(window.toolbar?.items.first { item in item.label == label }, "no toolbar item labelled \(label)")
        let view = try XCTUnwrap(item.view)
        let frame = view.convert(view.bounds, to: nil)
        return CGPoint(x: frame.minX + share * frame.width, y: frame.midY)
    }

    /// A press and release of the left button through the application's queue, as a hand's click arrives. Opens no undo
    /// group of its own: an Undo with a group open takes back that empty group.
    private func click(atWindowPoint windowPoint: CGPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.postEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)),
                            atStart: false)
        }
        try await settle(window)
    }

    // MARK: Output

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    /// The window's content with the PDF's pages drawn in, and its whole frame with the toolbar (whose pages are blank).
    private func writePicture(_ name: String, of window: NSWindow) throws {
        let folder = try XCTUnwrap(outputFolder)
        pictureCount += 1
        try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window)).write(to: folder.appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let representation = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: representation)
        try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            .write(to: folder.appendingPathComponent(String(format: "%02d %@ (frame).png", pictureCount, name)))
    }
}
#endif
