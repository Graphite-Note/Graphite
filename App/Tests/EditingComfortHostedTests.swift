/**
 * File: EditingComfortHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Typing helpers in the hosted workspace's own text view on the iPad, in Live Preview and Source mode: a code
 *              fence that closes itself, and the other papercuts of Docs/Editing-comfort-todo.md.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Typing helpers in the hosted workspace's own text view, typed as the keyboard types:
/// the editor is asked about each character first, which is where they act.
@MainActor
final class EditingComfortHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    // MARK: Code fences

    func testTypingAFenceClosesItBelowInLivePreviewAndSourceMode() async throws {
        for viewMode in [NoteViewMode.livePreview, .source] {
            let (editor, session) = try await openNote("Intro\n\n", viewMode: viewMode)
            try await startEditing(editor, at: (editor.text as NSString).length)
            typeAsKeyboard("```", in: editor)
            try await waitUntil("the closing fence in \(viewMode)") { session.text == "Intro\n\n```\n```" }
            XCTAssertEqual(editor.selectedRange, NSRange(location: 10, length: 0), "The cursor waits after the opening fence in \(viewMode).")
            typeAsKeyboard("python\nprint(1)", in: editor)
            try await waitUntil("the language and code in \(viewMode)") { session.text.hasSuffix("print(1)\n```") }
            XCTAssertEqual(session.text, "Intro\n\n```python\nprint(1)\n```", "The language goes after the opening fence and Return opens the line between.")
            attachScreenshot(named: "A typed fence closed below in \(viewMode)")
        }
    }

    func testUndoTakesTheClosingFenceBackWithTheBacktick() async throws {
        let (editor, session) = try await openNote("Intro\n\n", viewMode: .livePreview)
        try await startEditing(editor, at: (editor.text as NSString).length)
        typeAsKeyboard("``", in: editor)
        try await waitUntil { session.text == "Intro\n\n``" }
        typeAsKeyboard("`", in: editor)
        try await waitUntil { session.text == "Intro\n\n```\n```" }
        editor.undoManager?.undo()
        try await waitUntil("the fence undone") { !session.text.contains("```") }
        XCTAssertFalse(session.text.contains("\n`"), "No closing fence is left behind: \(session.text.debugDescription)")
    }

    func testAFenceTypedAboveAnUnmatchedOneIsTypedAlone() async throws {
        let (editor, session) = try await openNote("``\nlet value = 1\n```\n", viewMode: .livePreview)
        try await startEditing(editor, at: 2)
        typeAsKeyboard("`", in: editor)
        try await waitUntil { session.text == "```\nlet value = 1\n```\n" }
    }

    func testReturnInACalloutsCodeKeepsItsMarkersAndIndentation() async throws {
        let note = "> [!example]\n> ```python\n>     x = 1\n> ```\n"
        let (editor, session) = try await openNote(note, viewMode: .livePreview)
        try await startEditing(editor, at: (note as NSString).range(of: "x = 1").location + 5)
        typeAsKeyboard("\ny = 2", in: editor)
        try await waitUntil { session.text == "> [!example]\n> ```python\n>     x = 1\n>     y = 2\n> ```\n" }
        attachScreenshot(named: "Return in a callout's code block")
    }

    // MARK: Lists

    func testShiftReturnFromAHardwareKeyboardBreaksAnItemsLineWithoutANewItem() async throws {
        let (editor, session) = try await openNote("- item", viewMode: .livePreview)
        try await startEditing(editor, at: 6)
        let shiftReturn = try XCTUnwrap(editor.keyCommands?.first { command in command.input == "\r" && command.modifierFlags == .shift })
        XCTAssertTrue(shiftReturn.wantsPriorityOverSystemBehavior)
        editor.runCommand?(.lineBreakInItem)
        try await waitUntil { session.text == "- item\n  " }
        XCTAssertEqual(editor.selectedRange, NSRange(location: 9, length: 0))
        typeAsKeyboard("more", in: editor)
        try await waitUntil { session.text == "- item\n  more" }
    }

    // MARK: Keyboard

    func testTheKeyboardNeitherCorrectsNorCapitalizesInCode() async throws {
        let note = "Prose here\n\n```c\nint main\n```\n\nUse `printf` here\n"
        let (editor, session) = try await openNote(note, viewMode: .livePreview)
        let source = note as NSString
        func expectKeyboard(inCode: Bool, at location: Int, _ description: String) async throws {
            editor.selectedRange = NSRange(location: location, length: 0)
            editor.delegate?.textViewDidChangeSelection?(editor)
            try await waitUntil(description) {
                editor.autocorrectionType == (inCode ? .no : .default) && editor.autocapitalizationType == (inCode ? .none : .sentences)
            }
        }
        try await startEditing(editor, at: 3)
        try await expectKeyboard(inCode: false, at: 3, "prose corrected")
        try await expectKeyboard(inCode: true, at: source.range(of: "main").location, "a code block left alone")
        try await expectKeyboard(inCode: true, at: source.range(of: "printf").location + 2, "inline code left alone")
        try await expectKeyboard(inCode: false, at: source.range(of: "here\n").location, "prose after inline code corrected")
        // Typing carries the cursor into code: a fence, then Return to the line inside it. The
        // opening fence's own line, where the language is typed, still counts as prose.
        editor.selectedRange = NSRange(location: source.length, length: 0)
        editor.delegate?.textViewDidChangeSelection?(editor)
        typeAsKeyboard("```\n", in: editor)
        try await waitUntil { session.text.hasSuffix("```\n\n```") }
        try await waitUntil("a typed fence left alone") { editor.autocorrectionType == .no }
    }

    // MARK: Helpers

    /// Opens a vault holding the note in `viewMode` and returns its text view.
    private func openNote(_ text: String, viewMode: NoteViewMode) async throws -> (MarkdownTextView, MarkdownSession) {
        window?.isHidden = true
        let directory = try TemporaryVault.make(prefix: "EditingComfort", files: ["Comfort.md": text], for: self).root
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Comfort.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = viewMode
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

    /// Puts the cursor in the note as a tap does.
    private func startEditing(_ editor: MarkdownTextView, at location: Int) async throws {
        editor.beginEditing()
        try await waitUntil { editor.isFirstResponder }
        editor.selectedRange = NSRange(location: location, length: 0)
        editor.delegate?.textViewDidChangeSelection?(editor)
    }

    /// Types as the keyboard does: the editor is asked about each character first.
    private func typeAsKeyboard(_ text: String, in editor: MarkdownTextView) {
        for character in text {
            let typedText = String(character)
            if editor.delegate?.textView?(editor, shouldChangeTextIn: editor.selectedRange, replacementText: typedText) != false {
                editor.insertText(typedText)
            }
        }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
