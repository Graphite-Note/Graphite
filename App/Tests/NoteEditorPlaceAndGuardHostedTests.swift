/**
 * File: NoteEditorPlaceAndGuardHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The iPad's note editor keeps its place through mode, width, fold and appearance changes, and its edits leave properties and folds whole.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 04/11/2026
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

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func openNote(_ text: String) async throws -> (MarkdownTextView, MarkdownSession) {
        let directory = try TemporaryVault.make(prefix: "NoteEditorPlace", for: self).root
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
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
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
    }

    /// Types as the keyboard does: the editor is asked about the text first, which is where the
    /// guards act. `insertText` and `deleteBackward` called from code do not ask.
    private func typeAsKeyboard(_ text: String, in editor: MarkdownTextView) {
        if editor.delegate?.textView?(editor, shouldChangeTextIn: editor.selectedRange, replacementText: text) != false { editor.insertText(text) }
    }

    private func pressBackspace(in editor: MarkdownTextView) {
        let deletedRange = NSRange(location: editor.selectedRange.location - 1, length: 1)
        if editor.delegate?.textView?(editor, shouldChangeTextIn: deletedRange, replacementText: "") != false { editor.deleteBackward() }
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
        try await waitUntil { editor.layoutIfNeeded(); return coordinator.topCharacter(of: editor) == location }
        return location
    }

    // MARK: HUNT-064

    func testSwitchingToSourceAndBackKeepsTheLineAtTheTop() async throws {
        let (editor, session) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        session.viewMode = .source
        try await waitUntil { coordinator.configuration.mode == .source && coordinator.pendingJump == nil && coordinator.topCharacter(of: editor) == top }
        XCTAssertEqual(coordinator.topCharacter(of: editor), top, "In Source")
        session.viewMode = .livePreview
        try await waitUntil { coordinator.configuration.mode == .livePreview && coordinator.pendingJump == nil && coordinator.topCharacter(of: editor) == top }
        XCTAssertEqual(coordinator.topCharacter(of: editor), top, "Back in Live Preview")
    }

    // MARK: HUNT-065

    func testANewWidthKeepsTheLineAtTheTop() async throws {
        let (editor, _) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        window?.frame.size.width = 500
        try await waitUntil { editor.bounds.width < 510 && coordinator.topCharacter(of: editor) == top }
    }

    // MARK: HUNT-066

    func testFoldingAndAChangeOfAppearanceKeepTheLineAtTheTop() async throws {
        let (editor, session) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        let folded = try XCTUnwrap(NoteFolding.regions(in: session.text).first { region in region.headerRange.location > top + 400 })
        coordinator.toggleFold(folded.key, in: editor)
        try await waitUntil { editor.layoutIfNeeded(); return coordinator.topCharacter(of: editor) == top }
        let styleBefore = editor.traitCollection.userInterfaceStyle
        editor.overrideUserInterfaceStyle = styleBefore == .dark ? .light : .dark
        try await waitUntil("the note takes the new appearance") { editor.traitCollection.userInterfaceStyle != styleBefore }
        try await waitUntil("the line is at the top in the new appearance") { coordinator.topCharacter(of: editor) == top }
        XCTAssertEqual(coordinator.topCharacter(of: editor), top, "The first character of the line at the top; the value shows the line it went to.")
    }

    /// A jump keeps its line at the top, but the blocks above can move the text in the turn before
    /// the layout pass that puts it back. The line the offset falls on then is not the place held.
    func testAChangeOfAppearanceWhileAJumpKeepsItsLineHoldsThatLine() async throws {
        let (editor, _) = try await openNote(Self.longNote)
        let top = try await scrollToSection(150, in: editor)
        let coordinator = try coordinator(of: editor)
        let styleBefore = editor.traitCollection.userInterfaceStyle
        editor.setContentOffset(CGPoint(x: editor.contentOffset.x, y: editor.contentOffset.y + 80), animated: false)
        XCTAssertNotEqual(coordinator.topCharacter(of: editor), top, "The text has moved under the top of the view.")
        editor.overrideUserInterfaceStyle = styleBefore == .dark ? .light : .dark
        editor.updateTraitsIfNeeded()
        try await waitUntil("the note takes the new appearance") { editor.traitCollection.userInterfaceStyle != styleBefore }
        try await waitUntil("the line is back at the top") { editor.layoutIfNeeded(); return coordinator.topCharacter(of: editor) == top }
    }

    // MARK: HUNT-062

    func testBackspaceBelowThePropertiesLeavesThemWhole() async throws {
        let text = "---\ntitle: x\n---\nBody\n"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: (text as NSString).range(of: "Body").location)
        pressBackspace(in: editor)
        XCTAssertEqual(editor.text, text)
        XCTAssertEqual(session.text, text)
        XCTAssertEqual(FrontmatterLocator.length(in: session.text as NSString), 17)
    }

    func testTheYAMLStaysEditableOnceItsSourceShows() async throws {
        let text = "---\ntitle: x\n---\nBody\n"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: (text as NSString).range(of: "x\n").location + 1)
        pressBackspace(in: editor)
        try await waitUntil { session.text == "---\ntitle: \n---\nBody\n" }
    }

    // MARK: HUNT-068

    func testTheFirstLetterBelowClosingPropertiesKeepsThem() async throws {
        let text = "---\ntitle: x\n---"
        let (editor, session) = try await openNote(text)
        try await startEditing(editor, at: (text as NSString).length)
        typeAsKeyboard("H", in: editor)
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
        editor.decorate(foundTextRange: try foundRange("hidden word"), document: nil, usingStyle: .highlighted)
        try await waitUntil { !session.foldedKeys.contains(where: { key in key.hasPrefix("h1|# One") }) }

        session.foldedKeys = []
        try await waitUntil { coordinator.appliedFoldedKeys.isEmpty }
        let cellLocation = (session.text as NSString).range(of: "cell").location
        XCTAssertTrue(coordinator.styling.concealedEntries(in: editor).contains { entry in NSLocationInRange(cellLocation, entry.range) })
        editor.decorate(foundTextRange: try foundRange("cell"), document: nil, usingStyle: .highlighted)
        try await waitUntil { !coordinator.styling.concealedEntries(in: editor).contains { entry in NSLocationInRange(cellLocation, entry.range) } }
        editor.clearAllDecoratedFoundText()
        try await waitUntil { coordinator.styling.concealedEntries(in: editor).contains { entry in NSLocationInRange(cellLocation, entry.range) } }
    }

    /// The system's own find navigator reaches the same place.
    func testTheFindNavigatorOpensAFoldItMovesInto() async throws {
        let text = "# One\nhidden word\n# Two\n\nEnd\n"
        let (editor, session) = try await openNote(text)
        let coordinator = try coordinator(of: editor)
        session.foldAll()
        try await waitUntil { coordinator.appliedFoldedKeys == session.foldedKeys }
        let interaction = try XCTUnwrap(editor.findInteraction)
        interaction.presentFindNavigator(showingReplace: false)
        try await waitUntil { interaction.activeFindSession != nil }
        // The search text only fills in the field; the session searches when asked, as the field asks it.
        interaction.searchText = "hidden word"
        interaction.activeFindSession?.performSearch(query: "hidden word", options: nil)
        try await waitUntil { (interaction.activeFindSession?.resultCount ?? 0) > 0 }
        interaction.findNext()
        try await waitUntil { !session.foldedKeys.contains(where: { key in key.hasPrefix("h1|# One") }) }
        interaction.dismissFindNavigator()
    }

    // MARK: HUNT-063

    func testACompositionDoesNotWriteOverAChangeFromElsewhere() async throws {
        let (editor, session) = try await openNote("start\nend\n")
        try await startEditing(editor, at: 5)
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
        session.text = "start\nend from another device\n"
        await Task.yield()
        editor.setMarkedText("かき", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(session.text, "start\nend from another device\n")
        editor.unmarkText()
        editor.delegate?.textViewDidChange?(editor)
        try await waitUntil { session.text == "startかき\nend from another device\n" }
        XCTAssertEqual(session.text, "startかき\nend from another device\n")
        XCTAssertEqual(editor.text, session.text)
    }

    /// A writer that worked from the session's text kept the composition published so far.
    func testAConversionReplacesTheCompositionAWriterKept() async throws {
        let (editor, session) = try await openNote("abc\n")
        try await startEditing(editor, at: 3)
        editor.setMarkedText("かん", selectedRange: NSRange(location: 2, length: 0))
        try await waitUntil { session.text == "abcかん\n" }
        session.text = "abcかん…X\n"
        await Task.yield()
        editor.setMarkedText("感じ", selectedRange: NSRange(location: 2, length: 0))
        editor.unmarkText()
        editor.delegate?.textViewDidChange?(editor)
        try await waitUntil { session.text == "abc感じ…X\n" }
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
