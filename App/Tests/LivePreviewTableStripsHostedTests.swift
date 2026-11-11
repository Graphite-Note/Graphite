/**
 * File: LivePreviewTableStripsHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: On the iPad, a Live Preview table shows no "+" strip while none of its cells is edited, and the strips
 *              stay in the table's view, the bottom one adding a last row and opening the editor in it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The hosted workspace's own Live Preview and the strips in a window of their own, with the
/// accessibility runtime on so the strips are found and pressed as VoiceOver finds and presses them.
@MainActor
final class LivePreviewTableStripsHostedTests: XCTestCase {
    private var window: UIWindow?

    private static let note = "Intro line\n\n| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n| 2025 | 1.8 |\n\nAfter the table\n"

    override func setUp() async throws {
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    /// Nothing hovers over a finger's screen: a table no cell of which is edited shows no strip.
    /// (A finger's tap on a cell cannot be made here: synthesized touches reach UIKit's gesture
    /// recognizers but not SwiftUI's tap on the table, so the strips are tried on their own below.)
    func testATableNoCellOfWhichIsEditedShowsNoStrip() async throws {
        let (_, editor) = try await openNote(Self.note)
        let tableView = try await blockView(in: editor)
        try await waitUntil("the table's cells are read") { self.accessibilityElements(in: tableView).contains { element in element.accessibilityLabel == "2024" } }
        XCTAssertNil(strip("Add row below", in: tableView))
        XCTAssertNil(strip("Add column to the right", in: tableView))
        attachScreenshot(named: "No strips while no cell is edited")
    }

    /// The strips as a table being edited shows them: inside its view, and the bottom one adds a
    /// last row to the table's source and moves the editor into its first cell.
    func testTheBottomStripAddsARowAndEditsItsFirstCell() async throws {
        var source = "| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n"
        let editor = LivePreviewTableEditor()
        func viewUpdates() {
            editor.update(source: source, textSize: 17, sourceEditing: RenderedBlockSourceEditing(replaceSource: { _, transform in
                source = transform(source) ?? source
                viewUpdates()
            }, setIsEditingInView: { _, _ in }))
        }
        viewUpdates()
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        let geometry = TableAddStripsGeometry(tableBounds: CGRect(x: 20, y: 20, width: 300, height: 120),
                                              blockBounds: CGRect(x: 0, y: 0, width: 400, height: 150))
        let host = UIHostingController(rootView: AnyView(ZStack(alignment: .topLeading) {
            LivePreviewTableAddStrips(geometry: geometry, editor: editor, isPointerOverStrip: .constant(false))
        }.frame(width: 400, height: 150, alignment: .topLeading).ignoresSafeArea()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 150)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        var addRow: NSObject?
        try await waitUntil("the strips are shown") {
            addRow = self.strip("Add row below", in: host.view)
            return addRow != nil && self.strip("Add column to the right", in: host.view) != nil
        }
        attachScreenshot(named: "The strips")
        let addRowFrameInWindow = try XCTUnwrap(addRow).accessibilityFrame
        XCTAssertEqual(addRowFrameInWindow.midY, geometry.rowStrip.midY, accuracy: 1, "The bottom strip is where its geometry puts it, inside the block.")
        // The strip is 14 points thick; a finger's target around its "+" is 44 points across.
        let addRowFrame = try XCTUnwrap(addRow).accessibilityFrame
        XCTAssertGreaterThanOrEqual(addRowFrame.height, 44)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(strip("Add column to the right", in: host.view)).accessibilityFrame.width, 44)

        XCTAssertTrue(try XCTUnwrap(addRow).accessibilityActivate())
        XCTAssertEqual(source, "| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n|  |  |\n")
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 2, column: 0))
    }

    // MARK: Finding things

    private func blockView(in editor: MarkdownTextView) async throws -> UIView {
        var found: UIView?
        try await waitUntil("the table is drawn") {
            found = editor.subviews.first { subview in !subview.isHidden && self.isViewOfHostingController(subview) }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func isViewOfHostingController(_ view: UIView) -> Bool {
        var responder = view.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if currentResponder is UIHostingController<AnyView> { return true }
            responder = currentResponder.next
        }
        return false
    }

    private func strip(_ label: String, in view: UIView) -> NSObject? {
        accessibilityElements(in: view).first { element in element.accessibilityLabel == label }
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
    }

    // MARK: Hosting

    private func openNote(_ text: String) async throws -> (MarkdownSession, MarkdownTextView) {
        let directory = try TemporaryVault.make(prefix: "TableStrips", for: self).root
        try Data(text.utf8).write(to: directory.appendingPathComponent("Table.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Table.md")
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

    /// SwiftUI builds its accessibility elements only while an assistive technology asks for them.
    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }
}
#endif
