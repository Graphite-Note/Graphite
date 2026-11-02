/**
 * File: OversizedNoteHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The read-only view of a note too large to edit, in a real iPad or iPhone window, and Edit Anyway (HUNT-102).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class OversizedNoteHostedTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    func testAnOversizedNoteShowsItsFirstPagesWithoutAnEditorAndEditAnywayBringsTheEditor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OversizedNote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        let line = Data("A line of the note, grown by a paste.\n".utf8)
        var bytes = Data(capacity: 9 * 1_048_576 + line.count)
        while bytes.count < 9 * 1_048_576 { bytes.append(line) }
        let location = directory.appendingPathComponent("Big.md")
        try bytes.write(to: location)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let path = try VaultPath("Big.md")
        let openedTab = await workspace.open(path)
        let tabID = try XCTUnwrap(openedTab)
        let note = try XCTUnwrap(workspace.document(for: tabID).oversizedNote)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let hostingWindow = UIWindow(windowScene: scene)
        hostingWindow.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        let controller = UIHostingController(rootView: TabDocumentView(workspace: workspace, tab: try XCTUnwrap(workspace.layout.tab(withID: tabID)),
                                                                       document: workspace.document(for: tabID), isFocused: true,
                                                                       showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {}))
        hostingWindow.rootViewController = controller
        hostingWindow.isHidden = false
        window = hostingWindow

        try await waitUntil("the first pages to be read") { note.pagesRead > 0 }
        XCTAssertLessThan(note.pagesRead, note.pageCount / 4, "Read \(note.pagesRead) of \(note.pageCount) pages.")
        XCTAssertTrue(textViews(in: controller.view).isEmpty, "Read-only shows no editor.")
        XCTAssertEqual(try Data(contentsOf: location), bytes)

        await workspace.editOversizedNoteAnyway(inTab: tabID)
        let session = try XCTUnwrap(workspace.document(for: tabID).markdownSession)
        XCTAssertEqual(session.errorMessage, MarkdownSession.grownTooLargeMessage)
        XCTAssertEqual(session.text.utf8.count, bytes.count)
        XCTAssertEqual(try Data(contentsOf: location), bytes, "Loading it writes nothing.")
    }

    private func textViews(in parent: UIView) -> [UITextView] {
        parent.subviews.flatMap { child in ((child as? UITextView).map { [$0] } ?? []) + textViews(in: child) }
    }
}
#endif
