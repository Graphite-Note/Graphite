/**
 * File: BugHuntMacViewsTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Bug hunt fixes checked in the Mac's own views, in a window no one sees: the Colors page's remove buttons,
 *              row menu and question, the Editor page's tab size, the notebook's page count field, the changed-file banner
 *              in a narrow and a wide window, the library tile's callout icons, and the sheet sizes and labels the
 *              iPhone gets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import Vision
import XCTest
import GraphiteApple
import GraphiteCore
import GraphiteFixtures
@testable import GraphiteUI
import GraphiteTestSupport

/// What the hosted iPad tests cannot reach: the same views on the Mac, clicked as a mouse clicks them and read from
/// their pixels as a person reads them. Nothing here plays sound or shows anything on a screen a person looks at.
@MainActor
final class BugHuntMacViewsTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        windows = []
        testBed.tearDown()
    }

    private func show<Content: View>(_ content: Content, size: CGSize) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.showInvisibly()
        windows.append(window)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { child in [child] + descendants(of: child) }
    }

    /// The texts the view draws, read from its pixels by the system's text recognition, with their frames in the
    /// view's points from its top left (an `NSHostingView` is flipped).
    private func drawnTexts(in view: NSView) throws -> [(text: String, frame: CGRect)] {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
        let size = view.bounds.size
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return (text, CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height))
        }
    }

    /// A mouse click at a point of a hosting view, sent through its window as AppKit delivers one.
    private func click(at point: CGPoint, in view: NSView) throws {
        let window = try XCTUnwrap(view.window)
        let location = view.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    // MARK: HUNT-242: removing and moving a color on the Mac

    /// The Colors page's buttons AppKit draws, from the top: each row's remove button (the Mac's Form rows have no swipe).
    private func removeButtons(in hosting: NSView) -> [NSButton] {
        descendants(of: hosting).compactMap { view in view as? NSButton }
            .sorted { first, second in first.convert(first.bounds, to: hosting).minY < second.convert(second.bounds, to: hosting).minY }
    }

    func testOnTheMacAColorIsRemovedByItsButtonAndMovedByItsRowsMenu() async throws {
        let preferences = GraphitePreferences(defaults: try testBed.isolatedDevice().defaults)
        let palette = preferences.colorPalette
        XCTAssertGreaterThanOrEqual(palette.count, 3)
        let size = CGSize(width: 600, height: 700)
        let hosting = show(ColorsSettingsPage(preferences: preferences).frame(width: size.width, height: size.height), size: size)
        try await waitUntil("a remove button on each row") {
            self.removeButtons(in: hosting).count >= palette.count + preferences.highlighterPalette.count
        }
        removeButtons(in: hosting)[0].performClick(nil)
        try await waitUntil("the first color is gone") { preferences.colorPalette.count == palette.count - 1 }
        XCTAssertEqual(preferences.colorPalette.map(\.name), palette.dropFirst().map(\.name), "The first row's button removed the first color only.")

        // The second row's menu, as a right-click beside its name field opens it.
        let secondName = preferences.colorPalette[1].name
        var nameField: NSTextField?
        try await waitUntil("the second row's name field") {
            nameField = self.descendants(of: hosting).compactMap { view in view as? NSTextField }.first { field in field.isEditable && field.stringValue == secondName }
            return nameField != nil
        }
        let field = try XCTUnwrap(nameField)
        let window = try XCTUnwrap(hosting.window)
        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: field.convert(CGPoint(x: field.bounds.maxX + 30, y: field.bounds.midY), to: nil),
                                                         modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(hosting.menu(for: rightClick), "A row has a menu on the Mac.")
        XCTAssertEqual(menu.items.map(\.title), ["Move Up", "Move Down"])
        let moveUpIndex = try XCTUnwrap(menu.items.firstIndex { item in item.title == "Move Up" })
        menu.performActionForItem(at: moveUpIndex)
        try await waitUntil("the second color moves up") { preferences.colorPalette.first?.name == secondName }
    }

    // MARK: HUNT-250: the Restore question on the Mac

    func testOnTheMacRestoringTheDefaultPaletteAsksInASheetFirst() async throws {
        let preferences = GraphitePreferences(defaults: try testBed.isolatedDevice().defaults)
        preferences.colorPalette.append(PaletteColor(name: "mine", hex: "#123456"))
        let size = CGSize(width: 600, height: 700)
        let hosting = show(ColorsSettingsPage(preferences: preferences).frame(width: size.width, height: size.height), size: size)
        var restoreFrame: CGRect?
        try await waitUntil("Restore Default Palette is drawn") {
            restoreFrame = try self.drawnTexts(in: hosting).first { drawn in drawn.text.contains("Restore Default Palette") }?.frame
            return restoreFrame != nil
        }
        let frame = try XCTUnwrap(restoreFrame)
        try click(at: CGPoint(x: frame.midX, y: frame.midY), in: hosting)
        let window = try XCTUnwrap(hosting.window)
        try await waitUntil("the question, in a sheet of the window") { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let sheetTexts = descendants(of: try XCTUnwrap(sheet.contentView)).compactMap { view in (view as? NSTextField)?.stringValue }
        XCTAssertTrue(sheetTexts.contains("Replace your palette with the default colors?"), "\(sheetTexts)")
        XCTAssertTrue(sheetTexts.contains { text in text.contains("This cannot be undone.") }, "The question names what is lost.")
        let sheetButtons = descendants(of: try XCTUnwrap(sheet.contentView)).compactMap { view in (view as? NSButton)?.title }
        XCTAssertTrue(sheetButtons.contains("Restore Default Palette") && sheetButtons.contains("Cancel"), "\(sheetButtons)")
        XCTAssertTrue(preferences.colorPalette.contains { color in color.name == "mine" }, "Nothing is replaced before the person agrees.")
    }

    // MARK: HUNT-256: the Mac's Editor page has the Typing section

    func testTheMacEditorPageChangesTheVaultsTabIndentSize() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: [".obsidian/app.json": #"{"useTab": false, "tabSize": 4}"#, "Note.md": "x"])
        XCTAssertEqual(workspace.vaultSettings.tabSize, 4)
        let size = CGSize(width: 600, height: 1_400)
        let page = EditorSettingsPage(workspace: workspace, preferences: workspace.preferences, vaultSettingsChanges: VaultSettingsChanges())
        let hosting = show(page.frame(width: size.width, height: size.height), size: size)
        var foundStepper: NSStepper?
        try await waitUntil("the Typing section's Tab Indent Size stepper") {
            foundStepper = self.descendants(of: hosting).compactMap { view in view as? NSStepper }.first
            return foundStepper != nil
        }
        // SwiftUI's stepper takes a step up from the control's value going up.
        let stepper = try XCTUnwrap(foundStepper)
        stepper.integerValue += 1
        stepper.sendAction(stepper.action, to: stepper.target)
        var savedSettings: [String: Any]?
        try await waitUntil("the vault's app.json has the new size", timeoutSeconds: 10) {
            let data = try? Data(contentsOf: vault.appendingPathComponent(".obsidian/app.json"))
            savedSettings = data.flatMap { data in try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
            return savedSettings?["tabSize"] as? Int == 5
        }
        XCTAssertEqual(savedSettings?["useTab"] as? Bool, false, "Indent Using Tabs stays as the vault had it.")
    }

    // MARK: HUNT-217: a page count typed into a field

    func testANotebooksPageCountIsTypedIntoTheFieldBesideItsStepper() async throws {
        var options = NewNotebookOptions(paperChoice: .dotted, paperStyle: PaperSpecification(), pageSize: .named(.a4, .portrait), pageCount: 1)
        let binding = Binding(get: { options.pageCount }, set: { pageCount in options.pageCount = pageCount })
        let size = CGSize(width: 400, height: 100)
        let hosting = show(Form { NotebookPageCountControl(pageCount: binding) }.frame(width: size.width, height: size.height), size: size)
        XCTAssertFalse(descendants(of: hosting).compactMap { view in view as? NSStepper }.isEmpty, "The stepper stays beside the field.")
        for (typed, problem) in [("300", nil), ("5000", NewNotebookProblem.pageCountOutOfRange)] as [(String, NewNotebookProblem?)] {
            var foundField: NSTextField?
            try await waitUntil("the Pages field") {
                foundField = self.descendants(of: hosting).compactMap { view in view as? NSTextField }.first { field in field.isEditable }
                return foundField != nil
            }
            let field = try XCTUnwrap(foundField)
            let window = try XCTUnwrap(hosting.window)
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.selectAll(nil)
            editor.insertText(typed, replacementRange: editor.selectedRange())
            editor.insertNewline(nil)
            try await waitUntil("\(typed) pages") { options.pageCount == Int(typed) }
            XCTAssertEqual(options.problem, problem, "\(typed) pages")
        }
    }

    // MARK: HUNT-290: the changed-file banner in a narrow window

    func testTheChangeBannerPutsItsButtonsUnderTheSentenceWhereTheyDoNotFitBesideIt() async throws {
        let message = "This note changed in another app. Your edits are still here."
        for (width, isStacked) in [(CGFloat(390), true), (1_000, false)] {
            let size = CGSize(width: width, height: 160)
            let banner = ExternalChangeBanner(message: message, saveCopy: {}, useOtherVersion: {}).frame(width: width).background(Color.white)
            let hosting = show(banner, size: size)
            var texts: [(text: String, frame: CGRect)] = []
            try await waitUntil("the banner is drawn at \(Int(width)) points") {
                texts = try self.drawnTexts(in: hosting)
                return texts.contains { drawn in drawn.text.contains("Save a Copy") } && texts.contains { drawn in drawn.text.contains("another app") }
            }
            let saveCopy = try XCTUnwrap(texts.first { drawn in drawn.text.contains("Save a Copy") }).frame
            let sentenceLines = texts.filter { drawn in !drawn.text.contains("Save a Copy") && !drawn.text.contains("Use Other Version") }.map(\.frame)
            let sentenceBottom = try XCTUnwrap(sentenceLines.map(\.maxY).max())
            let sentenceWidth = try XCTUnwrap(sentenceLines.map(\.width).max())
            if isStacked {
                XCTAssertGreaterThanOrEqual(saveCopy.minY, sentenceBottom - 1, "At \(Int(width)) points the buttons are under the sentence.")
                XCTAssertLessThan(saveCopy.minX, width * 0.3, "They start at the banner's leading edge.")
                XCTAssertGreaterThan(sentenceWidth, width * 0.6, "The sentence keeps the banner's width rather than a column beside the buttons.")
            } else {
                XCTAssertLessThan(saveCopy.minY, sentenceBottom, "Where they fit the buttons are on the sentence's row.")
                XCTAssertGreaterThan(saveCopy.minX, width * 0.5, "Beside it, at the end of the row.")
            }
        }
    }

    // MARK: HUNT-297: a library tile's callout icons

    /// The pixels of a note's library tile whose only block is a callout of this type, titled alike for every type.
    private func tilePixels(ofCalloutType calloutType: String) throws -> [UInt8] {
        let summary = NotePreviewSummary(blocks: [.callout(type: calloutType, title: AttributedString("Title"))], firstPictureTarget: nil)
        let renderer = ImageRenderer(content: LibraryNotePage(summary: summary, picture: nil, displayScale: 2).frame(width: 300))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, calloutType)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// The tile used to draw a bug, a danger and a failure callout with one icon (`xmark.octagon`), while the note
    /// draws a ladybug, a bolt and a cross. All three are red, so with the same title only the icon can tell them apart.
    func testALibraryTileDrawsEachCalloutWithTheNotesOwnIcon() throws {
        let bug = try tilePixels(ofCalloutType: "bug")
        let danger = try tilePixels(ofCalloutType: "danger")
        let failure = try tilePixels(ofCalloutType: "failure")
        XCTAssertEqual(danger, try tilePixels(ofCalloutType: "error"), "Two names of one callout draw the same tile, so the pictures compare.")
        XCTAssertNotEqual(bug, danger)
        XCTAssertNotEqual(bug, failure)
        XCTAssertNotEqual(danger, failure)
        for type in ["bug", "danger", "failure"] {
            XCTAssertEqual(CalloutAppearance(type: type).color, CalloutAppearance(type: "bug").color, "\(type) is red in the note, so only its icon differs.")
        }
    }

    // MARK: HUNT-271, HUNT-272: no sheet is wider or taller than a phone

    /// The Swift files of the app's interface, as text.
    private func interfaceSources() throws -> [(name: String, text: String)] {
        let folder = FixtureFolders.repositoryRoot.appendingPathComponent("Sources/GraphiteUI", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { name in name.hasSuffix(".swift") }.sorted()
        return try names.map { name in (name, try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) }
    }

    /// Each `.frame(minWidth: …` or `minHeight: …` line that iOS builds, with its numbers: a line inside `#if os(macOS)`
    /// (or the `#else` of `#if canImport(UIKit)` or `#if os(iOS)`) is the Mac's alone.
    private func minimumFramesBuiltForIOS(in text: String) -> [(line: String, width: Double?, height: Double?)] {
        var branches: [(condition: String, isElse: Bool)] = []
        var frames: [(line: String, width: Double?, height: Double?)] = []
        func number(after label: String, in line: String) -> Double? {
            guard let range = line.range(of: label + ": ") else { return nil }
            return Double(line[range.upperBound...].prefix { character in character.isNumber || character == "." })
        }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") { branches.append((String(trimmed.dropFirst(4)), false)); continue }
            if trimmed.hasPrefix("#elseif ") || trimmed == "#else" { if !branches.isEmpty { branches[branches.count - 1].isElse = true }; continue }
            if trimmed.hasPrefix("#endif") { _ = branches.popLast(); continue }
            guard trimmed.contains(".frame("), trimmed.contains("minWidth:") || trimmed.contains("minHeight:") else { continue }
            let isMacOnly = branches.contains { branch in
                (branch.condition.contains("os(macOS)") && !branch.isElse)
                    || ((branch.condition.contains("canImport(UIKit)") || branch.condition.contains("os(iOS)")) && branch.isElse)
            }
            if !isMacOnly { frames.append((trimmed, number(after: "minWidth", in: trimmed), number(after: "minHeight", in: trimmed))) }
        }
        return frames
    }

    /// A phone's sheet is 375 to 440 points wide and, held sideways, about 400 tall; Slide Over is 320 wide. A minimum
    /// beyond that lays the sheet out larger than the screen and cuts off its Cancel and title bar. The Mac's minimums go
    /// through `sheetMinimumSize`, which the hosted `testTheVaultManagerFitsTheWidthOfAPhone` shows leaves an iOS sheet
    /// its width.
    func testNoViewBuiltForIOSAsksForMoreThanAPhonesRoom() throws {
        var tooLarge: [String] = []
        for source in try interfaceSources() where source.name != "SheetMinimumSize.swift" {
            for frame in minimumFramesBuiltForIOS(in: source.text) where (frame.width ?? 0) > 320 || (frame.height ?? 0) > 360 {
                tooLarge.append("\(source.name): \(frame.line)")
            }
        }
        XCTAssertEqual(tooLarge, [], "Use sheetMinimumSize(width:height:) or keep the minimum for the Mac.")
    }

    func testTheFileSheetsNamedInTheHuntTakeTheirMinimumOnTheMacOnly() throws {
        let sources = Dictionary(uniqueKeysWithValues: try interfaceSources().map { source in (source.name, source.text) })
        for name in ["FileSheets.swift", "ConflictVersionsSheet.swift", "FileRecoverySheet.swift", "NotebookImportReportSheet.swift", "CommunityPluginSettings.swift",
                     "CommunityPluginPresentation.swift"] {
            let text = try XCTUnwrap(sources[name], name)
            XCTAssertTrue(text.contains(".sheetMinimumSize("), "\(name) sizes its sheet for the Mac only.")
            XCTAssertEqual(minimumFramesBuiltForIOS(in: text).filter { frame in (frame.width ?? 0) > 320 }.map(\.line), [], name)
        }
    }

    // MARK: HUNT-301: Settings labels in Title Case

    private func isTitleCase(_ label: String) -> Bool {
        let smallWords: Set<String> = ["a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to"]
        let words = label.split(separator: " ").map(String.init)
        return words.enumerated().allSatisfy { wordIndex, word in
            guard let first = word.first, first.isLetter else { return true }
            return first.isUppercase || (wordIndex > 0 && smallWords.contains(word))
        }
    }

    func testSettingsFieldAndStepperLabelsAreTitleCase() throws {
        var labels: [String] = []
        for source in try interfaceSources() {
            for pattern in [#"SettingsTextField\(title: "([^"\\]+)""#, #"field\("([^"\\]+)", prompt:"#, #"Stepper\("([^":\\]+)"#] {
                let expression = try NSRegularExpression(pattern: pattern)
                let text = source.text as NSString
                labels += expression.matches(in: source.text, range: NSRange(location: 0, length: text.length)).map { match in text.substring(with: match.range(at: 1)) }
            }
        }
        for expected in ["Template Folder Location", "Date Format", "Time Format", "New File Location", "Template File Location", "Tab Indent Size",
                         "Snapshot Interval", "History Length"] {
            XCTAssertTrue(labels.contains(expected), "\(expected) is a label of Settings.")
        }
        XCTAssertEqual(labels.filter { label in !isTitleCase(label) }, [], "Settings labels are Title Case, as the rest of Settings.")
    }
}
#endif
