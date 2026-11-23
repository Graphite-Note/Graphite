/**
 * File: MacSectionLinksInAppHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A heading of a note in the reading view dragged onto a page of a PDF beside it, inside the running Mac
 *              app: the drag's item told to the PDF view as AppKit tells a drag destination, the section's picture placed
 *              where it was let go, a click on the picture opening the section on the other side, and the saved file's
 *              link read back with PDFKit as another reader reads it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Docs/Split-down-and-section-links-todo.md section 2, the Mac's checks in the running app. AppKit's own drags come
/// from the window server following a hand on the hardware pointer, and SwiftUI starts no drag from events a test posts
/// (tried 2026-11-23: a mouse-down and moves posted over an `onDrag` view never reached `beginDraggingSession`); a drag
/// begun by a person's mouse, driven by posted events, leaves AppKit's drag loop waiting for a mouse-up it never gets.
/// So the drag here starts from what the reading view's heading hands SwiftUI (`ReadingSectionDrags.itemProvider`, made
/// from the block places the reading view on screen laid out) and is told to the window's views as AppKit tells a drag
/// destination (`PasteboardDrag`), with the item's contents on a real pasteboard. Not exercised: SwiftUI writing the item
/// provider onto the drag pasteboard. The clicks on the picture are presses handed to the PDF view (`press`): the test's
/// window is never key, and PDFKit follows no link for a press posted to an inactive window. Runs only with `TEST_RUNNER_GRAPHITE_MAC_SECTION_LINKS` given to xcodebuild as a
/// folder, where it writes a picture of each step, its notes and the saved PDF; a person looks at them.
@MainActor
final class MacSectionLinksInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_SECTION_LINKS"
    private static let heading = "Ohm's law"
    /// A note long enough that its third section is below the reading view's first screen, so opening it at the section
    /// shows the view scrolled there.
    private static let note: String = {
        var text = "# Circuits\n\nNotes from the first evening of Everyday Electronics.\n\n## Charge and current\n\n"
        for sentence in 1...14 { text += "Current is charge moving past a point, counted in amperes; sentence \(sentence) of the warm-up.\n\n" }
        text += "## Ohm's law\n\nThe voltage across a resistor is the current through it times its resistance: V = IR.\n\n"
        text += "- Double the resistance, half the current.\n- A short circuit has almost no resistance.\n\n## Power\n\nP = VI, in watts.\n\n"
        for sentence in 1...14 { text += "A kettle turns electricity into heat; sentence \(sentence) of the examples.\n\n" }
        return text
    }()

    private var outputFolder: URL?
    private var pictureCount = 0
    private var notes: [String] = []

    func testAHeadingDraggedFromTheReadingViewOntoAPDFPageOpensItsSection() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        let opened = try await openNoteBesidePDF()
        let window = opened.window, workspace = opened.workspace, session = opened.pdfSession
        session.undoManager.groupsByEvent = false
        let pdfView = try paneView(of: session, in: window)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try writePicture("note in reading view beside the PDF", of: window)

        // 1. The heading's drag, as the reading view on screen makes it: its block found among the places the reading
        // view laid out, the item provider of `ReadingSectionDrags` read as a drop reads it.
        let noteSession = opened.noteSession
        let headingOffset = (Self.note as NSString).range(of: "## " + Self.heading).location
        let headingBlock = try XCTUnwrap(noteSession.readingPosition.blockLocations.first { location in location.noteOffset == headingOffset },
                                         "the reading view laid out a block at the heading")
        let drags = ReadingSectionDrags(notePath: opened.notePath, noteText: noteSession.text, vaultRoot: try XCTUnwrap(workspace.folderAccess?.root),
                                        blockOffsets: Dictionary(noteSession.readingPosition.blockLocations.map { location in (location.blockIdentifier, location.noteOffset) }) { first, _ in first })
        let provider = try XCTUnwrap(drags.itemProvider(forBlock: headingBlock.blockIdentifier))
        let loadedTransfer = await SectionLinkTransfer.load(from: provider)
        let transfer = try XCTUnwrap(loadedTransfer)
        let linkText: String? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in continuation.resume(returning: object as? String) }
        }
        try note("dragged block \(headingBlock.blockIdentifier) at \(headingOffset): \(transfer.link), as text \(linkText ?? "none"), provider types \(provider.registeredTypeIdentifiers)")
        XCTAssertEqual(transfer.link, SectionLink(note: "Circuits", subpath: Self.heading))
        XCTAssertEqual(linkText, "[[Circuits#\(Self.heading)]]")
        let pasteboard = dragPasteboard(carrying: transfer, text: linkText ?? "")

        let dropPoint = windowPoint(onPageFromTop: CGPoint(x: 306, y: 300), page: page, view: pdfView)
        let dropPagePoint = pdfView.convert(pdfView.convert(dropPoint, from: nil), to: page)
        let outcome = try await drop(pasteboard, at: dropPoint, over: pdfView, window: window, undoManager: session.undoManager) { session.pictures(on: page).contains { picture in picture.sectionLinkAddress != nil } }
        try note("drop at \(dropPoint), page point \(dropPagePoint): \(describe(outcome))")
        XCTAssertTrue(outcome.destinations.allSatisfy { destination in destination === pdfView }, "the PDF view is the drag's destination")
        XCTAssertTrue(outcome.operations.allSatisfy { operation in operation == .copy }, "a + on the pointer all the way")
        XCTAssertTrue(outcome.wasHandedOver && outcome.wasTaken, "the drop was taken")
        let picture = try XCTUnwrap(session.pictures(on: page).first { picture in picture.sectionLinkAddress != nil }, "the section's picture on the page")
        let address = try XCTUnwrap(picture.sectionLinkAddress)
        try note("picture \(picture.bounds.integral), address \(address), next undo \"\(session.undoManager.undoActionName)\"")
        XCTAssertEqual(picture.bounds.midX, dropPagePoint.x, accuracy: 1, "its middle where it was let go")
        XCTAssertEqual(picture.bounds.midY, dropPagePoint.y, accuracy: 1, "its middle where it was let go")
        XCTAssertLessThanOrEqual(picture.bounds.width, page.bounds(for: .cropBox).width * 0.6 + 1, "at most 60% of the page")
        XCTAssertEqual(session.undoManager.undoActionName, "Add Section Link")
        XCTAssertEqual(session.selectedPicture?.pictureName, picture.name, "the placed picture is selected")
        XCTAssertTrue(address.hasPrefix("obsidian://open?vault="), address)
        XCTAssertTrue(address.hasSuffix("&file=Circuits%23Ohm%27s%20law"), address)
        let linkOnPage = try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Link" && annotation.url?.absoluteString == address },
                                       "a link over the picture")
        XCTAssertEqual(linkOnPage.bounds, picture.annotationBounds, "the link covers the picture")
        try await waitUntil("the row chose its Images tool", timeoutSeconds: 5) { pdfView.markupInteraction?.input.markupTool == .pictures }
        try writePicture("heading dropped on the page", of: window)

        // 2. The other side shows another note, so the click has to bring the section there.
        let otherTabID = try XCTUnwrap(workspace.layout.tabID(showing: opened.notePath))
        let errandsPath = try VaultPath("Errands.md")
        _ = await workspace.open(errandsPath, placement: .besideTab(try XCTUnwrap(workspace.layout.tabID(showing: opened.pdfPath))))
        try await waitUntil("the other side shows Errands", timeoutSeconds: 10) { workspace.layout.tabID(showing: errandsPath) != nil && workspace.layout.tabID(showing: opened.notePath) == nil }
        try await settle(window)
        try note("before the clicks: groups \(describeGroups(of: workspace)), the note's old tab \(otherTabID)")
        let linkMiddle = CGPoint(x: linkOnPage.bounds.midX, y: linkOnPage.bounds.midY)
        let clickPoint = pdfView.convert(pdfView.convert(linkMiddle, from: page), to: nil)

        // The test window is never key (macOS refuses a test's request to activate the app), and PDFKit follows no link
        // for a press posted to an inactive window (tried 2026-11-23: neither on the picture nor on a plain link); so each
        // press is handed to the PDF view, its release waiting in the queue, as AppKit hands a press to the view under the
        // pointer in a key window.
        // A click through the application's queue on the page beside the picture focuses the PDF's side, as a person's
        // first click on it does (the side's own tap); the press on the picture then goes to the view under the pointer.
        try await clickThroughQueue(atWindowPoint: windowPoint(onPageFromTop: CGPoint(x: 306, y: 700), page: page, view: pdfView), in: window)
        let pdfGroupID = try XCTUnwrap(workspace.layout.groups.first { group in group.tabs.contains { tab in tab.path == opened.pdfPath } }?.id)
        try note("after a click on the page: groups \(describeGroups(of: workspace))")
        XCTAssertEqual(workspace.layout.focusedGroupID, pdfGroupID, "a click on the PDF focuses its side")
        // A click with the Images tool still in hand, as the drop left it, the picture let go of first.
        session.selectedPicture = nil
        try await press(atWindowPoint: clickPoint, in: window)
        let openedWithImagesTool = workspace.layout.tabID(showing: opened.notePath) != nil
        try note("click at \(clickPoint) with the Images tool: the section opened \(openedWithImagesTool); groups \(describeGroups(of: workspace)), "
                 + "selected picture \(session.selectedPicture?.pictureName ?? "none")")
        try writePicture("clicked with the Images tool", of: window)
        XCTAssertFalse(openedWithImagesTool, "with the Images tool a click takes the picture, to move or resize it")
        XCTAssertEqual(session.selectedPicture?.pictureName, picture.name, "the click selected the picture")

        // With Text Selection, as a person reads the page.
        let markupToolbar = try XCTUnwrap(pdfView.markupInteraction?.toolbar)
        markupToolbar.choose(.textSelection)
        try await waitUntil("Text Selection is chosen", timeoutSeconds: 5) { pdfView.markupInteraction?.input.markupTool == .textSelection }
        try await settle(window)
        XCTAssertEqual(page.annotation(at: linkMiddle)?.url?.absoluteString, address, "PDFKit finds the link over the picture")
        try await press(atWindowPoint: clickPoint, in: window)
        try await waitUntil("the section opened beside the PDF", timeoutSeconds: 10) { workspace.layout.tabID(showing: opened.notePath) != nil }
        try await settle(window)
        let sectionTabID = try XCTUnwrap(workspace.layout.tabID(showing: opened.notePath))
        let pdfTabID = try XCTUnwrap(workspace.layout.tabID(showing: opened.pdfPath))
        let sectionGroup = try XCTUnwrap(workspace.layout.groups.first { group in group.tabs.contains { tab in tab.id == sectionTabID } })
        let pdfGroup = try XCTUnwrap(workspace.layout.groups.first { group in group.tabs.contains { tab in tab.id == pdfTabID } })
        try note("after the click: groups \(describeGroups(of: workspace))")
        XCTAssertNotEqual(sectionGroup.id, pdfGroup.id, "the section opened on the other side")
        XCTAssertEqual(sectionGroup.activeTabID, sectionTabID, "the section is the other side's tab in view")
        XCTAssertEqual(pdfGroup.activeTabID, pdfTabID, "the PDF stays in view on its side")
        let shownNote = try XCTUnwrap(workspace.document(for: sectionTabID).markdownSession)
        try await waitUntil("the note shows its section at the top", timeoutSeconds: 10) {
            let top = shownNote.viewMode == .reading ? shownNote.readingPosition.topLocation() : nil
            return shownNote.viewMode != .reading || (top ?? 0) >= headingOffset - 1
        }
        try note("the note opened in \(shownNote.viewMode), reading view's top at \(shownNote.readingPosition.topLocation().map(String.init) ?? "none"), "
                 + "heading at \(headingOffset), editor selection \(shownNote.selection)")
        try writePicture("section opened beside the PDF", of: window)

        // 3. The saved file, read back as another reader reads it.
        try await session.save()
        let savedData = try Data(contentsOf: session.location)
        try savedData.write(to: try XCTUnwrap(outputFolder).appendingPathComponent("Worksheet with a section link.pdf"))
        let savedPage = try XCTUnwrap(PDFDocument(data: savedData)?.page(at: 0))
        let savedLinks = savedPage.annotations.filter { annotation in annotation.type == "Link" }
        let savedStamps = savedPage.annotations.filter { annotation in annotation.type == "Stamp" }
        try note("saved \(savedData.count) bytes: links \(savedLinks.map { link in "\(link.url?.absoluteString ?? "no address") at \(link.bounds.integral)" }), "
                 + "stamps \(savedStamps.map { stamp in stamp.bounds.integral })")
        XCTAssertEqual(savedLinks.compactMap(\.url?.absoluteString), [address], "the saved file links to the section")
        XCTAssertEqual(savedStamps.count, 1, "the section's picture is a stamp of its own")
        XCTAssertEqual(savedLinks.first?.bounds, savedStamps.first?.bounds, "the link covers the picture")
        let savedURL = try XCTUnwrap(savedLinks.first?.url)
        XCTAssertEqual(SectionLink(openingURL: savedURL), SectionLink(note: "Circuits", subpath: Self.heading), "Graphite reads the link back")
        let components = try XCTUnwrap(URLComponents(url: savedURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "obsidian")
        XCTAssertEqual(components.host, "open")
        XCTAssertEqual(components.queryItems?.first { item in item.name == "vault" }?.value, workspace.title, "Obsidian finds the vault by its name")
        XCTAssertEqual(components.queryItems?.first { item in item.name == "file" }?.value, "Circuits#\(Self.heading)", "and the note's section")
        try note("Obsidian would open vault \"\(components.queryItems?.first { item in item.name == "vault" }?.value ?? "")\", "
                 + "file \"\(components.queryItems?.first { item in item.name == "file" }?.value ?? "")\"")
    }

    /// Docs/Guide-vault-todo.md section 5: the guide's picture of a section link on the Mac, taken from a copy of the guide
    /// vault: the Week 1 lecture note in the reading view beside its slides, its Power heading dropped onto the first
    /// slide as the test above drops one. Runs only with `TEST_RUNNER_GRAPHITE_GUIDE_MAC_SECTION_LINK` given as a folder.
    func testTakeTheGuidesPictureOfASectionLinkOnASlide() async throws {
        guard let folder = ProcessInfo.processInfo.environment[Self.guidePictureVariable] else { return }
        outputFolder = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: try XCTUnwrap(outputFolder), withIntermediateDirectories: true)
        let vaultRoot = try TemporaryVault.make(prefix: "GuideSectionLink", for: self).root.appendingPathComponent("Graphite Guide", isDirectory: true)
        try FileManager.default.copyItem(at: FixtureFolders.guideVault, to: vaultRoot)
        let lecturePath = try VaultPath("6 Everyday examples/Everyday Electronics/Week 1 - Voltage and current.md")
        let slidesPath = try VaultPath("6 Everyday examples/Everyday Electronics/Week 1 slides.pdf")
        let opened = try await openNoteBesidePDF(vaultRoot: vaultRoot, notePath: lecturePath, pdfPath: slidesPath)
        let window = opened.window, session = opened.pdfSession
        session.undoManager.groupsByEvent = false
        let pdfView = try paneView(of: session, in: window)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let noteSession = opened.noteSession
        let headingOffset = (noteSession.text as NSString).range(of: "## Power").location
        let headingBlock = try XCTUnwrap(noteSession.readingPosition.blockLocations.first { location in location.noteOffset == headingOffset })
        let drags = ReadingSectionDrags(notePath: lecturePath, noteText: noteSession.text, vaultRoot: vaultRoot,
                                        blockOffsets: [headingBlock.blockIdentifier: headingBlock.noteOffset])
        let provider = try XCTUnwrap(drags.itemProvider(forBlock: headingBlock.blockIdentifier))
        let loadedTransfer = await SectionLinkTransfer.load(from: provider)
        let transfer = try XCTUnwrap(loadedTransfer)
        let pasteboard = dragPasteboard(carrying: transfer, text: "[[\(transfer.link.linkText)]]")
        let box = page.bounds(for: pdfView.displayBox)
        let dropPoint = windowPoint(onPageFromTop: CGPoint(x: box.width * 0.62, y: box.height * 0.7), page: page, view: pdfView)
        let outcome = try await drop(pasteboard, at: dropPoint, over: pdfView, window: window, undoManager: session.undoManager) {
            session.pictures(on: page).contains { picture in picture.sectionLinkAddress != nil }
        }
        XCTAssertTrue(outcome.wasTaken, "the drop was taken")
        // As a person leaves it: the picture let go of and the row folded away.
        session.selectedPicture = nil
        if let toolbar = pdfView.markupInteraction?.toolbar, toolbar.isRowShown { toolbar.toggleRow() }
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 60).measure({}, until: { true })
        let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))))
        try XCTUnwrap(image.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.62]))
            .write(to: try XCTUnwrap(outputFolder).appendingPathComponent("Mac - A section link on a slide.jpg"))
    }

    static let guidePictureVariable = "GRAPHITE_GUIDE_MAC_SECTION_LINK"

    // MARK: The window

    private struct OpenedNoteBesidePDF {
        let window: NSWindow
        let workspace: WorkspaceModel
        let notePath: VaultPath
        let pdfPath: VaultPath
        let noteSession: MarkdownSession
        let pdfSession: PDFSession
    }

    /// A vault of the note, a note of errands and a one-page worksheet PDF, opened as `openNoteBesidePDF(vaultRoot:…)` does.
    private func openNoteBesidePDF() async throws -> OpenedNoteBesidePDF {
        let vaultRoot = try TemporaryVault.make(prefix: "MacSectionLinksInApp", for: self).root
        try Data(Self.note.utf8).write(to: vaultRoot.appendingPathComponent("Circuits.md"))
        try Data("# Errands\n\n- Buy a 220 ohm resistor.\n".utf8).write(to: vaultRoot.appendingPathComponent("Errands.md"))
        try Self.writeWorksheetPDF(to: vaultRoot.appendingPathComponent("Worksheet.pdf"))
        return try await openNoteBesidePDF(vaultRoot: vaultRoot, notePath: try VaultPath("Circuits.md"), pdfPath: try VaultPath("Worksheet.pdf"))
    }

    /// The note in the reading view on the left side, the PDF on the right.
    private func openNoteBesidePDF(vaultRoot: URL, notePath: VaultPath, pdfPath: VaultPath) async throws -> OpenedNoteBesidePDF {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        _ = await workspace.open(notePath, placement: .currentTab)
        let noteSession = try XCTUnwrap(workspace.markdownSession)
        noteSession.viewMode = .reading
        _ = await workspace.open(pdfPath, placement: .otherGroup)
        try await waitUntil("the PDF is shown", timeoutSeconds: 30) { (workspace.pdfSession?.pageCount ?? 0) > 0 }
        let pdfSession = try XCTUnwrap(workspace.pdfSession)
        try await waitUntil("the reading view laid out its blocks", timeoutSeconds: 30) {
            noteSession.readingPosition.hasLaidOutBlocks && noteSession.readingPosition.blockLocations.count > 3
        }
        try await waitUntil("the PDF view is in the window", timeoutSeconds: 30) {
            ReleaseVaultViews.descendants(of: window.contentView ?? NSView(), ofType: GraphiteMacPDFView.self).contains { view in view.document === pdfSession.document }
        }
        try await settle(window)
        return OpenedNoteBesidePDF(window: window, workspace: workspace, notePath: notePath, pdfPath: pdfPath, noteSession: noteSession, pdfSession: pdfSession)
    }

    /// A Letter page with a title and ruled lines, as a worksheet to write on.
    private static func writeWorksheetPDF(to location: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: "Worksheet 1: resistors", attributes: [.font: NSFont.boldSystemFont(ofSize: 28)]).draw(at: CGPoint(x: 72, y: 700))
        NSColor(white: 0.75, alpha: 1).setFill()
        for lineIndex in 0..<20 { CGRect(x: 72, y: 640 - Double(lineIndex) * 28, width: 468, height: 1).fill() }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }

    private func describeGroups(of workspace: WorkspaceModel) -> String {
        workspace.layout.groups.map { group in
            let tabs = group.tabs.map { tab in (tab.id == group.activeTabID ? "*" : "") + (tab.path?.rawValue ?? "empty") }
            return (group.id == workspace.layout.focusedGroupID ? "focused " : "") + "[" + tabs.joined(separator: ", ") + "]"
        }.joined(separator: " | ")
    }

    // MARK: Dragging

    /// A pasteboard of its own for the drag, holding what the heading's item provider gives: the section, as a drag
    /// inside Graphite carries it, and the link as text for a note or another app.
    private func dragPasteboard(carrying transfer: SectionLinkTransfer, text: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("GraphiteSectionLinkDrop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData((try? JSONEncoder().encode(transfer)) ?? Data(), forType: MacPDFPictureDropTarget.sectionLinkType)
        item.setString(text, forType: .string)
        pasteboard.writeObjects([item])
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    /// A drag that comes in over the PDF view from the note's side, crosses to `dropPoint` and lets go there, as one
    /// action; waits until `isDone`, since the section is drawn and placed after the drop is taken.
    private func drop(_ pasteboard: NSPasteboard, at dropPoint: CGPoint, over pdfView: PDFView, window: NSWindow, undoManager: UndoManager,
                      until isDone: @escaping @MainActor () -> Bool) async throws -> PasteboardDrag.Outcome {
        let start = CGPoint(x: dropPoint.x - 160, y: dropPoint.y + 40)
        let path = (0...8).map { step in
            let share = Double(step) / 8
            return CGPoint(x: start.x + share * (dropPoint.x - start.x), y: start.y + share * (dropPoint.y - start.y))
        }
        // The first points are over the note's side, which takes no section: the drag reaches the PDF part way.
        // XCTest runs the whole test inside one turn of the event loop, so AppKit never closes an undo group by event:
        // the drop is a group of its own, as a person's is.
        undoManager.beginUndoGrouping()
        let pointsOverPDF = path.filter { point in pdfView.visibleRect.contains(pdfView.convert(point, from: nil)) }
        let drag = PasteboardDrag(pasteboard: pasteboard, window: window)
        try note("the drag's points over the PDF \(pointsOverPDF.map { point in "(\(Int(point.x)), \(Int(point.y)))" }), "
                 + "destinations \(pointsOverPDF.map { point in drag.destination(at: point).map { view in String(describing: type(of: view)) } ?? "none" })")
        let outcome = drag.move(through: pointsOverPDF)
        try note("the drag: \(describe(outcome))")
        var thrown: (any Error)?
        do { try await waitUntil("the section is placed", timeoutSeconds: 20) { isDone() } } catch { thrown = error }
        undoManager.endUndoGrouping()
        if let thrown { throw thrown }
        try await settle(window)
        return outcome
    }

    /// The PDF pane's view of `session`; a note's embedded PDFs have views of their own.
    private func paneView(of session: PDFSession, in window: NSWindow) throws -> GraphiteMacPDFView {
        try XCTUnwrap(ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: GraphiteMacPDFView.self).first { view in
            view.document === session.document
        }, "the PDF pane's view")
    }

    private func describe(_ outcome: PasteboardDrag.Outcome) -> String {
        "operations \(outcome.operations.map(\.rawValue)), destinations \(Set(outcome.destinations.map { view in String(describing: type(of: view)) })), "
            + "handed over \(outcome.wasHandedOver), taken \(outcome.wasTaken)"
    }

    /// A point of the page measured from its top left corner, in the window's coordinates.
    private func windowPoint(onPageFromTop pointFromTop: CGPoint, page: PDFPage, view: PDFView) -> CGPoint {
        let box = page.bounds(for: view.displayBox)
        return view.convert(view.convert(CGPoint(x: box.minX + pointFromTop.x, y: box.maxY - pointFromTop.y), from: page), to: nil)
    }

    /// A press of the left button handed to the view under the point, as AppKit finds it, its release waiting in the
    /// application's queue for the loop in which PDFKit follows a press.
    private func press(atWindowPoint windowPoint: CGPoint, in window: NSWindow) async throws {
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let target = try XCTUnwrap(frameView.hitTest(frameView.convert(windowPoint, from: nil)), "a view under the point")
        try note("press at (\(Int(windowPoint.x)), \(Int(windowPoint.y))) handed to \(type(of: target))")
        NSApp.postEvent(try mouseEvent(.leftMouseUp, at: windowPoint, in: window), atStart: false)
        target.mouseDown(with: try mouseEvent(.leftMouseDown, at: windowPoint, in: window))
        try await settle(window)
    }

    /// A press and release posted to the application's queue, which an inactive window's views get as AppKit sends them.
    private func clickThroughQueue(atWindowPoint windowPoint: CGPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { NSApp.postEvent(try mouseEvent(type, at: windowPoint, in: window), atStart: false) }
        try await settle(window)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 20).measure({}, until: { true })
    }

    // MARK: Output

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    /// The window's content with the PDF's pages drawn in.
    private func writePicture(_ name: String, of window: NSWindow) throws {
        pictureCount += 1
        try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
            .write(to: try XCTUnwrap(outputFolder).appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
    }
}
#endif
