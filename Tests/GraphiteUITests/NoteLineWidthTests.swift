/**
 * File: NoteLineWidthTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: A note's two line widths (HUNT-324): narrow holds the title, the properties, the text and every block to
 *              the readable column, wide gives them all the editor's width, in Live Preview and in the reading view; and
 *              the Format menu's Line Width switch changes Readable Line Length.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// Bases took the pane's whole width while the title, the properties and the text kept to the
/// readable column, so a note with a base had two left edges (HUNT-324). Every block now takes
/// the text's column, which is the readable one in narrow mode and the pane inside its margins
/// in wide mode, as Obsidian does.
@MainActor
final class NoteLineWidthTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    /// A title, properties, a paragraph, an embedded base, a base code block, a table and a row of two pictures.
    private static let note = """
    ---
    tags: [study]
    ---
    A paragraph of ordinary words, long enough to wrap over several lines of the readable column at the width these tests give the note, and wider still.

    ![[Books.base]]

    ```base
    views:
      - type: table
        name: Shelf
    ```

    | Year | Rate |
    | --- | --- |
    | 2024 | 2.0 |

    ![[One.png]] ![[Two.png]]

    End
    """

    private static let windowWidth: CGFloat = 1_400

    private func makeVault() throws -> URL {
        let vault = try TemporaryVault.make(prefix: "LineWidth", for: self).root
        try Data(Self.note.utf8).write(to: vault.appendingPathComponent("Note.md"))
        try Data("views:\n  - type: cards\n    name: Gallery\n".utf8).write(to: vault.appendingPathComponent("Books.base"))
        // A one-pixel PNG for each picture of the row: a row is drawn only for images in the vault.
        let picture = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="))
        for name in ["One.png", "Two.png"] { try picture.write(to: vault.appendingPathComponent(name)) }
        return vault
    }

    private func window(showing view: NSView, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: Self.windowWidth, height: height)
        return window
    }

    private func layOutWindows() {
        windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
    }

    // MARK: Live Preview

    private func makeEditor(vault: URL) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: { _ in })
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.textContainerInset = CGSize(width: MarkdownMacTextView.minimumHorizontalInset, height: 32)
        textView.string = Self.note
        // The cursor after the note, so every block shows its view rather than its source.
        textView.setSelectedRange(NSRange(location: (Self.note as NSString).length, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        _ = window(showing: scrollView, height: 2_400)
        textView.frame.size.width = Self.windowWidth
        textView.inlineTitle = ("Note", NSFont.boldSystemFont(ofSize: 30), .labelColor)
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView)
    }

    private func blockViews(in textView: NSTextView) -> [NSView] {
        textView.subviews.filter { subview in subview is NSHostingView<AnyView> }.sorted { upperView, lowerView in upperView.frame.minY < lowerView.frame.minY }
    }

    /// The properties, the embedded base, the base code block, the table and the picture row.
    private static let livePreviewBlockCount = 5

    func testLivePreviewPutsTheTitleThePropertiesAndEveryBlockBetweenTheTextsEdgesAtEitherLineWidth() async throws {
        let (coordinator, textView) = try await makeEditor(vault: try makeVault())
        defer { withExtendedLifetime(coordinator) {} }
        let padding = try XCTUnwrap(textView.textContainer).lineFragmentPadding
        for lineWidth in NoteLineWidth.allCases {
            textView.readableColumnWidth = lineWidth == .narrow ? MarkdownMacTextView.graphiteReadableColumnWidth : nil
            let expectedWidth = lineWidth == .narrow
                ? MarkdownMacTextView.graphiteReadableColumnWidth - 2 * padding
                : textView.frame.width - 2 * (MarkdownMacTextView.minimumHorizontalInset + padding)
            let isPlaced = {
                let views = self.blockViews(in: textView)
                return views.count == Self.livePreviewBlockCount && views.allSatisfy { view in abs(view.frame.width - expectedWidth) < 0.5 }
            }
            try? await waitUntil("\(lineWidth): every block's view at the column's width") {
                self.layOutWindows()
                return isPlaced()
            }
            XCTAssertTrue(isPlaced(), "\(lineWidth): \(blockViews(in: textView).map(\.frame)), column \(expectedWidth)")
            let columnMinX = textView.textContainerOrigin.x + padding
            let columnMaxX = columnMinX + textView.renderedBlockColumnWidth
            XCTAssertEqual(textView.renderedBlockColumnWidth, expectedWidth, accuracy: 0.5, "\(lineWidth): the text's column")
            if lineWidth == .narrow {
                XCTAssertEqual(columnMinX, ((textView.frame.width - MarkdownMacTextView.graphiteReadableColumnWidth) / 2).rounded(.down) + padding, accuracy: 1, "Narrow: the column is centered")
            } else {
                XCTAssertEqual(columnMinX, MarkdownMacTextView.minimumHorizontalInset + padding, accuracy: 0.5, "Wide: the column starts at the margin")
            }
            let title = try XCTUnwrap(textView.inlineTitleLabel)
            XCTAssertEqual(title.frame.minX, columnMinX, accuracy: 0.5, "\(lineWidth): the title starts where the text does")
            XCTAssertEqual(title.frame.maxX, columnMaxX, accuracy: 0.5, "\(lineWidth): the title ends where the text does")
            for (position, view) in blockViews(in: textView).enumerated() {
                XCTAssertEqual(view.frame.minX, columnMinX, accuracy: 0.5, "\(lineWidth): block \(position) starts where the text does")
                XCTAssertEqual(view.frame.maxX, columnMaxX, accuracy: 0.5, "\(lineWidth): block \(position) ends where the text does")
            }
        }
    }

    // MARK: Reading view

    private func readingFrames(vault: URL, lineWidth: NoteLineWidth) async throws -> (frames: [(noteOffset: Int, frame: CGRect)], position: ReadingPosition) {
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent("index.sqlite"))
        let position = ReadingPosition()
        var configuration = ReadingConfiguration(usesReadableLineLength: lineWidth == .narrow)
        configuration.inlineTitle = "Note"
        let preview = MarkdownPreview(source: Self.note, path: try VaultPath("Note.md"), root: vault, index: index, configuration: configuration,
                                      headingScrollRequest: .constant(nil), handledScrollToken: .constant(nil),
                                      navigate: { _, _ in }, openPDF: { _, _ in }, updateProperties: nil, savedPosition: position)
        let hosting = NSHostingView(rootView: preview.frame(width: Self.windowWidth, height: 2_400))
        window(showing: hosting, height: 2_400).showInvisibly()
        func shownFrames() -> [(noteOffset: Int, frame: CGRect)] {
            position.blockLocations.compactMap { location in position.frame(ofBlock: location.blockIdentifier).map { frame in (location.noteOffset, frame) } }
        }
        try await waitUntil("\(lineWidth): the reading view laid out every block") {
            self.layOutWindows()
            let frames = shownFrames()
            return !position.blockLocations.isEmpty && frames.count == position.blockLocations.count
        }
        return (shownFrames(), position)
    }

    func testTheReadingViewPutsThePropertiesAndEveryBlockInTheTextsColumnAtEitherLineWidth() async throws {
        let vault = try makeVault()
        let margin = ReadingConfiguration.minimumHorizontalMargin
        let baseOffset = (Self.note as NSString).range(of: "```base").location
        for lineWidth in NoteLineWidth.allCases {
            let columnWidth = lineWidth == .narrow ? ReadingConfiguration.readableColumnWidth : Self.windowWidth - 2 * margin
            let columnMinX = (Self.windowWidth - columnWidth) / 2
            let columnMaxX = columnMinX + columnWidth
            let (frames, position) = try await readingFrames(vault: vault, lineWidth: lineWidth)
            defer { withExtendedLifetime(position) {} }
            XCTAssertGreaterThanOrEqual(frames.count, 5, "\(lineWidth): the properties, the paragraph, the bases, the table and the pictures")
            for (noteOffset, frame) in frames {
                XCTAssertEqual(frame.minX, columnMinX, accuracy: 0.5, "\(lineWidth): the block at \(noteOffset) starts where the text does")
                XCTAssertLessThanOrEqual(frame.maxX, columnMaxX + 0.5, "\(lineWidth): the block at \(noteOffset) ends inside the column, \(frame)")
            }
            let base = try XCTUnwrap(frames.first { block in block.noteOffset == baseOffset }, "\(lineWidth): the base code block is shown")
            XCTAssertEqual(base.frame.maxX, columnMaxX, accuracy: 0.5, "\(lineWidth): the base ends where the column does, no wider")
            windows.forEach { window in window.orderOut(nil); window.contentView = nil }
            windows = []
        }
    }

    // MARK: The Format menu's switch

    func testTheLineWidthSwitchChangesReadableLineLengthOnTheDeviceAndInTheVault() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.usesReadableLineLength = true
        let lineWidth = workspace.lineWidthBinding(changes: VaultSettingsChanges())
        XCTAssertEqual(lineWidth.wrappedValue, .narrow)
        lineWidth.wrappedValue = .wide
        XCTAssertFalse(workspace.preferences.usesReadableLineLength, "With no vault open, the device's choice changes")
        XCTAssertFalse(workspace.usesReadableLineLength)

        let vault = try TemporaryVault.make(prefix: "LineWidthSwitch", files: ["Note.md": "x"], for: self).root
        try await workspace.openFolderAsVault(vault)
        let vaultLineWidth = workspace.lineWidthBinding(changes: VaultSettingsChanges())
        vaultLineWidth.wrappedValue = .narrow
        try await waitUntil("the vault's app.json says readable line length") { workspace.vaultSettings.usesReadableLineLength == true }
        XCTAssertTrue(workspace.usesReadableLineLength)
        XCTAssertEqual(vaultLineWidth.wrappedValue, .narrow)
        let written = try String(contentsOf: vault.appendingPathComponent(".obsidian/app.json"), encoding: .utf8)
        XCTAssertTrue(written.contains("\"readableLineLength\": true"), "Obsidian reads the same choice: \(written)")
        vaultLineWidth.wrappedValue = .wide
        try await waitUntil("the vault's app.json says wide") { workspace.vaultSettings.usesReadableLineLength == false }
        XCTAssertFalse(workspace.usesReadableLineLength)
    }
}
#endif
