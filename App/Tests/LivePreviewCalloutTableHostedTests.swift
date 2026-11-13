/**
 * File: LivePreviewCalloutTableHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: On the iPad, the long-press menu of a table in a Live Preview callout is the table's cell menu, and its
 *              commands change the note's source with the callout's quote markers kept, each one undoable edit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The hosted workspace's own Live Preview of a note with a callout holding a table.
@MainActor
final class LivePreviewCalloutTableHostedTests: XCTestCase {
    private var window: UIWindow?

    private static let note = "Intro line\n\n> [!note] Rates\n> Before the table.\n>\n> | Year | Rate |\n> | --- | --- |\n> | 2024 | 2.0 |\n"
        + "> | 2025 | 1.8 |\n\nAfter the callout\n"

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    /// The menu at the callout's table offers the table's rows and columns, above the title only
    /// Edit Source; Add row below and Add column to the right write lines with their `> `, drawn in
    /// the callout at once, and one undo takes each back.
    func testTheCalloutTablesMenuAddsARowAndAColumnWithTheMarkersKept() async throws {
        let (session, editor) = try await openNote(Self.note)
        let calloutView = try await blockView(in: editor)
        let menu = try XCTUnwrap(renderedBlockMenu(of: calloutView))
        var tablePoint: CGPoint?
        try await waitUntil("the callout's table is laid out") {
            tablePoint = self.points(downThe: calloutView).first { point in menu.context.items(at: point).first?.title == "Row" }
            return tablePoint != nil
        }
        let point = try XCTUnwrap(tablePoint)
        XCTAssertTrue(menu.context.items(at: CGPoint(x: 60, y: 6)).isEmpty, "The callout's title has no table commands.")
        XCTAssertEqual(menu.context.items(at: point).map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)"])
        attachScreenshot(named: "The callout and its table")
        let heightBefore = calloutView.bounds.height

        try choose("Row", "Add row below", at: point, in: menu)
        try await waitUntil("the row is in the note") { session.text.contains("\n> |  |  |\n") }
        XCTAssertEqual(session.text.components(separatedBy: "\n").count, Self.note.components(separatedBy: "\n").count + 1)
        assertCalloutKeepsItsMarkers(session.text)
        try await waitUntil("the callout is drawn with the new row") { (self.currentBlockView(in: editor)?.bounds.height ?? 0) > heightBefore + 10 }
        attachScreenshot(named: "A row added to the callout's table")
        let withRow = session.text

        var columnPoint: CGPoint?
        try await waitUntil("the callout's table is laid out again") {
            guard let view = self.currentBlockView(in: editor), let currentMenu = self.renderedBlockMenu(of: view) else { return false }
            columnPoint = self.points(downThe: view).first { point in currentMenu.context.items(at: point).first?.title == "Row" }
            return columnPoint != nil
        }
        let currentView = try XCTUnwrap(currentBlockView(in: editor))
        let widthBefore = currentView.bounds.width
        try choose("Column", "Add column to the right", at: try XCTUnwrap(columnPoint), in: try XCTUnwrap(renderedBlockMenu(of: currentView)))
        try await waitUntil("the column is in the note") { session.text.contains("> | --- | --- | --- |\n") }
        assertCalloutKeepsItsMarkers(session.text)
        try await waitUntil("the callout is drawn again for its new source") { self.currentBlockView(in: editor).map { view in view !== currentView && view.bounds.width == widthBefore } ?? false }
        attachScreenshot(named: "A column added to the callout's table")

        let undoManager = try XCTUnwrap(editor.undoManager)
        undoManager.undo()
        XCTAssertEqual(editor.text, withRow, "The column is one edit.")
        undoManager.undo()
        XCTAssertEqual(editor.text, Self.note, "The row is one edit.")
    }

    // MARK: Checking the note

    private func assertCalloutKeepsItsMarkers(_ note: String, file: StaticString = #filePath, line: UInt = #line) {
        let lines = note.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(of: "> [!note] Rates"), let afterIndex = lines.firstIndex(of: "After the callout") else {
            return XCTFail("The callout's header and the text after it are kept: \(note)", file: file, line: line)
        }
        for calloutLine in lines[headerIndex..<(afterIndex - 1)] {
            XCTAssertTrue(calloutLine.hasPrefix(">"), "\(calloutLine) keeps its marker", file: file, line: line)
        }
    }

    private func choose(_ group: String, _ title: String, at point: CGPoint, in menu: RenderedBlockEditSourceMenu) throws {
        let groupItem = try XCTUnwrap(menu.context.items(at: point).first { item in item.title == group }, group)
        let action = try XCTUnwrap(groupItem.children.first { item in item.title == title }?.action, title)
        action()
    }

    // MARK: Finding things

    /// Points down the middle of the view's first column, from its top.
    private func points(downThe view: UIView) -> [CGPoint] {
        stride(from: 4.0, to: view.bounds.height, by: 6).map { distanceFromTop in CGPoint(x: 60, y: distanceFromTop) }
    }

    private func currentBlockView(in editor: MarkdownTextView) -> UIView? {
        editor.subviews.first { subview in !subview.isHidden && renderedBlockMenu(of: subview) != nil }
    }

    private func blockView(in editor: MarkdownTextView) async throws -> UIView {
        var found: UIView?
        try await waitUntil("the callout is drawn") {
            found = editor.subviews.first { subview in !subview.isHidden && self.renderedBlockMenu(of: subview) != nil }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func renderedBlockMenu(of view: UIView) -> RenderedBlockEditSourceMenu? {
        var responder = view.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if let host = currentResponder as? UIHostingController<AnyView> {
                return objc_getAssociatedObject(host, &RenderedBlockEditSourceMenu.associationKey) as? RenderedBlockEditSourceMenu
            }
            responder = currentResponder.next
        }
        return nil
    }

    // MARK: Hosting

    private func openNote(_ text: String) async throws -> (MarkdownSession, MarkdownTextView) {
        let directory = try TemporaryVault.make(prefix: "CalloutTable", for: self).root
        try Data(text.utf8).write(to: directory.appendingPathComponent("Callout.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Callout.md")
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
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        var editor: MarkdownTextView?
        try await waitUntil("the note is shown") {
            editor = self.descendants(of: controller.view, matching: MarkdownTextView.self).first { editor in
                editor.window != nil && editor.text == session.text && editor.bounds.width > 0
            }
            return editor != nil
        }
        return (session, try XCTUnwrap(editor))
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
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
