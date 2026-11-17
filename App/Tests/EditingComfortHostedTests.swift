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
import UniformTypeIdentifiers
@testable import GraphiteUI

/// Typing helpers in the hosted workspace's own text view, typed as the keyboard types:
/// the editor is asked about each character first, which is where they act.
@MainActor
final class EditingComfortHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        closeWindow()
    }

    /// Ends editing first, so no hidden editor keeps the keyboard for the tests that follow.
    private func closeWindow() {
        window?.endEditing(true)
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

    /// #201: with the cursor in a callout, its code lines' `>` markers are the callout's bars,
    /// as its text lines' are, and the code's background starts after them.
    func testACalloutsCodeLinesStayInsideItsBarsWhileTheCursorIsInIt() async throws {
        let note = "Before\n\n> [!example] Title\n> Some text\n> ```python\n> x = 1\n>     y = 2\n> ```\n> After code\n\nOutside\n"
        let (editor, _) = try await openNote(note, viewMode: .livePreview)
        let source = note as NSString
        try await startEditing(editor, at: source.range(of: "x = 1").location + 2)
        func replacement(at location: Int) -> String? {
            editor.textStorage.attribute(ConcealedReplacement.attributeKey, at: location, effectiveRange: nil) as? String
        }
        func hasBackground(at location: Int) -> Bool { editor.textStorage.attribute(.backgroundColor, at: location, effectiveRange: nil) != nil }
        try await waitUntil("the callout's source shows") { replacement(at: source.range(of: "> Some").location) == ConcealedReplacement.quoteBar.rawValue }
        for codeLine in ["> x = 1", ">     y = 2"] {
            let marker = source.range(of: codeLine).location
            try await waitUntil("the bar of \(codeLine)") { replacement(at: marker) == ConcealedReplacement.quoteBar.rawValue }
            XCTAssertFalse(hasBackground(at: marker), "The marker of \(codeLine) is not code.")
            XCTAssertTrue(hasBackground(at: marker + 2), "The code of \(codeLine) keeps its background.")
        }
        attachScreenshot(named: "A callout's code inside its bars")
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

    // MARK: Hand checks of #200, done by the editor's own controls

    /// Each formatting button of the keyboard bar, pressed through its own action over a
    /// selected word, makes its edit, and Undo takes it back.
    func testEveryFormattingButtonOfTheKeyboardBarEditsTheSelectionAndUndoes() async throws {
        let (editor, session) = try await openNote("one word\nnext", viewMode: .livePreview)
        try await startEditing(editor, at: 0)
        let toolbar = try XCTUnwrap(editor.inputAccessoryView as? EditorKeyboardToolbar, "The keyboard bar is the editor's accessory view.")
        let buttons = descendants(of: toolbar, matching: UIButton.self)
        let expectations: [(label: String, text: String)] = [
            ("Bold", "one **word**\nnext"), ("Italic", "one *word*\nnext"), ("Strikethrough", "one ~~word~~\nnext"),
            ("Highlight", "one ==word==\nnext"), ("Code", "one `word`\nnext"), ("Inline math", "one $word$\nnext"),
            ("Link to note", "one [[word]]\nnext"), ("Tag", "one #word\nnext"), ("Bulleted list", "- one word\nnext"),
            ("Numbered list", "1. one word\nnext"), ("Task", "- [ ] one word\nnext"), ("Indent", "\tone word\nnext"),
            ("Move line down", "next\none word"),
        ]
        for (label, expectedText) in expectations {
            let button = try XCTUnwrap(buttons.first { button in button.accessibilityLabel == label }, "The bar has \(label).")
            editor.selectedRange = (editor.text as NSString).range(of: "word")
            editor.delegate?.textViewDidChangeSelection?(editor)
            button.sendActions(for: .touchUpInside)
            try await waitUntil("\(label) edits the note") { session.text == expectedText }
            editor.undoManager?.undo()
            try await waitUntil("Undo takes \(label) back") { session.text == "one word\nnext" }
        }
        attachScreenshot(named: "The keyboard bar's formatting buttons")
    }

    /// A web address pasted over selected text makes a link of it, and rich text is pasted
    /// as Markdown, as with Obsidian's "Auto convert HTML".
    func testPastingAnAddressOverASelectionLinksItAndRichTextBecomesMarkdown() async throws {
        let (editor, session) = try await openNote("Read the guide here.\n", viewMode: .livePreview)
        try await startEditing(editor, at: 0)
        // The simulator's pasteboard is only written: reading what another app left there can
        // ask for permission to paste.
        UIPasteboard.general.string = "https://help.obsidian.md"
        editor.selectedRange = (editor.text as NSString).range(of: "guide")
        editor.paste(nil)
        try await waitUntil("the link") { session.text == "Read the [guide](https://help.obsidian.md) here.\n" }
        UIPasteboard.general.setItems([[UTType.html.identifier: "<p><b>Bold</b> and <a href=\"https://example.org\">a link</a></p>",
                                        UTType.utf8PlainText.identifier: "Bold and a link"]])
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        editor.paste(nil)
        try await waitUntil("the Markdown") { session.text.contains("**Bold** and [a link](https://example.org)") }
    }

    /// The cursor stays where the typing is after a block it passed renders: a math block
    /// typed key by key, then Return twice to leave it, puts the cursor below the formula.
    func testTheCursorStaysBelowAMathBlockThatRendersAsItIsLeft() async throws {
        let (editor, session) = try await openNote("Intro\n", viewMode: .livePreview)
        try await startEditing(editor, at: 6)
        typeAsKeyboard("$$\nx^2 + y^2\n$$\n\nAfter", in: editor)
        try await waitUntil { session.text == "Intro\n$$\nx^2 + y^2\n$$\n\nAfter" }
        XCTAssertEqual(editor.selectedRange, NSRange(location: (session.text as NSString).length, length: 0))
        editor.layoutIfNeeded()
        let caret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        let introRect = editor.caretRect(for: try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: 5)))
        XCTAssertGreaterThan(caret.minY, introRect.maxY + 20, "The cursor is below the rendered formula, not on top of it.")
        XCTAssertTrue(caret.minY.isFinite && caret.height > 4, "The cursor has a line's height: \(caret)")
        attachScreenshot(named: "The cursor after a math block")
    }

    /// A selection across a rendered table has its ends, where the handles go, at the
    /// selected text before and after the table, each a line high.
    func testASelectionAcrossARenderedTableHasItsEndsAtTheText() async throws {
        let note = "Above the table\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\nBelow the table\n"
        let (editor, _) = try await openNote(note, viewMode: .livePreview)
        let source = note as NSString
        try await startEditing(editor, at: source.range(of: "Below").location)
        let selection = NSUnionRange(source.range(of: "table\n"), source.range(of: "Below"))
        editor.selectedRange = selection
        editor.delegate?.textViewDidChangeSelection?(editor)
        editor.layoutIfNeeded()
        let selectedRange = try XCTUnwrap(editor.selectedTextRange)
        let rects = editor.selectionRects(for: selectedRange)
        let start = try XCTUnwrap(rects.first { rect in rect.containsStart }).rect
        let end = try XCTUnwrap(rects.first { rect in rect.containsEnd }).rect
        let aboveLine = editor.caretRect(for: try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: selection.location)))
        let belowLine = editor.caretRect(for: try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: NSMaxRange(selection))))
        XCTAssertEqual(start.midY, aboveLine.midY, accuracy: aboveLine.height, "The start handle is on the line above the table.")
        XCTAssertEqual(end.midY, belowLine.midY, accuracy: belowLine.height, "The end handle is on the line below the table.")
        XCTAssertGreaterThan(end.minY, start.maxY, "The table lies between the two handles.")
        attachScreenshot(named: "A selection across a table")
    }

    // MARK: Helpers

    /// Opens a vault holding the note in `viewMode` and returns its text view.
    private func openNote(_ text: String, viewMode: NoteViewMode) async throws -> (MarkdownTextView, MarkdownSession) {
        closeWindow()
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
