/**
 * File: UiEditorMacCalloutTableEditingTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: In the Mac's Live Preview, a table in a callout's body is edited in place as a table of its own: its
 *              cells, its "+" strips and its cell menu change the note's source with every line's quote markers kept,
 *              each as one undoable edit, and the callout's view stays across the edits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiEditorMacCalloutTableEditingTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    private static let calloutNote = "Intro line\n\n> [!note] Rates\n> Before the table.\n>\n> | Year | Rate |\n> | --- | --- |\n> | 2024 | 2.0 |\n"
        + "> | 2025 | 1.8 |\n\nAfter the callout\n"

    private func makeEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, MarkdownSession) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 32, height: 32)
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        window.showInvisibly()
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        textView.frame.size.width = 700
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView, session)
    }

    private func calloutView(in textView: NSTextView) -> RenderedBlockHostingView? {
        textView.subviews.lazy.compactMap { subview in subview as? RenderedBlockHostingView }.first
    }

    private func awaitConditionAfterLayout(_ description: String, timeoutSeconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        try await waitUntil(description, timeoutSeconds: timeoutSeconds) {
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            return condition()
        }
    }

    /// The block's menu at points down the callout's view, from its top, in the view's own coordinates.
    private func menus(downThe view: RenderedBlockHostingView) -> [(point: CGPoint, menu: NSMenu)] {
        stride(from: 4.0, to: view.bounds.height, by: 6).compactMap { distanceFromTop in
            let point = CGPoint(x: 60, y: view.isFlipped ? distanceFromTop : view.bounds.height - distanceFromTop)
            return view.blockMenu.map { blockMenu in (point, blockMenu.makeMenu(at: point, isFlipped: view.isFlipped, height: view.bounds.height)) }
        }
    }

    /// Every line of the callout in `note` still has its `> `, and its header is as written.
    private func assertCalloutKeepsItsMarkers(_ note: String, file: StaticString = #filePath, line: UInt = #line) {
        let lines = note.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(of: "> [!note] Rates"), let afterIndex = lines.firstIndex(of: "After the callout") else {
            return XCTFail("The callout's header and the text after it are kept: \(note)", file: file, line: line)
        }
        for calloutLine in lines[headerIndex..<(afterIndex - 1)] {
            XCTAssertTrue(calloutLine.hasPrefix(">"), "\(calloutLine) keeps its marker", file: file, line: line)
        }
    }

    /// The right-click menu on the callout's table is the table's cell menu, elsewhere in the
    /// callout only Edit Source; Add row below and Add column to the right change the note's
    /// source with the markers kept, each one undoable edit.
    func testTheCalloutTablesMenuAddsARowAndAColumnWithTheMarkersKept() async throws {
        let (coordinator, textView, _) = try await makeEditor(text: Self.calloutNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The callout is drawn") { self.calloutView(in: textView) != nil }
        let view = try XCTUnwrap(calloutView(in: textView))
        var tableMenu: NSMenu?
        try await awaitConditionAfterLayout("The callout's table is laid out") {
            tableMenu = self.menus(downThe: view).first { _, menu in menu.items.first?.title == "Row" }?.menu
            return tableMenu != nil
        }
        let firstMenu = try XCTUnwrap(menus(downThe: view).first?.menu)
        XCTAssertEqual(firstMenu.items.map(\.title), ["Edit Source"], "The callout's title has no table commands.")
        let menu = try XCTUnwrap(tableMenu)
        XCTAssertEqual(menu.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)", "", "Edit Source"])

        let rowMenu = try XCTUnwrap(menu.items[0].submenu)
        rowMenu.performActionForItem(at: try XCTUnwrap(rowMenu.items.firstIndex { item in item.title == "Add row below" }))
        let withRow = textView.string
        XCTAssertEqual(withRow.components(separatedBy: "\n").count, Self.calloutNote.components(separatedBy: "\n").count + 1)
        XCTAssertTrue(withRow.contains("\n> |  |  |\n"), withRow)
        assertCalloutKeepsItsMarkers(withRow)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, Self.calloutNote, "Adding the row is one edit.")

        try await awaitConditionAfterLayout("The callout's table is laid out again") {
            tableMenu = self.calloutView(in: textView).flatMap { view in self.menus(downThe: view).first { _, menu in menu.items.first?.title == "Row" }?.menu }
            return tableMenu != nil
        }
        let columnMenu = try XCTUnwrap(tableMenu?.items[1].submenu)
        columnMenu.performActionForItem(at: try XCTUnwrap(columnMenu.items.firstIndex { item in item.title == "Add column to the right" }))
        XCTAssertTrue(textView.string.contains("> | --- | --- | --- |\n"), textView.string)
        assertCalloutKeepsItsMarkers(textView.string)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, Self.calloutNote, "Adding the column is one edit.")
    }

    private static let listItemCalloutNote = "Intro line\n\n> [!note] Steps\n> - First step\n>   | Year | Rate |\n>   | --- | --- |\n"
        + ">   | 2024 | 2.0 |\n> - Second step\n\nAfter the callout\n"

    /// A table in a list item of a callout is edited in place too: its right-click menu is the
    /// cell menu, and a row it adds keeps the quote marker and the item's indentation.
    func testATableInAListItemOfACalloutHasTheCellMenuAndKeepsTheItemsIndentation() async throws {
        let (coordinator, textView, _) = try await makeEditor(text: Self.listItemCalloutNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The callout is drawn") { self.calloutView(in: textView) != nil }
        let view = try XCTUnwrap(calloutView(in: textView))
        var tableMenu: NSMenu?
        try await awaitConditionAfterLayout("The list item's table is laid out as a table that edits") {
            tableMenu = self.menus(downThe: view).first { _, menu in menu.items.first?.title == "Row" }?.menu
            return tableMenu != nil
        }
        let rowMenu = try XCTUnwrap(tableMenu?.items[0].submenu)
        rowMenu.performActionForItem(at: try XCTUnwrap(rowMenu.items.firstIndex { item in item.title == "Add row below" }))
        let withRow = textView.string
        XCTAssertEqual(withRow.components(separatedBy: "\n").count, Self.listItemCalloutNote.components(separatedBy: "\n").count + 1)
        XCTAssertTrue(withRow.contains("\n>   |  |  |\n"), withRow)
        XCTAssertTrue(withRow.contains("\n> - Second step\n"), "The next item is untouched: \(withRow)")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, Self.listItemCalloutNote, "Adding the row is one edit.")
    }

    /// The callout's table editors as the callout's view holds them (`LivePreviewCalloutTableEditing`),
    /// with what the note's editor gives the callout's view (`NativeMarkdownEditor.Coordinator.blockRootView`):
    /// each `editor()` gives the table's editor the table's source as the note has it now, as the
    /// view does as it is drawn again. Clicks sent to a test window do not reach SwiftUI's tap on the table.
    @MainActor
    private final class CalloutTableHarness {
        let coordinator: NativeMarkdownEditor.Coordinator
        let textView: MarkdownMacTextView
        let session: MarkdownSession
        let editors = LivePreviewCalloutTableEditors()

        init(coordinator: NativeMarkdownEditor.Coordinator, textView: MarkdownMacTextView, session: MarkdownSession) {
            self.coordinator = coordinator
            self.textView = textView
            self.session = session
        }

        func editor() throws -> LivePreviewTableEditor {
            let blocks = LivePreviewBlockScanner.blocks(in: textView.string as NSString)
            let blockIndex = try XCTUnwrap(blocks.firstIndex { block in block.kind == .callout })
            let block = blocks[blockIndex]
            let key = LivePreviewBlockKey.keys(for: blocks)[blockIndex]
            let calloutEditing = RenderedBlockSourceEditing(replaceSource: { [weak coordinator, weak textView] editor, transform in
                guard let coordinator, let textView else { return }
                coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
            }, setIsEditingInView: { [weak coordinator] isEditing, editor in
                guard let coordinator else { return }
                if isEditing {
                    coordinator.styling.renderedBlocks.beginEditingInView(blockWithKey: key, at: block.range.location, owner: editor)
                } else {
                    coordinator.styling.renderedBlocks.endEditingInView(owner: editor)
                }
            }, offerCellCommands: { [weak session] target in session?.blockViews.takeTableCellCommands(target) })
            let callout = try XCTUnwrap(CalloutTables.callout(in: block.markdown))
            let editing = LivePreviewCalloutTableEditing(tables: CalloutTables.tables(in: callout), calloutSource: block.sourceLines,
                                                         sourceEditing: calloutEditing, editors: editors, textSize: 17)
            let headerOffset = (block.markdown as NSString).range(of: "| Year").location
            return try XCTUnwrap(editing.editor(forTableStartingAt: headerOffset), "The table's first line starts past its `> `.")
        }
    }

    /// Lets the run loop turn, which ends the undo group of the edits made in this event, as the
    /// app's edits from separate clicks and keys are.
    private func endTheEvent() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    /// A cell typed in, then the bottom and the right "+" strips: each a change of the callout's
    /// table with its markers kept, one undo each, and the callout's view kept across them.
    func testACalloutTablesCellAndStripsChangeTheSourceWithTheMarkersKept() async throws {
        let (coordinator, textView, session) = try await makeEditor(text: Self.calloutNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The callout is drawn") { self.calloutView(in: textView) != nil }
        let view = try XCTUnwrap(calloutView(in: textView))
        let harness = CalloutTableHarness(coordinator: coordinator, textView: textView, session: session)
        let editor = try harness.editor()

        editor.beginEditing(TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(editor.draftText, "2.0")
        XCTAssertTrue(session.blockViews.tableCellCommandTarget?.editor === editor, "The cell offers its commands to the note.")
        editor.draftText = "2.1 | est."
        editor.commitDraft()
        let afterCell = Self.calloutNote.replacingOccurrences(of: "> | 2024 | 2.0 |", with: "> | 2024 | 2.1 \\| est. |")
        XCTAssertEqual(textView.string, afterCell)
        XCTAssertTrue(try harness.editor() === editor, "The table keeps its editor.")
        endTheEvent()

        editor.addRowAtTheEnd()
        let afterRow = afterCell.replacingOccurrences(of: "> | 2025 | 1.8 |\n", with: "> | 2025 | 1.8 |\n> |  |  |\n")
        XCTAssertEqual(textView.string, afterRow)
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 3, column: 0), "The editor moves into the new row's first cell.")
        try await awaitConditionAfterLayout("The callout is drawn again") { self.calloutView(in: textView) != nil }
        XCTAssertTrue(calloutView(in: textView) === view, "The callout's view that made the edits stays, with the cell being typed in.")
        endTheEvent()

        try harness.editor().addColumnAtTheEnd()
        let afterColumn = "Intro line\n\n> [!note] Rates\n> Before the table.\n>\n> | Year | Rate |  |\n> | --- | --- | --- |\n"
            + "> | 2024 | 2.1 \\| est. |  |\n> | 2025 | 1.8 |  |\n> |  |  |  |\n\nAfter the callout\n"
        XCTAssertEqual(textView.string, afterColumn)
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 0, column: 2), "The editor moves into the new column's header.")
        endTheEvent()

        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.undo()
        XCTAssertEqual(textView.string, afterRow, "The column is one edit.")
        undoManager.undo()
        XCTAssertEqual(textView.string, afterCell, "The row is one edit.")
        undoManager.undo()
        XCTAssertEqual(textView.string, Self.calloutNote, "The cell is one edit.")
        editor.endEditing()
    }
}
#endif
