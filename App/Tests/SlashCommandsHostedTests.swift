/**
 * File: SlashCommandsHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The slash commands in the hosted workspace's own text view on the iPad: typed as the keyboard types,
 *              chosen with Return, the arrow keys and a tap, closed with Escape and a space, and undone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The slash commands of Docs/Slash-menu-and-block-handles-todo.md, section 1, in the note's
/// own text view: characters go through the editor as the keyboard sends them, the hardware
/// keyboard's arrows and Escape are the text view's own key commands, and a row is chosen
/// through its accessibility action, the path a tap on a SwiftUI row takes that a test can drive.
@MainActor
final class SlashCommandsHostedTests: XCTestCase {
    private var window: UIWindow?
    private var controller: UIViewController?
    /// Puts the device's core plugin switches back after each test.
    private var restorePluginSwitches: (() -> Void)?

    override func tearDown() async throws {
        closeWindow()
        restorePluginSwitches?()
        restorePluginSwitches = nil
    }

    private func closeWindow() {
        window?.endEditing(true)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        controller = nil
    }

    func testSlashTabThenReturnInsertsATableAndOneUndoTakesItBack() async throws {
        let (editor, session) = try await openNote("Intro\n\n")
        try await startEditing(editor, at: (editor.text as NSString).length)
        typeAsKeyboard("/tab", in: editor)
        try await waitUntil("the slash commands show Table first") { session.completion.isVisible && session.completion.items.first?.title == "Table" }
        guard case .slashCommand(let query) = session.completion.context else { return XCTFail("A slash command is being typed.") }
        XCTAssertEqual(query.text, "tab")
        attachScreenshot(named: "The slash commands after /tab")
        typeAsKeyboard("\n", in: editor)
        try await waitUntil("the table is inserted") { session.text.contains(EditorContextMenuContent.tableBlock) }
        let tableInserted = MarkdownSession.menuBlockEdit(EditorContextMenuContent.tableBlock, in: "Intro\n\n", after: 7)
        XCTAssertEqual(session.text, "Intro\n\n" + tableInserted.replacement, "The /tab is taken out and the table takes its line.")
        XCTAssertEqual(editor.selectedRange, tableInserted.selectionAfter, "The cursor goes to the table's first cell.")
        XCTAssertFalse(session.completion.isVisible)
        attachScreenshot(named: "The table inserted from /tab")
        editor.undoManager?.undo()
        try await waitUntil("the table is undone") { !session.text.contains("| Column |") }
        XCTAssertEqual(session.text, "Intro\n\n/tab", "One undo takes the table back and gives the typed /tab back.")
    }

    func testTheDownArrowAndReturnChooseTheSecondEntry() async throws {
        let (editor, session) = try await openNote("")
        try await startEditing(editor, at: 0)
        typeAsKeyboard("/list", in: editor)
        try await waitUntil("the lists are listed") { session.completion.items.prefix(2).map(\.title) == ["Bulleted List", "Numbered List"] }
        try pressKey(UIKeyCommand.inputDownArrow, in: editor)
        XCTAssertEqual(session.completion.selectedIndex, 1)
        typeAsKeyboard("\n", in: editor)
        try await waitUntil("a numbered list starts") { session.text == "1. " }
    }

    func testAChosenRowSetsTheLineAsAHeading() async throws {
        let (editor, session) = try await openNote("Intro\n\n")
        try await startEditing(editor, at: (editor.text as NSString).length)
        typeAsKeyboard("/head", in: editor)
        try await waitUntil("the headings are listed") { session.completion.items.first?.title == "Heading 1" }
        let row = try await accessibilityElement(labelled: "Heading 2")
        XCTAssertTrue(row.accessibilityActivate(), "The row is chosen as a tap chooses it.")
        try await waitUntil("the line is a heading") { session.text == "Intro\n\n## " }
        XCTAssertEqual(editor.selectedRange, NSRange(location: 10, length: 0), "The cursor waits after the marks.")
    }

    func testEscapeAndASpaceCloseTheListAndReturnThenStartsALine() async throws {
        let (editor, session) = try await openNote("")
        try await startEditing(editor, at: 0)
        typeAsKeyboard("/ta", in: editor)
        try await waitUntil("the slash commands show") { session.completion.isVisible }
        try pressKey(UIKeyCommand.inputEscape, in: editor)
        XCTAssertFalse(session.completion.isVisible, "Escape closes the list.")
        typeAsKeyboard("b", in: editor)
        try await waitUntil("typing opens it again, as in Obsidian") { session.completion.isVisible }
        typeAsKeyboard(" ", in: editor)
        try await waitUntil("a space closes it") { !session.completion.isVisible && session.completion.context == nil }
        typeAsKeyboard("\n", in: editor)
        try await waitUntil { session.text == "/tab \n" }
    }

    func testPlacingTheCursorAfterAWrittenSlashOpensNothing() async throws {
        let (editor, session) = try await openNote("See /path here")
        try await startEditing(editor, at: 9)
        // The editor decides at the selection change itself, before it returns.
        XCTAssertNil(session.completion.context, "Only typing opens the slash commands.")
    }

    func testTurnedOffASlashIsJustTyped() async throws {
        let (editor, session) = try await openNote("", turnsSlashCommandsOff: true)
        try await startEditing(editor, at: 0)
        typeAsKeyboard("/tab", in: editor)
        // Each character is decided as it is typed.
        XCTAssertNil(session.completion.context)
        typeAsKeyboard("\n", in: editor)
        try await waitUntil { session.text == "/tab\n" }
    }

    func testThePalettesCommandsFollowTheBlocks() async throws {
        var ranCommand = false
        let paletteCommands = WindowPaletteCommands()
        paletteCommands.offer { [PaletteCommand(id: "toggle-reading", title: "Toggle reading view", systemImage: "book") { ranCommand = true }] }
        let (editor, session) = try await openNote("", paletteCommands: paletteCommands)
        try await startEditing(editor, at: 0)
        typeAsKeyboard("/read", in: editor)
        try await waitUntil("the command is listed") { session.completion.items.first?.title == "Toggle reading view" }
        typeAsKeyboard("\n", in: editor)
        try await waitUntil("the command runs") { ranCommand }
        XCTAssertEqual(session.text, "", "Its /read is taken out.")
    }

    // MARK: Helpers

    private func openNote(_ text: String, turnsSlashCommandsOff: Bool = false,
                          paletteCommands: WindowPaletteCommands? = nil) async throws -> (MarkdownTextView, MarkdownSession) {
        closeWindow()
        let directory = try TemporaryVault.make(prefix: "SlashCommands", files: ["Slash.md": text], for: self).root
        let workspace = WorkspaceModel()
        if restorePluginSwitches == nil {
            restorePluginSwitches = HostedDevicePreferences.saving([CorePluginSwitches.turnedOffKey, CorePluginSwitches.turnedOnKey])
        }
        workspace.preferences.setEnabled(.slashCommands, !turnsSlashCommandsOff)
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Slash.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
                .environment(\.windowPaletteCommands, paletteCommands)
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        self.controller = controller
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

    /// Runs the text view's key command for a hardware key, as the keyboard does.
    private func pressKey(_ input: String, in editor: MarkdownTextView) throws {
        let command = try XCTUnwrap(editor.keyCommands?.first { command in command.input == input && command.modifierFlags.isEmpty },
                                    "The text view answers \(input) while the list shows.")
        let action = try XCTUnwrap(command.action)
        editor.perform(action, with: command)
    }

    private func accessibilityElement(labelled label: String) async throws -> NSObject {
        let controller = try XCTUnwrap(controller)
        try PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(true)
        defer { try? PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(false) } // Left on, it slows later tests.
        var found: NSObject?
        try await waitUntil("the row \(label)") {
            found = PencilBarPlacementHostedTests.accessibilityElements(in: controller.view).first { element in
                element.accessibilityLabel?.hasPrefix(label) == true
            }
            return found != nil
        }
        return try XCTUnwrap(found)
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
