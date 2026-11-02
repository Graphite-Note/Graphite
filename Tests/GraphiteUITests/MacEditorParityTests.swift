/**
 * File: MacEditorParityTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The Mac note editor does what the iPad's does: lists, Tab, pairs, folds, the note's name, and clicks that act on release.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacEditorParityTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// A note's editor with the keyboard, the cursor at `cursor`.
    private func makeEditor(text: String, cursor: Int = 0) async throws -> MacMarkdownEditorFixture {
        let fixture = try await MacMarkdownEditorFixture(text: text)
        self.fixture = fixture
        fixture.window.makeFirstResponder(fixture.textView)
        fixture.textView.setSelectedRange(NSRange(location: cursor, length: 0))
        return fixture
    }

    private func isHidden(_ location: Int, in textView: NSTextView) -> Bool {
        ((textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.maximumLineHeight ?? 0) == 0.01
    }

    private func turnRunLoop(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date.now.addingTimeInterval(seconds))
    }

    // MARK: HUNT-058

    func testReturnContinuesAListAndUndoTakesItBack() async throws {
        let editor = try await makeEditor(text: "- item", cursor: 6)
        editor.textView.insertNewline(nil)
        XCTAssertEqual(editor.textView.string, "- item\n- ")
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertEqual(editor.session.text, "- item\n- ")
        editor.coordinator.noteUndoManager.undo()
        XCTAssertEqual(editor.textView.string, "- item")
    }

    func testReturnContinuesNumbersAndTasksAndEndsAnEmptyItem() async throws {
        let numbered = try await makeEditor(text: "1. one\n2. two", cursor: 6)
        numbered.textView.insertNewline(nil)
        XCTAssertEqual(numbered.textView.string, "1. one\n2. \n3. two", "The items below count on, as on the iPad.")
        numbered.tearDown()
        let task = try await makeEditor(text: "- [x] done", cursor: 10)
        task.textView.insertNewline(nil)
        XCTAssertEqual(task.textView.string, "- [x] done\n- [ ] ")
        task.textView.insertNewline(nil)
        XCTAssertEqual(task.textView.string, "- [x] done\n", "Return on an empty item ends the list.")
    }

    func testReturnInPlainTextAndInCodeIsAPlainLineBreak() async throws {
        let editor = try await makeEditor(text: "```\n- code\n```", cursor: 10)
        editor.textView.insertNewline(nil)
        XCTAssertEqual(editor.textView.string, "```\n- code\n\n```")
    }

    func testTabIndentsAListItem() async throws {
        let editor = try await makeEditor(text: "- one\n- two", cursor: 8)
        editor.textView.insertTab(nil)
        XCTAssertEqual(editor.textView.string, "- one\n\t- two")
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 9, length: 0))
        editor.coordinator.noteUndoManager.undo()
        XCTAssertEqual(editor.textView.string, "- one\n- two")
    }

    func testTabInPlainTextInsertsATab() async throws {
        let editor = try await makeEditor(text: "plain", cursor: 5)
        editor.textView.insertTab(nil)
        XCTAssertEqual(editor.textView.string, "plain\t")
    }

    func testBracketsPairAndBackspaceRemovesThePair() async throws {
        let editor = try await makeEditor(text: "", cursor: 0)
        editor.textView.insertText("(", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "()")
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 1, length: 0))
        editor.textView.insertText(")", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "()", "A closing bracket steps over the one there.")
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 2, length: 0))
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        editor.textView.deleteBackward(nil)
        XCTAssertEqual(editor.textView.string, "")
    }

    func testTypedMarkerWrapsTheSelection() async throws {
        let editor = try await makeEditor(text: "word", cursor: 0)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        editor.textView.insertText("*", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "*word*")
    }

    func testTheSettingsTurnTheHelpersOff() async throws {
        let editor = try await makeEditor(text: "- item", cursor: 6)
        var configuration = editor.coordinator.configuration
        configuration.editingBehavior.continuesLists = false
        configuration.editingBehavior.pairsBrackets = false
        editor.coordinator.configuration = configuration
        editor.textView.insertText("(", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "- item(")
        editor.textView.insertNewline(nil)
        XCTAssertEqual(editor.textView.string, "- item(\n")
    }

    /// The find bar's replace holds the keyboard; what it writes is no typing.
    func testAChangeMadeWithoutTheKeyboardIsNotPaired() async throws {
        let editor = try await makeEditor(text: "x", cursor: 1)
        editor.window.makeFirstResponder(nil)
        editor.textView.insertText("(", replacementRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(editor.textView.string, "x(")
    }

    // MARK: HUNT-059

    private static let foldedNote = "# One\nhidden one\nhidden two\n# Two\nvisible\n"

    private func foldingEditor(cursor: Int = 0) async throws -> MacMarkdownEditorFixture {
        let editor = try await makeEditor(text: Self.foldedNote, cursor: cursor)
        editor.coordinator.foldTracking.scanIfWaiting()
        return editor
    }

    func testFoldAllHidesTheSectionsAndUnfoldAllShowsThem() async throws {
        let editor = try await foldingEditor()
        let source = Self.foldedNote as NSString
        XCTAssertFalse(isHidden(source.range(of: "hidden one").location, in: editor.textView))
        editor.session.foldAll()
        editor.coordinator.applyFolds(in: editor.textView)
        XCTAssertTrue(isHidden(source.range(of: "hidden one").location, in: editor.textView))
        XCTAssertTrue(isHidden(source.range(of: "visible").location, in: editor.textView))
        XCTAssertFalse(isHidden(source.range(of: "# Two").location, in: editor.textView))
        editor.session.unfoldAll()
        editor.coordinator.applyFolds(in: editor.textView)
        XCTAssertFalse(isHidden(source.range(of: "hidden one").location, in: editor.textView))
    }

    func testAFoldedLineShowsItsChevron() async throws {
        let editor = try await foldingEditor()
        editor.textView.layoutSubtreeIfNeeded()
        editor.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        editor.coordinator.positionFoldButtons(in: editor.textView)
        XCTAssertEqual(editor.coordinator.foldButtons.shownCount, 2)
        XCTAssertEqual(editor.textView.subviews.filter { subview in subview is NSButton }.count, 4, "A chevron and an ellipsis for each.")
    }

    func testCursorStaysOutOfAFoldedSection() async throws {
        let editor = try await foldingEditor()
        editor.session.foldAll()
        editor.coordinator.applyFolds(in: editor.textView)
        let hiddenLocation = (Self.foldedNote as NSString).range(of: "hidden two").location
        editor.textView.setSelectedRange(NSRange(location: hiddenLocation, length: 0))
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 5, length: 0), "The cursor goes to the end of the header line.")
    }

    func testReturnAtTheEndOfAFoldedLineStartsALineAfterTheSection() async throws {
        let editor = try await foldingEditor(cursor: 5)
        editor.session.foldedKeys = [try XCTUnwrap(NoteFolding.regions(in: Self.foldedNote).first?.key)]
        editor.coordinator.applyFolds(in: editor.textView)
        editor.textView.insertNewline(nil)
        XCTAssertEqual(editor.textView.string, "# One\nhidden one\nhidden two\n\n# Two\nvisible\n")
        XCTAssertEqual(editor.session.foldedKeys.count, 1, "The section stays folded.")
    }

    /// HUNT-077: Forward Delete at the end of a folded line.
    func testDeletingIntoAFoldUnfoldsItFirst() async throws {
        let editor = try await foldingEditor(cursor: 5)
        editor.session.foldedKeys = [try XCTUnwrap(NoteFolding.regions(in: Self.foldedNote).first?.key)]
        editor.coordinator.applyFolds(in: editor.textView)
        editor.textView.deleteForward(nil)
        XCTAssertEqual(editor.textView.string, "# Onehidden one\nhidden two\n# Two\nvisible\n")
        XCTAssertEqual(editor.session.foldedKeys, [], "The hidden line came up into view.")
    }

    /// HUNT-069: a folded list item stays folded with the line below it.
    func testMoveLineDownGoesPastAFoldedListItemAndKeepsItFolded() async throws {
        let text = "line\n- item\n    - hidden\nafter\n"
        let editor = try await makeEditor(text: text, cursor: 1)
        editor.coordinator.foldTracking.scanIfWaiting()
        let foldKey = try XCTUnwrap(NoteFolding.regions(in: text).first?.key)
        editor.session.foldedKeys = [foldKey]
        editor.coordinator.applyFolds(in: editor.textView)
        XCTAssertTrue(editor.coordinator.runKeyCommand(.moveLinesDown, in: editor.textView))
        XCTAssertEqual(editor.textView.string, "- item\n    - hidden\nline\nafter\n")
        XCTAssertEqual(editor.session.foldedKeys, [foldKey])
        let source = editor.textView.string as NSString
        XCTAssertTrue(isHidden(source.range(of: "- hidden").location, in: editor.textView))
        XCTAssertFalse(isHidden(source.range(of: "line\n").location, in: editor.textView), "The moved line is in view.")
        XCTAssertEqual(editor.textView.selectedRange().location, source.range(of: "line\n").location + 1)
    }

    /// A line below a folded heading's text belongs to its section, so the section opens
    /// rather than swallow the line.
    func testMoveLineDownPastAFoldedHeadingOpensItsSection() async throws {
        let text = "line\n" + Self.foldedNote
        let editor = try await makeEditor(text: text, cursor: 1)
        editor.coordinator.foldTracking.scanIfWaiting()
        editor.session.foldedKeys = [try XCTUnwrap(NoteFolding.regions(in: text).first?.key)]
        editor.coordinator.applyFolds(in: editor.textView)
        XCTAssertTrue(editor.coordinator.runKeyCommand(.moveLinesDown, in: editor.textView))
        XCTAssertEqual(editor.textView.string, "# One\nhidden one\nhidden two\nline\n# Two\nvisible\n")
        let source = editor.textView.string as NSString
        XCTAssertFalse(isHidden(source.range(of: "line\n").location, in: editor.textView), "The moved line is in view.")
        XCTAssertEqual(editor.textView.selectedRange().location, source.range(of: "line\n").location + 1)
    }

    func testMoveLineUpBelowThePropertiesLeavesThemWhole() async throws {
        let text = "---\ntitle: x\n---\nBody\n"
        let editor = try await makeEditor(text: text, cursor: 18)
        var configuration = editor.coordinator.configuration
        configuration.mode = .livePreview
        editor.coordinator.configuration = configuration
        editor.coordinator.environment = LivePreviewEnvironment(root: try TemporaryVault.make(prefix: "Vault", for: self).root, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                                resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: { _ in })
        editor.coordinator.restyleEverything(in: editor.textView, forcesBlockScan: true)
        _ = editor.coordinator.runKeyCommand(.moveLinesUp, in: editor.textView)
        XCTAssertEqual(editor.textView.string, text)
    }

    /// HUNT-067: the find bar moved to a match in a folded section.
    func testFindOpensTheSectionThatHidesAMatch() async throws {
        let editor = try await foldingEditor()
        editor.session.foldAll()
        editor.coordinator.applyFolds(in: editor.textView)
        let match = (Self.foldedNote as NSString).range(of: "hidden two")
        editor.coordinator.revealFoundText(match, in: editor.textView)
        XCTAssertFalse(isHidden(match.location, in: editor.textView))
        XCTAssertFalse(editor.session.foldedKeys.contains(try XCTUnwrap(NoteFolding.regions(in: Self.foldedNote).first?.key)))
    }

    // MARK: HUNT-060

    func testTheNotesNameShowsAboveTheText() async throws {
        let editor = try await makeEditor(text: "Body")
        let insetWithoutTitle = editor.textView.textContainerInset.height
        editor.textView.inlineTitle = ("Lecture Notes", NSFont.systemFont(ofSize: 28, weight: .semibold), .labelColor)
        let label = try XCTUnwrap(editor.textView.subviews.compactMap { subview in subview as? NSTextField }.first)
        XCTAssertEqual(label.stringValue, "Lecture Notes")
        XCTAssertGreaterThan(label.frame.height, 20)
        XCTAssertGreaterThanOrEqual(editor.textView.textContainerOrigin.y, label.frame.maxY, "The text starts below the title.")
        XCTAssertGreaterThan(editor.textView.textContainerInset.height, insetWithoutTitle)
        editor.textView.inlineTitle = nil
        XCTAssertTrue(editor.textView.subviews.compactMap { subview in subview as? NSTextField }.isEmpty)
        XCTAssertEqual(editor.textView.textContainerInset.height, 32)
    }

    // MARK: Through the real editor: HUNT-060, HUNT-064, HUNT-074

    private var hostWindow: NSWindow?

    private func findTextView(in view: NSView) -> MarkdownMacTextView? {
        if let textView = view as? MarkdownMacTextView { return textView }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) { return textView }
        }
        return nil
    }

    private func showRealEditor(text: String, configuration: EditorConfiguration) async throws -> (MarkdownMacTextView, MarkdownSession, NSHostingView<NativeMarkdownEditor>) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        let host = NSHostingView(rootView: NativeMarkdownEditor(session: session, configuration: configuration, headingScrollRequest: nil, follow: { _, _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        hostWindow = window
        window.contentView = host
        window.showInvisibly()
        addTeardownBlock { @MainActor in
            window.orderOut(nil)
            window.contentView = nil
        }
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            host.layoutSubtreeIfNeeded()
            if let textView = findTextView(in: host) { return (textView, session, host) }
            turnRunLoop(0.01)
        }
        return (try XCTUnwrap(nil as MarkdownMacTextView?, "SwiftUI did not make the editor within 20 s."), session, host)
    }

    /// Turning spell checking off reaches a note already open.
    func testSpellCheckingFollowsTheSettingInAnOpenNote() async throws {
        var configuration = EditorConfiguration()
        configuration.usesSpellChecking = true
        let (textView, session, host) = try await showRealEditor(text: "Teh word", configuration: configuration)
        XCTAssertTrue(textView.isContinuousSpellCheckingEnabled)
        configuration.usesSpellChecking = false
        host.rootView = NativeMarkdownEditor(session: session, configuration: configuration, headingScrollRequest: nil, follow: { _, _ in })
        let deadline = Date.now.addingTimeInterval(5)
        while textView.isContinuousSpellCheckingEnabled, Date.now < deadline { turnRunLoop(0.02) }
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
    }

    func testTheNotesNameReachesTheEditorFromItsConfiguration() async throws {
        var configuration = EditorConfiguration()
        configuration.inlineTitle = "Lecture Notes"
        let (textView, _, _) = try await showRealEditor(text: "Body", configuration: configuration)
        XCTAssertEqual(textView.subviews.compactMap { subview in subview as? NSTextField }.first?.stringValue, "Lecture Notes")
    }

    func testSwitchingModesKeepsTheLineAtTheTop() async throws {
        var text = ""
        for index in 0..<400 { text += "Line number \(index) with **bold** words in it.\n\n" }
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let (textView, session, host) = try await showRealEditor(text: text, configuration: configuration)
        host.layoutSubtreeIfNeeded()
        let coordinator = try XCTUnwrap(textView.delegate as? NativeMarkdownEditor.Coordinator)
        let target = (text as NSString).range(of: "Line number 300").location
        coordinator.scrollToTop(of: target, in: textView)
        turnRunLoop(0.1)
        let lineBefore = try XCTUnwrap(coordinator.topCharacter(of: textView))
        XCTAssertEqual(lineBefore, target)
        configuration.mode = .source
        host.rootView = NativeMarkdownEditor(session: session, configuration: configuration, headingScrollRequest: nil, follow: { _, _ in })
        let deadline = Date.now.addingTimeInterval(5)
        while coordinator.configuration.mode != .source, Date.now < deadline { turnRunLoop(0.02) }
        turnRunLoop(0.2)
        XCTAssertEqual(coordinator.topCharacter(of: textView), target, "Source of another height must not move the view to another passage.")
    }

    // MARK: HUNT-076

    func testAPressThatMovesAwayIsADrag() {
        var events: [(type: NSEvent.EventType, location: CGPoint)] = [(.leftMouseDragged, CGPoint(x: 11, y: 10)), (.leftMouseDragged, CGPoint(x: 20, y: 10)), (.leftMouseUp, CGPoint(x: 20, y: 10))]
        let outcome = MacEditorClickOutcome.following(pressAt: CGPoint(x: 10, y: 10)) { events.isEmpty ? nil : events.removeFirst() }
        XCTAssertEqual(outcome, .dragged)
        XCTAssertEqual(events.count, 1, "It stops reading once it knows.")
    }

    func testAPressReleasedInPlaceIsAClick() {
        var events: [(type: NSEvent.EventType, location: CGPoint)] = [(.leftMouseDragged, CGPoint(x: 11, y: 10)), (.leftMouseUp, CGPoint(x: 11, y: 11))]
        XCTAssertEqual(MacEditorClickOutcome.following(pressAt: CGPoint(x: 10, y: 10)) { events.isEmpty ? nil : events.removeFirst() }, .released)
    }

    func testALinkIsFollowedOnReleaseNotOnPress() async throws {
        let text = "Plain\n\nSee [[Target]] here\n"
        let editor = try await makeEditor(text: text)
        var followed: [String] = []
        editor.coordinator.follow = { target, _ in followed.append(target) }
        editor.window.makeFirstResponder(nil)
        editor.textView.layoutSubtreeIfNeeded()
        let linkLocation = (text as NSString).range(of: "Target").location + 2
        XCTAssertEqual(editor.textView.isClickTarget?(linkLocation), true)
        XCTAssertEqual(editor.textView.isClickTarget?(1), false)
        XCTAssertEqual(followed, [], "Asking whether a click would act does not act.")
        XCTAssertEqual(editor.textView.followLinkOnClick?(linkLocation, []), true)
        XCTAssertEqual(followed, ["Target"])
    }

    // MARK: HUNT-063

    /// Typing with an input method while the note's text changes elsewhere: the composition
    /// must not write the older text over that change.
    func testACompositionDoesNotWriteOverAChangeFromElsewhere() async throws {
        let editor = try await makeEditor(text: "start\nend", cursor: 5)
        editor.textView.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 5, length: 0))
        editor.session.text = "start\nend from another device"
        editor.textView.setMarkedText("かき", selectedRange: NSRange(location: 2, length: 0), replacementRange: editor.textView.markedRange())
        XCTAssertEqual(editor.session.text, "start\nend from another device", "The composition does not reach the session while a change waits.")
        editor.textView.insertText("柿", replacementRange: editor.textView.markedRange())
        XCTAssertEqual(editor.session.text, "start柿\nend from another device")
        XCTAssertEqual(editor.textView.string, "start柿\nend from another device")
    }

    func testAKeyTypedBeforeAChangeArrivesKeepsBoth() async throws {
        let editor = try await makeEditor(text: "start\nend", cursor: 5)
        editor.session.text = "start\nend changed"
        editor.textView.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(editor.session.text, "start!\nend changed")
        XCTAssertEqual(editor.textView.string, "start!\nend changed")
    }

    // MARK: HUNT-048

    func testFormattingCodeUnderAListItemKeepsItsIndentation() async throws {
        let text = "- step\n    ```json\n    {\"a\":1}\n    ```\n\nAfter\n"
        let editor = try await makeEditor(text: text)
        let source = text as NSString
        let codeLocation = source.range(of: "{\"a\"").location
        editor.textView.setSelectedRange(NSRange(location: codeLocation, length: 0))
        turnRunLoop()
        editor.textView.window?.makeFirstResponder(editor.textView)
        editor.coordinator.perform(MarkdownTextEdit(range: NSRange(location: codeLocation + 1, length: 0), replacement: "\"b\":2,",
                                                    selectionAfter: NSRange(location: codeLocation + 2, length: 0)), in: editor.textView)
        turnRunLoop()
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        let deadline = Date.now.addingTimeInterval(3)
        while editor.textView.string.contains("{\"b\":2,\"a\":1}"), Date.now < deadline { turnRunLoop(0.02) }
        let lines = editor.textView.string.components(separatedBy: "\n")
        let fenceIndex = try XCTUnwrap(lines.firstIndex(of: "    ```json"))
        let closingIndex = try XCTUnwrap(lines.firstIndex(of: "    ```"))
        XCTAssertGreaterThan(closingIndex, fenceIndex + 1)
        for line in lines[(fenceIndex + 1)..<closingIndex] {
            XCTAssertTrue(line.hasPrefix("    "), "\(line) left the list item.")
        }
        XCTAssertEqual(lines.last { line in !line.isEmpty }, "After")
    }

    // MARK: HUNT-061

    func testAPastedPageBecomesMarkdown() async throws {
        let editor = try await makeEditor(text: "")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacEditorParityTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("<h2>Title</h2><p>See <a href=\"https://example.com\">this</a></p>", forType: .html)
        pasteboard.setString("Title See this", forType: .string)
        editor.textView.pastingPasteboard = pasteboard
        editor.textView.convertsPastedHTML = true
        editor.textView.paste(nil)
        try await waitUntil("the converted text is in the note", timeoutSeconds: 10) { !editor.textView.string.isEmpty }
        XCTAssertTrue(editor.textView.string.contains("## Title"), editor.textView.string)
        XCTAssertTrue(editor.textView.string.contains("[this](https://example.com)"), editor.textView.string)
    }
}
#endif
