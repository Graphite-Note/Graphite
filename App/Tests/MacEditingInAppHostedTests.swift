/**
 * File: MacEditingInAppHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Frontmatter suggestions, a web frame's lines and typing under pictures, in Graphite's own window
 *              inside the running Mac app, with key and mouse events sent through AppKit as a person's arrive.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The Mac checks of `Docs/Property-and-tag-completion-todo.md` (the frontmatter's keys), `Docs/Iframe-embeds-todo.md`
/// (section 4) and `Docs/Bug-hunt-todo.md` (HUNT-364 and HUNT-365) inside the app, as a hosted test: Graphite's root view
/// in a window of the app, typed into and clicked with events put in the application's queue. Runs only with
/// `TEST_RUNNER_GRAPHITE_MAC_EDITING` given to xcodebuild as a folder, where it writes a picture of each step and notes; a
/// person looks at them.
@MainActor
final class MacEditingInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_EDITING"
    static let releaseVaultVariable = "GRAPHITE_MAC_EDITING_RELEASE_VAULT"
    private var outputFolder: URL?
    private var pictureCount = 0
    private var notes: [String] = []

    private static let vaultNotes: [String: String] = [
        "Amplifier lecture 1.md": "---\ncourse: Analog Circuits\ndue: 2026-11-21\ntags: [eth/analog, exam]\n---\n# Amplifier lecture 1\n",
        "Amplifier lecture 2.md": "---\ncourse: Analog Circuits\ndue: 2026-11-22\ntags: [eth/analog]\n---\n# Amplifier lecture 2\n",
        "Mixed signals.md": "---\ncourse: Mixed Signals\ntags:\n  - eth/mixed\n---\n# Mixed signals\n",
        "Typing here.md": "---\ntitle: Typing here\n---\n# Typing here\nA note to type frontmatter in.\n",
        "Frames.md": "# Frames\n\nThe line above the frame.\n\n<iframe src=\"https://graphite-frame-check.invalid/\" width=\"300\" height=\"160\" "
            + "title=\"Narrow frame\"></iframe>\n\nThe line below the frame.\n",
    ]

    // MARK: Section 2 of the property suggestions: the frontmatter written as text

    func testFrontmatterSuggestionsAnswerTheKeysInSourceMode() async throws {
        guard try start() else { return }
        let (window, workspace) = try await openWindow()
        let session = try await openNote("Typing here.md", in: workspace, mode: .source)
        let textView = try await editor(in: window)
        window.makeFirstResponder(textView)
        let titleLineEnd = (session.text as NSString).range(of: "title: Typing here").upperBound
        textView.setSelectedRange(NSRange(location: titleLineEnd, length: 0))
        try await pressKey("\r", keyCode: 36, in: window)
        try await type("cou", in: window)
        try await waitUntil("a name is suggested", timeoutSeconds: 15) { !session.completion.items.isEmpty }
        try note("names for \"cou\": \(session.completion.items.map(\.title))")
        try writePicture("names suggested", of: window)
        XCTAssertEqual(session.completion.items.first?.title, "course")
        try await pressKey("\r", keyCode: 36, in: window)
        try note("after Return: \(Self.frontmatter(of: session.text))")
        XCTAssertTrue(session.text.contains("course: "), "Return wrote the name")
        try await type("Ana", in: window)
        try await waitUntil("a value is suggested", timeoutSeconds: 15) { session.completion.items.contains { item in item.title == "Analog Circuits" } }
        try note("values for \"Ana\": \(session.completion.items.map(\.title))")
        try writePicture("values suggested", of: window)
        try await pressKey("\t", keyCode: 48, in: window)
        try note("after Tab: \(Self.frontmatter(of: session.text))")
        XCTAssertTrue(session.text.contains("course: Analog Circuits\n"), "Tab wrote the value")
        try await pressKey("\r", keyCode: 36, in: window)
        try await type("tags: [eth", in: window)
        try await waitUntil("a tag is suggested", timeoutSeconds: 15) { session.completion.items.count >= 2 }
        try note("tags for \"eth\": \(session.completion.items.map(\.title))")
        let secondTitle = try XCTUnwrap(session.completion.items.dropFirst().first?.title)
        try await pressArrow(down: true, in: window)
        try writePicture("second tag highlighted", of: window)
        try await pressKey("\r", keyCode: 36, in: window)
        try note("after Down and Return: \(Self.frontmatter(of: session.text))")
        XCTAssertTrue(session.text.contains("tags: [" + secondTitle), "Down then Return wrote the second tag")
        try await type(", ex", in: window)
        try await waitUntil("the second item is suggested", timeoutSeconds: 15) { !session.completion.items.isEmpty }
        try await press(escape: true, in: window)
        try note("after Escape: items \(session.completion.items.map(\.title)), \(Self.frontmatter(of: session.text))")
        XCTAssertTrue(session.completion.items.isEmpty, "Escape closed the suggestions")
        XCTAssertTrue(session.text.contains(", ex"), "Escape left the typing as it was")
        XCTAssertIdentical(window.firstResponder, textView, "Escape did not leave the editor")
        try writePicture("after escape", of: window)
    }

    // MARK: Section 1: the Properties panel

    // MARK: Web frames, section 4

    func testAClickBesideANarrowFrameAndTheArrowsPutTheCursorOnItsLine() async throws {
        guard try start() else { return }
        let (window, workspace) = try await openWindow()
        let session = try await openNote("Frames.md", in: workspace, mode: .livePreview)
        let textView = try await editor(in: window)
        try await settle(window)
        try writePicture("frame", of: window)
        let frameLine = (session.text as NSString).range(of: "<iframe")
        let framePoint = try await windowPoint(ofText: "<iframe", in: textView, session: session)
        // Beside the 300-point frame: well right of it, on its first line's height plus a little.
        let besidePoint = CGPoint(x: framePoint.x + 420, y: framePoint.y - 40)
        let besideView = String(describing: window.contentView?.hitTest(besidePoint)).prefix(120)
        try note("frame's line starts at \(frameLine.location); clicking beside it at \(besidePoint), hit \(besideView)")
        try await click(atWindowPoint: besidePoint, in: window)
        try writePicture("after the click beside", of: window)
        let afterClick = textView.selectedRange()
        try note("selection after the click beside: \(afterClick)")
        let aboveLine = (session.text as NSString).range(of: "The line above the frame.")
        textView.setSelectedRange(NSRange(location: aboveLine.location, length: 0))
        window.makeFirstResponder(textView)
        try await pressArrow(down: true, in: window)
        try await pressArrow(down: true, in: window)
        try writePicture("after two Downs", of: window)
        try note("selection after two Downs from the line above: \(textView.selectedRange())")
        try await pressArrow(down: true, in: window)
        try await pressArrow(down: true, in: window)
        try note("selection after two more Downs: \(textView.selectedRange()), the line below at "
                 + "\((session.text as NSString).range(of: "The line below").location)")
        try writePicture("after four Downs", of: window)
    }

    // MARK: Bug hunt, section 15

    /// HUNT-364 and HUNT-365: keys typed at the end of a heading under two pictures, in a note that opens with a PDF, as
    /// the owner's exercise note: the note stays where it is and every picture and PDF in sight keeps its view.
    func testTypingAtTheEndOfAHeadingUnderPicturesKeepsTheNoteStillAndItsPicturesDrawn() async throws {
        guard try start() else { return }
        let pass = try await ReleaseVaultPass.open(for: self, vault: releaseVaultSource)
        let window = pass.window
        let text = "# Exercise 9\n\n![[Lecture slides.pdf]]\n\n## Gate\n\n![[Sunset over hills.png]]\n\n![[Bar chart.png]]\n\n"
            + "## D-flip-flop\n\nThe answer goes here.\n\n![[Wide banner.png]]\n"
        try Data(text.utf8).write(to: pass.vaultRoot.appendingPathComponent("Exercise shape.md"))
        _ = await pass.workspace.open(try VaultPath("Exercise shape.md"), placement: .currentTab)
        let session = try XCTUnwrap(pass.workspace.markdownSession)
        session.viewMode = .livePreview
        let textView = try await editor(in: window)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let headingEnd = (session.text as NSString).range(of: "D-flip-flop").upperBound
        window.makeKey()
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: headingEnd, length: 0))
        // TextKit estimates the lines it has not laid out, so the first scroll may stop short of the heading: scroll again
        // once they are laid out, until the cursor is in sight.
        for _ in 0..<3 {
            textView.scrollRangeToVisible(NSRange(location: headingEnd, length: 0))
            for _ in 0..<5 { try await settle(window) }
        }
        try writePicture("before typing", of: window)
        var offsets: [CGFloat] = [scrollView.contentView.bounds.minY]
        var blank: [String] = []
        for (index, character) in [" ", "x", " ", "y", "z"].enumerated() {
            try await type(character, in: window)
            offsets.append(scrollView.contentView.bounds.minY)
            let shown = ReleaseVaultViews.renderedBlockViews(in: textView).filter { view in view.frame.intersects(textView.visibleRect) }
            blank += shown.filter { view in view.isHidden || view.alphaValue < 0.01 || view.frame.height < 4 }.map { view in "\(index): \(view.frame)" }
            try writePicture("after key \(index + 1)", of: window)
        }
        try await settle(window)
        try note("offsets while typing: \(offsets), blank views: \(blank), text at the heading: "
                 + "\((session.text as NSString).substring(with: NSRange(location: headingEnd - 11, length: 20)))")
        for offset in offsets { XCTAssertEqual(offset, offsets[0], accuracy: 1, "The note stayed where it was: \(offsets)") }
        XCTAssertTrue(blank.isEmpty, "Every picture in sight kept its view: \(blank)")
        XCTAssertTrue(session.text.contains("D-flip-flop x yz"), "The keys were typed")
    }

    // MARK: Setting up

    private func start() throws -> Bool {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return false }
        let testName = String(String(name.split(separator: " ").last ?? "test").dropLast())
        let folder = URL(fileURLWithPath: outputPath, isDirectory: true).appendingPathComponent(testName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        outputFolder = folder
        return true
    }

    /// The release vault the pass copies: a copy outside the checkout when `GRAPHITE_MAC_EDITING_RELEASE_VAULT` names one,
    /// since the test host reading a checkout on the Desktop waits on the privacy prompt for that folder.
    private var releaseVaultSource: URL {
        guard let path = ProcessInfo.processInfo.environment[Self.releaseVaultVariable] else { return FixtureFolders.releaseVault }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func openWindow() async throws -> (NSWindow, WorkspaceModel) {
        let vaultRoot = try TemporaryVault.make(prefix: "MacEditingInApp", for: self).root
        for (name, text) in Self.vaultNotes { try Data(text.utf8).write(to: vaultRoot.appendingPathComponent(name)) }
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        window.makeKey()
        return (window, workspace)
    }

    private func openNote(_ name: String, in workspace: WorkspaceModel, mode: NoteViewMode) async throws -> MarkdownSession {
        _ = await workspace.open(try VaultPath(name), placement: .currentTab)
        try await waitUntil("the note is open", timeoutSeconds: 20) { workspace.markdownSession != nil }
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = mode
        return session
    }

    private func editor(in window: NSWindow) async throws -> MarkdownMacTextView {
        let root = try XCTUnwrap(window.contentView)
        try await waitUntil("the note's editor is shown", timeoutSeconds: 20) { ReleaseVaultViews.noteTextView(in: root) != nil }
        try await settle(window)
        return try XCTUnwrap(ReleaseVaultViews.noteTextView(in: root))
    }

    /// The middle of the first line of `text` in the editor, in the window's coordinates.
    private func windowPoint(ofText text: String, in textView: MarkdownMacTextView, session: MarkdownSession) async throws -> CGPoint {
        let range = (session.text as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, "no \(text) in the note")
        var actualRange = NSRange()
        let screenRect = textView.firstRect(forCharacterRange: NSRange(location: range.location, length: 1), actualRange: &actualRange)
        let windowRect = textView.window?.convertFromScreen(screenRect) ?? .zero
        return CGPoint(x: windowRect.midX, y: windowRect.midY)
    }

    private static func frontmatter(of text: String) -> String {
        text.components(separatedBy: "\n---").first.map { block in block.replacingOccurrences(of: "\n", with: " / ") } ?? text
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 20).measure({}, until: { true })
    }

    // MARK: Events

    private func click(atWindowPoint windowPoint: CGPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { NSApp.postEvent(try mouseEvent(type, at: windowPoint, in: window), atStart: false) }
        try await settle(window)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .mouseMoved ? 0 : 1))
    }

    private func type(_ text: String, in window: NSWindow) async throws {
        for character in text {
            try postKey(String(character), keyCode: 0, in: window)
            try await settle(window)
        }
    }

    private func pressKey(_ characters: String, keyCode: UInt16, in window: NSWindow) async throws {
        try postKey(characters, keyCode: keyCode, in: window)
        try await settle(window)
    }

    private func pressArrow(down: Bool, in window: NSWindow) async throws {
        let scalar = UnicodeScalar(down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey).map(String.init) ?? ""
        try postKey(scalar, keyCode: down ? 125 : 126, modifiers: [.numericPad, .function], in: window)
        try await settle(window)
    }

    private func press(escape: Bool, in window: NSWindow) async throws {
        try postKey(String(UnicodeScalar(UInt8(27))), keyCode: 53, in: window)
        try await settle(window)
    }

    private func postKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let timestamp = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: timestamp,
                                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)), atStart: false)
        }
    }

    // MARK: Output

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    private func writePicture(_ name: String, of window: NSWindow) throws {
        let pngData = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        pictureCount += 1
        try pngData.write(to: try XCTUnwrap(outputFolder).appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
    }
}
#endif
