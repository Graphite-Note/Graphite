/**
 * File: LivePreviewTableInWindowTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A Live Preview table drawn in a Mac window with its editing layer: the edited cell grows its row to the field's
 *              height when the cell's source takes more lines than its drawn text, a column's grip sits above its column and,
 *              dropped on the next column, moves the column in the note, and a menu command leaves the table out of a scroll
 *              view, so its strips and grips stay drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The table's Markdown, drawn again as its edits change it.
@MainActor
@Observable
private final class TableMarkdown {
    var markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }
}

private struct EditedTable: View {
    let markdown: TableMarkdown
    let environment: LivePreviewEnvironment
    let editor: LivePreviewTableEditor

    var body: some View {
        RenderedMarkdownBlock(markdown: markdown.markdown, environment: environment)
            .environment(\.livePreviewTableEditor, editor)
    }
}

@MainActor
final class LivePreviewTableInWindowTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        try await super.tearDown()
    }

    private static let table = "| $V_{GS}$ (V) | Region |\n| --- | --- |\n| 0.4 | off |\n| 0.9 | saturation |\n"

    /// The table's source as its edits left it.
    private let drawnTable = TableMarkdown(LivePreviewTableInWindowTests.table)
    private var source: String {
        get { drawnTable.markdown }
        set { drawnTable.markdown = newValue }
    }

    /// The table drawn as Live Preview draws it, 30 points in from the sides of a window 320 points wide, its editor given
    /// the table's source.
    private func showTable() throws -> LivePreviewTableEditor {
        let editor = LivePreviewTableEditor()
        func viewUpdates() {
            editor.update(source: source, textSize: 17, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [unowned self] _, transform in
                self.source = transform(self.source) ?? self.source
                viewUpdates()
            }, setIsEditingInView: { _, _ in }))
        }
        viewUpdates()
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        let environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                 resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let view = EditedTable(markdown: drawnTable, environment: environment, editor: editor)
            .padding(30)
            .coordinateSpace(.named(LivePreviewTableEditor.blockCoordinateSpaceName))
            .frame(width: 320, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        let host = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.window = window
        self.editor = editor
        return editor
    }

    private func laidOut(_ condition: @escaping (TableCellGrid) -> Bool, _ description: String) async throws {
        try await waitUntil(description, timeoutSeconds: 5) {
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.window?.displayIfNeeded()
            guard let layout = self.editor?.layout else { return false }
            return condition(layout)
        }
    }

    private weak var editor: LivePreviewTableEditor?

    func testTheEditedCellsRowGrowsToItsFieldAndShrinksBackAfter() async throws {
        let editor = try showTable()
        try await laidOut({ layout in layout.numberOfRows == 3 }, "the table is laid out")
        let drawnHeaderHeight = try XCTUnwrap(editor.layout).rowBounds(0).height

        editor.beginEditing(TableCellPosition(row: 0, column: 0))
        XCTAssertEqual(editor.draftText, "$V_{GS}$ (V)")
        editor.draftText = "$V_{GS}$ (V), the gate to source voltage, written out long"
        try await laidOut({ layout in layout.rowBounds(0).height > drawnHeaderHeight + 10 }, "the header row grows with its edited cell")
        let layout = try XCTUnwrap(editor.layout)
        let fieldHeight = try XCTUnwrap(editor.editedCellHeight)
        XCTAssertGreaterThan(fieldHeight, drawnHeaderHeight + 10, "The source wraps onto more lines than the drawn cell.")
        XCTAssertGreaterThanOrEqual(layout.rowBounds(0).height + 0.5, fieldHeight, "The row is as tall as the field.")
        XCTAssertGreaterThanOrEqual(layout.rowBounds(1).minY + 0.5, layout.rowBounds(0).minY + fieldHeight, "The field ends above the row below.")
        XCTAssertNil(editor.minimumHeight(ofCellAtRow: 1, column: 0), "Only the edited cell keeps a height.")

        // The cell's own text again, so ending the edit writes the note as it was.
        editor.draftText = "$V_{GS}$ (V)"
        editor.endEditing()
        XCTAssertNil(editor.editedCellHeight)
        try await laidOut({ layout in layout.rowBounds(0).height < drawnHeaderHeight + 10 }, "the row is drawn at its own height again")
    }

    /// A grip dropped on another column, as its drag's end calls it: clicks and drags sent to a test window do not reach
    /// SwiftUI's gestures, so the drag itself is checked by hand in the app.
    func testAColumnsGripDroppedOnTheNextColumnMovesTheColumnInTheNote() async throws {
        let editor = try showTable()
        try await laidOut({ layout in layout.numberOfRows == 3 }, "the table is laid out")
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        let layout = try XCTUnwrap(editor.layout)
        let grip = TableGripsGeometry(tableBounds: layout.bounds, placement: editor.tablePlacement).columnGrip(for: layout.columnBounds(0))
        XCTAssertEqual(grip.midX, layout.columnBounds(0).midX, accuracy: 1, "The column's grip is centred above it.")
        let dropCell = LivePreviewTableEditor.cell(at: CGPoint(x: layout.columnBounds(1).midX, y: layout.rowBounds(1).midY), in: layout)
        XCTAssertEqual(dropCell, TableCellPosition(row: 1, column: 1), "The pointer over the second column picks it as the drop place.")
        editor.moveColumn(0, to: try XCTUnwrap(dropCell).column)
        XCTAssertEqual(source, "| Region | $V_{GS}$ (V) |\n| --- | --- |\n| off | 0.4 |\n| saturation | 0.9 |\n")
        XCTAssertEqual(editor.selectedRange, MarkdownTableCellRange(rows: 0...2, columns: 1...1), "The moved column stays selected.")
    }

    /// A table drawn again after a menu command was measured wider for one pass and kept in a horizontal scroll view,
    /// which clipped the "+" strips and grips outside it.
    func testAMenuCommandLeavesTheTableOutOfAScrollViewWithItsCellEdited() async throws {
        let editor = try showTable()
        try await laidOut({ layout in layout.numberOfRows == 3 }, "the table is laid out")
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        editor.perform(.addRowBelow)
        try await laidOut({ layout in layout.numberOfRows == 4 }, "the added row is drawn")
        // Laid out frame after frame past Overflow's 300 ms wait, the table never moves into a scroll view.
        let end = ContinuousClock.now + .milliseconds(700)
        var wasInAScrollView = false
        try await waitUntil("the table was laid out for 700 ms", timeoutSeconds: 5) {
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.window?.displayIfNeeded()
            wasInAScrollView = wasInAScrollView || self.showsScrollView
            return ContinuousClock.now >= end
        }
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 2, column: 0), "The added row's cell is edited, so the strips show.")
        XCTAssertFalse(wasInAScrollView, "The table fits and is drawn in place, its strips and grips unclipped.")
    }

    private var showsScrollView: Bool {
        guard let root = window?.contentView else { return false }
        var views: [NSView] = [root]
        while let view = views.popLast() {
            if view is NSScrollView { return true }
            views.append(contentsOf: view.subviews)
        }
        return false
    }
}
#endif
