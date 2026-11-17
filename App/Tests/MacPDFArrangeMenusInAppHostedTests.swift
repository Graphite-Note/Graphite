/**
 * File: MacPDFArrangeMenusInAppHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The Mac's Arrange menus used in Graphite's own window inside the running Mac app: two overlapping
 *              pictures, ink, a text box and a shape on a generated page; each of the six commands chosen from the
 *              right-click menus and through what Tools › Arrange's items call; the dimmed items, one Undo for each
 *              move, the colour the screen shows where the objects overlap and the saved file's order at each step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI

/// Docs/PDF-annotation-todo.md, section 2: "On the Mac, the same with overlapping pictures, a text box and a shape". The
/// owner declined computer use and a Mac UI test needs Automation Mode, so this runs inside the app as a hosted test, as
/// MacPDFMarkupInAppHostedTests does: Graphite's root view in a window of the app, clicks and keys put in the app's event
/// queue, right-click menus asked of the view under the pointer and their items chosen as a click on them chooses them.
/// The menu bar's Tools › Arrange is read from `NSApp.mainMenu`, but its items stay dimmed for a test's window
/// (`ArrangeRoute.toolsArrangeActions`), so its six commands are chosen through the actions its items call. Runs only
/// with `TEST_RUNNER_GRAPHITE_MAC_ARRANGE` given to xcodebuild as a folder, where it writes a picture of each step and a
/// line of notes for each; a person looks at them.
@MainActor
final class MacPDFArrangeMenusInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_ARRANGE"
    private var outputFolder: URL?
    private var notes: [String] = []
    private var pictureCount = 0
    /// When the last press was put in the queue, by the system's uptime.
    private var lastPressTime: TimeInterval = 0

    /// The object a run of steps arranges, the tool that selects it and that tool's place in the markup row.
    private struct ArrangeSubject {
        let layer: ArrangedLayer
        let tool: PDFMarkupTool
        /// From the window's left edge, read from a picture of the row in this window of 1,280 by 860 points.
        let rowX: Double
    }

    private static let subjects = [ArrangeSubject(layer: .bluePicture, tool: .pictures, rowX: 882), ArrangeSubject(layer: .textBox, tool: .textBox, rowX: 734),
                                   ArrangeSubject(layer: .shape, tool: .shapes, rowX: 798)]

    private enum ArrangeRoute: String {
        case rightClickMenu = "right-click menu"
        /// What Tools › Arrange's items call (`PDFArrangeMenuActions`, made from the markup row's model) and what they
        /// read to dim themselves. The menu bar's own items stay dimmed for a window of a hosted test: SwiftUI gives the
        /// commands the focused values of its own scene windows only, and only while the app is in front (2026-11-17:
        /// every item dimmed, the app in the background and in front alike).
        case toolsArrangeActions = "Tools › Arrange's actions"
    }

    /// An Arrange menu as read before a choice: which of the six it leaves enabled, and how one is chosen.
    private struct ArrangeChoices {
        let enabled: Set<ArrangeCommand>
        let choose: (ArrangeCommand) -> Void
        /// A right-click menu, held while its items are used: an item's menu is weak, and the menu has no other owner.
        let heldMenu: NSMenu?
    }

    /// The window, the page and where its layers are.
    @MainActor
    private struct ArrangeStage {
        let window: NSWindow
        let session: PDFSession
        let page: PDFPage
        let view: GraphiteMacPDFView
        let pictureNames: [String: ArrangedLayer]
        let rectangles: [ArrangedLayer: CGRect]
        let samples: [OverlapSample]

        func windowPoint(_ pagePoint: CGPoint) -> CGPoint {
            view.convert(view.convert(pagePoint, from: page), to: nil)
        }

        /// Where a click or a right-click selects the layer: inside it, 12 points in from its top right corner, where the
        /// red picture does not reach the blue one.
        func selectionPoint(of layer: ArrangedLayer) throws -> CGPoint {
            let rectangle = try XCTUnwrap(rectangles[layer])
            return windowPoint(CGPoint(x: rectangle.maxX - 12, y: rectangle.maxY - 12))
        }

        var layersInMemory: [ArrangedLayer] { ArrangedLayer.layers(of: page, pictureNames: pictureNames) }
    }

    func testEachArrangeCommandFromBothMenusInTheRunningApp() async {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        // An error is caught here and reported: one thrown out of an async test method was seen to abort the app in
        // XCTest's error observation (2026-11-17, "freed pointer was not the last allocation").
        do {
            try await arrangeWithBothMenus()
        } catch {
            try? note("stopped by an error: \(error)")
            XCTFail("stopped by an error: \(error)")
        }
    }

    private func arrangeWithBothMenus() async throws {
        try note("started")
        // Twice on 2026-11-17 the app started hidden, its windows ordered out, and no click reached them. Shown again
        // without coming to the front, so the owner's app in front keeps the keyboard.
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
            try note("the app started hidden and was shown without activation")
        }
        let stage = try await openStackingPage()
        var expected = ExpectedStacking(layers: stage.layersInMemory)
        XCTAssertEqual(expected.layers, [.redPicture, .bluePicture, .ink, .textBox, .shape], "the pictures under the ink, the box and the shape over it")
        let rectangleLines = stage.rectangles.map { layer, rectangle in "\(layer.rawValue) \(rectangle.integral)" }.sorted()
        try note("rectangles \(rectangleLines), \(stage.samples.count) overlap points")
        let windowLines = NSApp.windows.map { window in
            "\(type(of: window)) \"\(window.title)\" \(window.frame.integral) visible \(window.isVisible) key \(window.isKeyWindow)"
        }
        try note("app active \(NSApp.isActive), key window \(String(describing: NSApp.keyWindow)), windows: \(windowLines)")
        try await expectOnScreenAndInFile(expected, step: "placed", in: stage, saving: true)
        try expectToolsArrangeInTheMenuBar()
        for subject in Self.subjects {
            try await choose(subject.tool, atRowX: subject.rowX, in: stage)
            expected = try await chooseEachCommand(for: subject, through: .rightClickMenu, from: expected, in: stage)
            try await selectByClick(subject, in: stage)
            expected = try await chooseEachCommand(for: subject, through: .toolsArrangeActions, from: expected, in: stage)
        }
        try FileManager.default.copyItem(at: stage.session.location, to: try XCTUnwrap(outputFolder).appendingPathComponent("Stacking arranged.pdf"))
    }

    // MARK: The steps

    /// Chooses each of the six commands once from `route`, whichever its dimmed items allow next, with the menu read
    /// before each choice and once more at the end, and the object seen at the top, in the middle and at the bottom.
    private func chooseEachCommand(for subject: ArrangeSubject, through route: ArrangeRoute, from start: ExpectedStacking,
                                   in stage: ArrangeStage) async throws -> ExpectedStacking {
        var expected = start
        var remaining = ArrangeCommand.all
        var places: Set<PlaceAmongObjects> = []
        while true {
            let place = expected.place(of: subject.layer)
            places.insert(place)
            let possible = expected.possibleCommands(for: subject.layer)
            let choices = try await arrangeChoices(through: route, for: subject, in: stage)
            let enabled = choices.enabled
            XCTAssertEqual(Set(enabled.map(\.title)), Set(possible.map(\.title)),
                           "\(route.rawValue) of the \(subject.layer.rawValue) at the \(place.rawValue): the items not dimmed")
            // A menu that is wrong already would only choose dimmed items from here on.
            guard enabled == possible else { break }
            guard !remaining.isEmpty else { break }
            guard let command = remaining.first(where: possible.contains), let after = expected.applying(command, to: subject.layer) else {
                XCTFail("\(route.rawValue) of the \(subject.layer.rawValue): none of \(remaining) can be chosen in \(expected.layers)")
                break
            }
            remaining.removeAll { left in left == command }
            let step = "\(subject.layer.rawValue), \(route.rawValue), \(command.title)"
            try await asOneAction(in: stage) { choices.choose(command) }
            withExtendedLifetime(choices.heldMenu) {}
            try await expectOneStep(command, named: step, from: expected, to: after, in: stage)
            expected = after
        }
        XCTAssertEqual(places, [.top, .middle, .bottom], "\(route.rawValue): the \(subject.layer.rawValue) was at the top, in the middle and at the bottom")
        return expected
    }

    /// The move on screen and in the page, named after the command in Undo, taken back by one Undo, put back by Redo,
    /// and saved.
    private func expectOneStep(_ command: ArrangeCommand, named step: String, from before: ExpectedStacking, to after: ExpectedStacking,
                               in stage: ArrangeStage) async throws {
        try await expectOnScreenAndInFile(after, step: step, in: stage)
        XCTAssertEqual(stage.session.undoManager.undoActionName, command.title, "\(step): the step Undo names")
        try await clickToolbarItem(labelled: "Undo", in: stage.window)
        try await expectOnScreenAndInFile(before, step: "\(step), undone", in: stage)
        try await clickToolbarItem(labelled: "Redo", in: stage.window)
        try await expectOnScreenAndInFile(after, step: "\(step), redone", in: stage, saving: true)
    }

    /// The page's order, the colour of every overlap point in a picture of the window, and, `saving`, the order of the
    /// file saved and read back as another application reads it.
    private func expectOnScreenAndInFile(_ expected: ExpectedStacking, step: String, in stage: ArrangeStage, saving: Bool = false) async throws {
        XCTAssertEqual(stage.layersInMemory, expected.layers, "\(step): the page's order")
        let picture = try WindowPicture(pngData: try writePicture(step, of: stage.window))
        var wrongPoints: [String] = []
        var largestDistance = 0.0
        for sample in stage.samples {
            let shouldShow = expected.colour(where: sample.covering)
            let shown = picture.colour(atWindowPoint: stage.windowPoint(sample.pagePoint)).flatMap(ScreenColour.nearest(to:))
            if shown?.colour != shouldShow { wrongPoints.append("\(sample.pagePoint) \(shown?.colour.rawValue ?? "nothing") for \(shouldShow.rawValue)") }
            largestDistance = max(largestDistance, shown?.distance ?? 0)
        }
        XCTAssertTrue(wrongPoints.isEmpty,
                      "\(step): \(wrongPoints.count) of \(stage.samples.count) overlap points show another colour, \(wrongPoints.prefix(3))")
        var line = "\(String(format: "%03d", pictureCount)) \(step): \(expected.layers.map(\.rawValue)); \(stage.samples.count - wrongPoints.count) of "
            + "\(stage.samples.count) overlap points right (farthest \(String(format: "%.2f", largestDistance)) from its colour)"
        if saving {
            try await stage.session.save()
            let saved = try XCTUnwrap(PDFDocument(url: stage.session.location)?.page(at: 0), "the saved file reads back")
            let savedLayers = ArrangedLayer.layers(of: saved, pictureNames: stage.pictureNames)
            XCTAssertEqual(savedLayers, expected.layers, "\(step): the saved file's order")
            line += "; saved \(savedLayers == expected.layers ? "in that order" : "as \(savedLayers.map(\.rawValue))")"
        }
        try note(line)
    }

    // MARK: The menus

    /// The route's Arrange items for the selected object. A right-click menu is asked of the view under the pointer and
    /// its items chosen as a click chooses them, by the menu performing the item's action.
    private func arrangeChoices(through route: ArrangeRoute, for subject: ArrangeSubject, in stage: ArrangeStage) async throws -> ArrangeChoices {
        switch route {
        case .rightClickMenu:
            let point = try stage.selectionPoint(of: subject.layer)
            let viewUnderPointer = try XCTUnwrap(stage.window.contentView?.hitTest(point), "a view under the \(subject.layer.rawValue)")
            let rightClick = try mouseEvent(.rightMouseDown, at: point, in: stage.window)
            let menu = try XCTUnwrap(viewUnderPointer.menu(for: rightClick), "the \(subject.layer.rawValue)'s right-click menu")
            try await settle(stage.window)
            var items: [ArrangeCommand: NSMenuItem] = [:]
            for command in ArrangeCommand.all { items[command] = menu.items.first { item in item.title == command.title } }
            return ArrangeChoices(enabled: Set(ArrangeCommand.all.filter { command in items[command]?.isEnabled == true }), choose: { command in
                guard let item = items[command], item.isEnabled else { return XCTFail("\(command.title) is dimmed") }
                menu.performActionForItem(at: menu.index(of: item))
            }, heldMenu: menu)
        case .toolsArrangeActions:
            let toolbar = try XCTUnwrap(stage.view.markupInteraction?.toolbar)
            let enabled = Set(ArrangeCommand.all.filter { command in
                (command.movesInk ? toolbar.selectedPageInkArrangements : toolbar.selectedObjectArrangements).contains(command.arrangement)
            })
            return ArrangeChoices(enabled: enabled, choose: { command in
                guard enabled.contains(command) else { return XCTFail("\(command.title) is dimmed") }
                if command.movesInk { toolbar.arrangeInkOfSelectedPage?(command.arrangement) } else { toolbar.arrangeSelectedObject?(command.arrangement) }
            }, heldMenu: nil)
        }
    }

    /// The menu bar's Tools › Arrange holds the six items, in the menus' order, the ink's after a line.
    private func expectToolsArrangeInTheMenuBar() throws {
        let toolsMenu = try XCTUnwrap(NSApp.mainMenu?.items.first { item in item.title == "Tools" }?.submenu, "a Tools menu in the menu bar")
        toolsMenu.update()
        let arrangeMenu = try XCTUnwrap(toolsMenu.items.first { item in item.title == "Arrange" }?.submenu, "Tools › Arrange")
        arrangeMenu.update()
        let titles = arrangeMenu.items.map { item in item.isSeparatorItem ? "—" : item.title }
        XCTAssertEqual(titles, PDFArrangement.menuArrangements.map(\.title) + ["—"] + PDFArrangement.inkMenuArrangements.map(\.inkTitle))
        try note("the menu bar's Tools › Arrange: \(titles)")
    }

    // MARK: The page

    private func openStackingPage() async throws -> ArrangeStage {
        let vaultRoot = try TemporaryVault.make(prefix: "MacArrangeInApp", for: self).root
        try ArrangeTestPage.writeBlankPDF(to: vaultRoot.appendingPathComponent("Stacking.pdf"))
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        _ = await workspace.open(try VaultPath("Stacking.pdf"), placement: .currentTab)
        try await waitUntil("the PDF is shown", timeoutSeconds: 30) { (workspace.pdfSession?.pageCount ?? 0) > 0 }
        try await settle(window)
        try note("the PDF is shown; toolbar items \(window.toolbar?.items.map(\.label) ?? [])")
        try await clickToolbarItem(labelled: "Show Markup Toolbar", in: window)
        let session = try XCTUnwrap(workspace.pdfSession)
        // Each action of the test is one undo group, as each of a person's clicks is (MacPDFMarkupInAppHostedTests).
        session.undoManager.groupsByEvent = false
        let view = try XCTUnwrap(ReleaseVaultViews.descendants(of: try XCTUnwrap(window.contentView), ofType: GraphiteMacPDFView.self).first)
        return try await placeObjects(on: try XCTUnwrap(session.document.page(at: 0)), session: session, view: view, window: window)
    }

    /// Two pictures side by side, overlapping; a bold green stroke across both; a yellow text box and a purple rectangle
    /// over them, each overlapping the others.
    private func placeObjects(on page: PDFPage, session: PDFSession, view: GraphiteMacPDFView, window: NSWindow) async throws -> ArrangeStage {
        // Each placement is an undo group of its own: with grouping by event off, an edit outside a group raises.
        for (colour, centerX) in [(ScreenColour.red, 240.0), (.blue, 340)] {
            let imageData = try ArrangeTestPage.solidPNG(colour)
            session.undoManager.beginUndoGrouping()
            var thrown: (any Error)?
            do {
                try await session.addPicture(imageData: imageData, placement: (pageIndex: 0, center: CGPoint(x: centerX, y: 560)), preferredWidth: 200)
            } catch {
                thrown = error
            }
            session.undoManager.endUndoGrouping()
            if let thrown { throw thrown }
        }
        session.selectedPicture = nil
        let pictureNames = session.pictures(on: page).map(\.name)
        XCTAssertEqual(pictureNames.count, 2)
        let partialStage = ArrangeStage(window: window, session: session, page: page, view: view, pictureNames: [:], rectangles: [:], samples: [])
        try await choose(.draw, atRowX: 662, in: partialStage)
        view.markupInteraction?.toolbar?.useInkStyle(PDFMarkupInkStyle(color: ScreenColour.green.textColor, width: .bold))
        try await drag(through: ArrangeTestPage.inkStrokePoints.map(partialStage.windowPoint), in: partialStage)
        try note("pictures placed and ink drawn: \(page.annotations.map { annotation in annotation.type ?? "?" })")
        // Its text in its own fill's colour, so no letter is read as another layer.
        let text = PDFTextRun(text: "Box", attributes: PDFTextAttributes(fontFamily: "Helvetica", fontSize: 60, color: ScreenColour.yellow.textColor))
        let box = PDFTextBoxLayout.fitted(PDFTextBox(runs: [text],
                                                     origin: CGPoint(x: 200, y: 570), width: 124, height: 80, rotationRadians: 0,
                                                     style: PDFTextBoxStyle(alignment: .left, fillColor: ScreenColour.yellow.textColor, padding: 4)))
        session.undoManager.beginUndoGrouping()
        defer { if session.undoManager.groupingLevel > 0 { session.undoManager.endUndoGrouping() } }
        try session.changeTextBox(from: nil, to: box, on: session.historyPage(for: page), actionName: "Add Text Box")
        try session.addShape(PDFShape(kind: .rectangle, start: CGPoint(x: 290, y: 480), end: CGPoint(x: 420, y: 590),
                                      borderColor: ScreenColour.purple.textColor, fillColor: ScreenColour.purple.textColor, lineWidth: 2), on: page)
        session.undoManager.endUndoGrouping()
        try await settle(window)
        let names = Dictionary(uniqueKeysWithValues: zip(pictureNames, [ArrangedLayer.redPicture, .bluePicture]))
        var rectangles: [ArrangedLayer: CGRect] = [.ink: ArrangeTestPage.inkBand]
        for annotation in page.annotations {
            if let layer = ArrangedLayer.layer(of: annotation, pictureNames: names), layer != .ink { rectangles[layer] = annotation.bounds }
        }
        let samples = OverlapSample.overlaps(of: rectangles, inkRows: ArrangeTestPage.inkRows)
        return ArrangeStage(window: window, session: session, page: page, view: view, pictureNames: names, rectangles: rectangles, samples: samples)
    }

    // MARK: Pressing controls

    /// Escape takes the run before's selection away, then a click on the object selects it with its tool.
    private func selectByClick(_ subject: ArrangeSubject, in stage: ArrangeStage) async throws {
        let toolbar = try XCTUnwrap(stage.view.markupInteraction?.toolbar)
        // A person's click makes the PDF view the first responder; the right-click menus before did not.
        stage.window.makeFirstResponder(stage.view)
        try await pressEscape(in: stage)
        XCTAssertTrue(toolbar.selectedObjectArrangements.isEmpty, "Escape left the \(subject.layer.rawValue)")
        let point = try stage.selectionPoint(of: subject.layer)
        try await asOneAction(in: stage, posting: [try mouseEvent(.leftMouseDown, at: point, in: stage.window),
                                                   try mouseEvent(.leftMouseUp, at: point, in: stage.window)])
        XCTAssertFalse(toolbar.selectedObjectArrangements.isEmpty, "the click selected the \(subject.layer.rawValue)")
        XCTAssertFalse(stage.window.firstResponder is NSTextView, "the click selected the box without typing in it")
        try note("selected the \(subject.layer.rawValue) by a click: Tools › Arrange can do \(toolbar.selectedObjectArrangements.map(\.title).sorted())")
    }

    /// Clicks a tool of the markup row and waits until the PDF view has it, clicking again when a click was lost.
    private func choose(_ tool: PDFMarkupTool, atRowX x: Double, in stage: ArrangeStage) async throws {
        let hasIt = { @MainActor in stage.view.markupInteraction?.input.markupTool == tool }
        for _ in 1...3 where !hasIt() {
            let point = CGPoint(x: x, y: 860 - 113)
            try await asOneAction(in: stage, posting: [try mouseEvent(.leftMouseDown, at: point, in: stage.window),
                                                       try mouseEvent(.leftMouseUp, at: point, in: stage.window)])
            for _ in 0..<5 where !hasIt() { try await settle(stage.window) }
        }
        XCTAssertTrue(hasIt(), "the row chose \(tool.title)")
    }

    /// A toolbar item clicked a quarter of the way across (Undo and Redo keep their arrow menus in their right half),
    /// with no undo group of the test's own: an undo with a group open takes back that empty group.
    private func clickToolbarItem(labelled label: String, in window: NSWindow) async throws {
        let item = try XCTUnwrap(window.toolbar?.items.first { item in item.label == label }, "no toolbar item labelled \(label)")
        let view = try XCTUnwrap(item.view)
        let frame = view.convert(view.bounds, to: nil)
        let point = CGPoint(x: frame.minX + 0.25 * frame.width, y: frame.midY)
        try await prepareForPress()
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { NSApp.postEvent(try mouseEvent(type, at: point, in: window), atStart: false) }
        try await settle(window)
    }

    private func pressEscape(in stage: ArrangeStage) async throws {
        let escape = String(UnicodeScalar(UInt8(27)))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: stage.window.windowNumber, context: nil, characters: escape,
                                                   charactersIgnoringModifiers: escape, isARepeat: false, keyCode: 53))
        try await asOneAction(in: stage, posting: [event])
    }

    /// A press, a drag through the points and a release, put in the application's queue in order.
    private func drag(through windowPoints: [CGPoint], in stage: ArrangeStage) async throws {
        guard let first = windowPoints.first, let last = windowPoints.last else { return }
        var events = [try mouseEvent(.leftMouseDown, at: first, in: stage.window)]
        for point in windowPoints.dropFirst() { events.append(try mouseEvent(.leftMouseDragged, at: point, in: stage.window)) }
        events.append(try mouseEvent(.leftMouseUp, at: last, in: stage.window))
        try await asOneAction(in: stage, posting: events)
    }

    /// Waits out a double-click's time since the last press, and shows the app again if it was hidden. A press soon
    /// after another at another place was seen to be dropped (MacPDFMarkupInAppHostedTests; here on 2026-11-17, a Redo
    /// right after an Undo), and the app was seen hidden in mid-run, when no press reaches its windows.
    private func prepareForPress() async throws {
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
            try note("the app was hidden; shown again without activation")
        }
        let lastPress = lastPressTime
        try await waitUntil("a double-click's time since the last press", timeoutSeconds: 5) {
            ProcessInfo.processInfo.systemUptime - lastPress >= NSEvent.doubleClickInterval
        }
        lastPressTime = ProcessInfo.processInfo.systemUptime
    }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    /// Runs one action of a person's as one undo group: XCTest runs inside one turn of the event loop, so AppKit never
    /// closes the group an event opens.
    /// The action is synchronous and the events are made beforehand: an error thrown out of an async closure here aborted
    /// the app in the concurrency runtime (2026-11-17, "freed pointer was not the last allocation").
    private func asOneAction(in stage: ArrangeStage, posting events: [NSEvent] = [], _ action: () -> Void = {}) async throws {
        if events.contains(where: { event in event.type == .leftMouseDown }) { try await prepareForPress() }
        let undoManager = stage.session.undoManager
        undoManager.beginUndoGrouping()
        action()
        for event in events { NSApp.postEvent(event, atStart: false) }
        var thrown: (any Error)?
        do { try await settle(stage.window) } catch { thrown = error }
        undoManager.endUndoGrouping()
        if let thrown { throw thrown }
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 20).measure({}, until: { true })
    }

    // MARK: Output

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    /// A picture of the window's content with the PDF's pages drawn in, written to the output folder and returned.
    private func writePicture(_ name: String, of window: NSWindow) throws -> Data {
        let pngData = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        pictureCount += 1
        let fileName = String(format: "%03d %@.png", pictureCount, name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "›", with: "-"))
        try pngData.write(to: try XCTUnwrap(outputFolder).appendingPathComponent(fileName))
        return pngData
    }
}
#endif
