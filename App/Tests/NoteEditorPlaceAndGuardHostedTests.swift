/**
 * File: NoteEditorPlaceAndGuardHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The iPad's note editor keeps its place through mode, width, fold and appearance changes, and its edits leave properties and folds whole.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class NoteEditorPlaceAndGuardHostedTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) } // Best-effort removal of a temporary folder.
        vaultDirectory = nil
    }

    private func openNote(_ text: String) async throws -> (MarkdownTextView, MarkdownSession) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NoteEditorPlace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(text.utf8).write(to: directory.appendingPathComponent("Note.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Note.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil { self.editors(in: controller).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        let editor = try XCTUnwrap(editors(in: controller).first { editor in editor.text == session.text })
        editor.layoutIfNeeded()
        return (editor, session)
    }

    private func editors(in controller: UIViewController) -> [MarkdownTextView] {
        descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func coordinator(of editor: MarkdownTextView) throws -> NativeMarkdownEditor.Coordinator {
        try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
    }

    private func startEditing(_ editor: MarkdownTextView, at location: Int) async throws {
        editor.beginEditing()
        try await waitUntil { editor.isFirstResponder }
        editor.selectedRange = NSRange(location: location, length: 0)
        editor.delegate?.textViewDidChangeSelection?(editor)
        try await Task.sleep(for: .milliseconds(80))
    }

    /// A long note whose paragraphs wrap, so a new width moves everything, with tables that
    /// change height with the mode.
    private static let longNote: String = {
        var text = ""
        for index in 0..<220 {
            text += "## Section \(index)\n\nParagraph \(index) with enough words in it to wrap over several lines at any width the note is shown at, and then some more of them.\n\n"
            if index % 20 == 0 { text += "| A | B |\n| --- | --- |\n| \(index) | two |\n\n" }
        }
        return text
    }()

    /// Scrolls the line of "Section `number`" to the top and returns the character there.
    private func scrollToSection(_ number: Int, in editor: MarkdownTextView) async throws -> Int {
        let coordinator = try coordinator(of: editor)
        let location = (editor.text as NSString).range(of: "## Section \(number)\n").location
        coordinator.scrollToTop(of: location, in: editor)
        try await Task.sleep(for: .milliseconds(400))
        editor.layoutIfNeeded()
        return try XCTUnwrap(coordinator.topCharacter(of: editor))
    }

    // MARK: HUNT-064

    func testSwitchingToSourceAndBackKeepsTheLineAtTheTop() async throws {
        let (editor, session) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        session.viewMode = .source
        try await waitUntil { coordinator.configuration.mode == .source }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(coordinator.topCharacter(of: editor), top)
        session.viewMode = .livePreview
        try await waitUntil { coordinator.configuration.mode == .livePreview }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(coordinator.topCharacter(of: editor), top)
    }

    // MARK: HUNT-065

    func testANewWidthKeepsTheLineAtTheTop() async throws {
        let (editor, _) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        window?.frame.size.width = 500
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertLessThan(editor.bounds.width, 510)
        XCTAssertEqual(coordinator.topCharacter(of: editor), top)
    }

    // MARK: HUNT-066

    func testFoldingAndAChangeOfAppearanceKeepTheLineAtTheTop() async throws {
        let (editor, session) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        let folded = try XCTUnwrap(NoteFolding.regions(in: session.text).first { region in region.headerRange.location > top + 400 })
        coordinator.toggleFold(folded.key, in: editor)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(coordinator.topCharacter(of: editor), top)
        editor.overrideUserInterfaceStyle = editor.traitCollection.userInterfaceStyle == .dark ? .light : .dark
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(coordinator.topCharacter(of: editor), top)
    }

    // MARK: HUNT-062

    func testBackspaceBelowThePropertiesLeavesThemWhole() async throws {
        let text = "---\ntitle: x\n---\nBody\n"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: (text as NSString).range(of: "Body").location)
        editor.deleteBackward()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.text, text)
        XCTAssertEqual(FrontmatterLocator.length(in: session.text as NSString), 17)
    }

    func testTheYAMLStaysEditableOnceItsSourceShows() async throws {
        let text = "---\ntitle: x\n---\nBody\n"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: (text as NSString).range(of: "x\n").location + 1)
        editor.deleteBackward()
        try await waitUntil { session.text == "---\ntitle: \n---\nBody\n" }
    }

    // MARK: HUNT-068

    func testTheFirstLetterBelowClosingPropertiesKeepsThem() async throws {
        let text = "---\ntitle: x\n---"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: (text as NSString).length)
        editor.insertText("H")
        try await waitUntil { session.text == "---\ntitle: x\n---\nH" }
        XCTAssertEqual(FrontmatterLocator.length(in: session.text as NSString), 17)
    }

    // MARK: HUNT-069

    func testMoveLineDownGoesPastAFoldedSection() async throws {
        let text = "line\n- item\n    - hidden\nafter\n"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: 1)
        let key = try XCTUnwrap(NoteFolding.regions(in: text).first?.key)
        session.foldedKeys = [key]
        try await waitUntil { (try? self.coordinator(of: editor).appliedFoldedKeys) == [key] }
        editor.runCommand?(.moveLinesDown)
        try await waitUntil { session.text == "- item\n    - hidden\nline\nafter\n" }
        XCTAssertEqual(session.foldedKeys, [key], "The section stays folded.")
        XCTAssertEqual(editor.selectedRange.location, (session.text as NSString).range(of: "line\n").location + 1, "The moved line stays in view with the cursor.")
    }

    // MARK: HUNT-077

    func testForwardDeleteAtTheEndOfAFoldedLineUnfoldsFirst() async throws {
        let text = "# One\nhidden\n# Two\nvisible\n"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: 5)
        let key = try XCTUnwrap(NoteFolding.regions(in: text).first?.key)
        session.foldedKeys = [key]
        try await waitUntil { (try? self.coordinator(of: editor).appliedFoldedKeys) == [key] }
        XCTAssertEqual(editor.delegate?.textView?(editor, shouldChangeTextIn: NSRange(location: 5, length: 1), replacementText: ""), true)
        XCTAssertEqual(session.foldedKeys, [], "The hidden line comes up in view.")
    }

    // MARK: HUNT-067

    func testFindOpensAFoldAndShowsABlocksSource() async throws {
        let text = "# One\nhidden word\n# Two\n\n| A | B |\n| --- | --- |\n| cell | two |\n\nEnd\n"
        let (editor, session) = try await openNote(text)
        let coordinator = try coordinator(of: editor)
        session.foldAll()
        try await waitUntil { coordinator.appliedFoldedKeys == session.foldedKeys }
        func foundRange(_ words: String) throws -> UITextRange {
            let range = (session.text as NSString).range(of: words)
            let start = try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: range.location))
            let end = try XCTUnwrap(editor.position(from: start, offset: range.length))
            return try XCTUnwrap(editor.textRange(from: start, to: end))
        }
        editor.decorate(foundTextRange: try foundRange("hidden word"), in: nil, usingStyle: .highlighted)
        try await waitUntil { !session.foldedKeys.contains(where: { key in key.hasPrefix("h1|# One") }) }

        session.foldedKeys = []
        try await waitUntil { coordinator.appliedFoldedKeys.isEmpty }
        let cellLocation = (session.text as NSString).range(of: "cell").location
        XCTAssertTrue(coordinator.styling.concealedEntries(in: editor).contains { entry in NSLocationInRange(cellLocation, entry.range) })
        editor.decorate(foundTextRange: try foundRange("cell"), in: nil, usingStyle: .highlighted)
        try await waitUntil { !coordinator.styling.concealedEntries(in: editor).contains { entry in NSLocationInRange(cellLocation, entry.range) } }
        editor.clearAllDecoratedFoundText()
        try await waitUntil { coordinator.styling.concealedEntries(in: editor).contains { entry in NSLocationInRange(cellLocation, entry.range) } }
    }

    // MARK: HUNT-063

    func testACompositionDoesNotWriteOverAChangeFromElsewhere() async throws {
        let (editor, session) = try await openNote("start\nend\n")
        try await startEditing(editor, at: 5)
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        session.text = "start\nend from another device\n"
        try await Task.sleep(for: .milliseconds(100))
        editor.setMarkedText("かき", selectedRange: NSRange(location: 2, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.text, "start\nend from another device\n")
        editor.unmarkText()
        editor.delegate?.textViewDidChange?(editor)
        try await waitUntil { session.text == "startかき\nend from another device\n" }
        XCTAssertEqual(editor.text, session.text)
    }

    // MARK: HUNT-057

    func testABlockFromAMenuPutsTheCursorInsideIt() async throws {
        let (editor, session) = try await openNote("Text\n")
        session.selection = NSRange(location: 4, length: 0)
        session.insertBlockFromMenu(EditorContextMenuContent.mathBlock)
        try await waitUntil { editor.isFirstResponder && session.text.contains("$$\n\n$$") }
        let insideBlock = (session.text as NSString).range(of: "$$\n\n").location + 3
        XCTAssertEqual(editor.selectedRange, NSRange(location: insideBlock, length: 0))
        editor.insertText("x")
        try await waitUntil { session.text.contains("$$\nx\n$$") }
    }

    // MARK: HUNT-075

    func testTheAttachMenuOffersNewNotebook() async throws {
        let (editor, _) = try await openNote("Text\n")
        let toolbar = try XCTUnwrap(editor.inputAccessoryView)
        let attach = try XCTUnwrap(descendants(of: toolbar, matching: UIButton.self).first { button in button.menu?.title == "Attach" })
        XCTAssertTrue(attach.menu?.children.contains { element in element.title == "New Notebook" } == true)
    }
}
#endif
