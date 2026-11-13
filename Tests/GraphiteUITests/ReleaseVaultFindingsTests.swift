/**
 * File: ReleaseVaultFindingsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The defects the release test vault's checks found on 2026-11-12 (Docs/Bug-hunt-todo.md section 15),
 *              each pinned where the Mac package can reach it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Section 15 of the bug hunt: what the release test vault's checks found, each test failing
/// before its fix.
@MainActor
final class ReleaseVaultFindingsTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    /// HUNT-332: a graph view whose query was cancelled (its tab hidden, the index changed under
    /// it) put up the alert "The operation couldn't be completed. (Swift.CancellationError error 1.)".
    func testACancelledGraphQueryShowsNoAlert() async throws {
        let vault = try TemporaryVault.make(prefix: "GraphCancel", files: ["Note.md": "A link to [[Other]].", "Other.md": "Text."], for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault.root)
        try await waitUntil { workspace.hasCompletedIndexScan }
        workspace.graphCache = nil

        // Cancelled before it starts: the index's read throws CancellationError at once.
        let query = Task { @MainActor in await workspace.vaultGraph() }
        query.cancel()
        let graph = await query.value

        XCTAssertNil(graph)
        XCTAssertNil(workspace.errorMessage)
    }

    /// HUNT-329: the row the "+" strip adds, `|  |  |`, had no text the parser kept, so the reading
    /// view and Live Preview drew the table without it until something was typed in it.
    func testATableRowOfEmptyCellsIsParsedForDrawing() throws {
        let table = "| Left | Right |\n| --- | --- |\n| a | b |\n|  |  |\n"
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: table)
        var rowIndices: Set<Int> = []
        for run in attributed.runs {
            for component in run.presentationIntent?.components ?? [] {
                switch component.kind {
                case .tableHeaderRow: rowIndices.insert(0)
                case .tableRow(let rowIndex): rowIndices.insert(rowIndex)
                default: break
                }
            }
        }
        XCTAssertEqual(rowIndices.count, 3, "The header, the row with text and the empty row: \(rowIndices.sorted())")
    }

    /// HUNT-351: two PDF embeds on one line stayed link text in Live Preview; a line of embeds now holds both,
    /// as a line of pictures holds its pictures, and Live Preview draws each as its viewer.
    func testTwoPDFEmbedsOnALineAreALineOfEmbeds() throws {
        let line = "![[Lab notebook.pdf#height=200]] ![[Cornell.pdf#height=200]]"
        let blocks = LivePreviewBlockScanner.blocks(in: (line + "\n") as NSString, pluginCodeBlockLanguages: [])
        guard case .imageLine(let pieces)? = blocks.first?.kind else { return XCTFail("\(blocks.map(\.kind))") }
        let targets = pieces.compactMap { piece -> String? in if case .image(let embed) = piece { embed.target } else { nil } }
        XCTAssertEqual(targets, ["Lab notebook.pdf#height=200", "Cornell.pdf#height=200"])
    }

    /// HUNT-351, the reading view: the line of two PDF embeds was written as two links, while
    /// one PDF alone on its line is its viewer. Each PDF is now an embed block of its own, and the
    /// text and pictures between them stay Markdown, the pictures side by side.
    func testTwoPDFEmbedsOnALineAreTwoViewersInTheReadingView() {
        func described(_ blocks: [NotePreviewBlock]) -> [String] {
            blocks.map { block in
                switch block {
                case .embed(let embed): "embed " + embed.target
                case .markdown(let markdown): "markdown " + markdown
                default: "other"
                }
            }
        }
        XCTAssertEqual(described(NotePreviewDocument.blocks(from: "Above\n\n![[Lab notebook.pdf#height=200]] ![[Cornell.pdf#height=200]]\n\nBelow\n")),
                       ["markdown Above\n", "embed Lab notebook.pdf#height=200", "embed Cornell.pdf#height=200", "markdown \nBelow\n"])
        XCTAssertEqual(described(NotePreviewDocument.blocks(from: "See ![[a.png|100]] ![[b.png|100]] then ![[Slides.pdf#page=2]] and after")),
                       ["markdown See ![[a.png|100]] ![[b.png|100]] then", "embed Slides.pdf#page=2", "markdown and after"])
        XCTAssertEqual(described(NotePreviewDocument.blocks(from: "![[a.png|100]] ![[b.png|100]]")), ["markdown ![[a.png|100]] ![[b.png|100]]"],
                       "A line of pictures alone stays one paragraph, side by side.")
        XCTAssertEqual(described(NotePreviewDocument.blocks(from: "- ![[Slides.pdf]] ![[Cornell.pdf]]")), ["markdown - ![[Slides.pdf]] ![[Cornell.pdf]]"],
                       "A list item keeps its line.")
        let located = NotePreviewDocument.locatedBlocks(from: "x\n\nA ![[Slides.pdf]] B\n")
        XCTAssertEqual(located.map(\.startOffset), [0, 3, 5, 21], "Each piece starts where it is in the note.")
    }

    /// HUNT-352: a PDF embedded in a table cell showed its source, `!` included, in Live Preview. It is a
    /// link to the PDF's page named by its file, as the reading view writes it.
    func testAPDFEmbeddedInATableCellIsALinkToIt() async throws {
        let vault = try TemporaryVault.make(prefix: "PDFInCell", files: ["Lecture slides.pdf": "%PDF-1.4\n"], for: self)
        let table = "| PDF | Page |\n| --- | --- |\n| ![[Lecture slides.pdf#page=2\\|Slide 2]] | 2 |\n"
        let environment = LivePreviewEnvironment(root: vault.root, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
            resolve: { target, _ in try? VaultPath(String(target.split(separator: "#").first ?? "")) },
            open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let preparation = await LivePreviewText.preparedResolvingEmbeds(table, environment: environment)
        XCTAssertFalse(preparation.markdown.contains("![["), preparation.markdown)
        XCTAssertTrue(preparation.markdown.contains("[Lecture slides.pdf]("), preparation.markdown)
    }

    /// HUNT-337: in the dark, a note's name fading in with the zoom was dark grey on the graph's black.
    /// A name a third of the way into its fade now reads at 4.5 to 1 (white at 85 % over black, as drawn).
    func testANameFadingInWithTheZoomReadsOnTheDarkGraph() {
        func luminance(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let nameStrength = 0.85 * GraphCanvasRenderer.shownNameOpacity(forZoomOpacity: 0.3)
        let contrast = (luminance(nameStrength) + 0.05) / (luminance(0) + 0.05)
        XCTAssertGreaterThanOrEqual(contrast, 4.5)
        XCTAssertEqual(GraphCanvasRenderer.shownNameOpacity(forZoomOpacity: 0), 0, "A name not yet shown stays hidden.")
        XCTAssertEqual(GraphCanvasRenderer.shownNameOpacity(forZoomOpacity: 1), 1)
    }

    #if os(macOS)
    /// HUNT-331: the zoom over a note drew a picture smaller than the window at its own size, so a
    /// 480 by 270 picture was smaller in the zoom than in the note. It is fitted to the window.
    func testTheZoomFitsASmallPictureToTheWindow() async throws {
        let vault = try TemporaryVault.make(prefix: "ZoomFit", for: self)
        let location = try vault.writeFile("Small.png", data: try Self.pngData(width: 480, height: 270))
        let hosting = NSHostingView(rootView: ImageZoomOverlay(location: location, title: "Small.png", close: {}))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.showInvisibly()
        defer { window.close() }

        var scrollView: MagnifyingImageScrollView?
        try await waitUntil("the picture is shown") {
            hosting.layoutSubtreeIfNeeded()
            scrollView = Self.descendants(of: hosting).compactMap { view in view as? MagnifyingImageScrollView }.first { view in view.image != nil }
            return scrollView != nil
        }
        let shown = try XCTUnwrap(scrollView)
        shown.layoutSubtreeIfNeeded()
        let shownWidth = 480 * shown.magnification
        let shownHeight = 270 * shown.magnification
        XCTAssertGreaterThan(shownWidth, 480, "A picture smaller than the window is enlarged.")
        XCTAssertTrue(abs(shownWidth - (shown.bounds.width - 48)) < 2 || abs(shownHeight - (shown.bounds.height - 48)) < 2,
                      "Fitted to the window less its margins: \(shownWidth) by \(shownHeight) in \(shown.bounds.size)")
    }

    /// HUNT-330: a picture on a line of its own in Live Preview offered only the block's "Edit
    /// Source": the block's own menu took the long press and the secondary click from the
    /// picture's. The block's menu opened on the picture lists the picture's commands first.
    func testABlockPicturesCommandsAreInItsBlocksMenu() async throws {
        let context = RenderedBlockMenuContext()
        let actions = ReadingImageActions(providerIdentity: ObjectIdentifier(self), viewImage: { _ in }, editDrawing: nil,
                                          tabOpening: PictureTabOpening(open: { _, _ in }, otherSideTitle: "Open to the Right"))
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: try Self.pngData(width: 200, height: 100))?.cgImage)
        let picture = EmbeddedImageView(image: pixels, aspectRatio: 2, displayWidth: 200, edit: nil, view: {}, path: try VaultPath("Sunset.png"),
                                        tabOpening: actions.tabOpening)
            .frame(width: 400, height: 100, alignment: .topLeading)
            .modifier(RenderedBlockPictureMenu())
            .coordinateSpace(.named(LivePreviewTableEditor.blockCoordinateSpaceName))
            .environment(\.renderedBlockMenuContext, context)
            .environment(\.readingImageActions, actions)
        let hosting = NSHostingView(rootView: picture)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.showInvisibly()
        defer { window.close() }

        try await waitUntil("the picture's commands are in the block's menu") {
            hosting.layoutSubtreeIfNeeded()
            return !context.items(at: CGPoint(x: 100, y: 50)).isEmpty
        }
        XCTAssertEqual(context.items(at: CGPoint(x: 100, y: 50)).map(\.title), ["Zoom In", "Open in New Tab", "Open to the Right"])
        XCTAssertEqual(context.items(at: CGPoint(x: 300, y: 50)).map(\.title), [], "Beside the picture, the block's menu is its own.")
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { child in [child] + descendants(of: child) }
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    /// HUNT-340: "Sort by column (Z to A)" had no icon in a table cell's menu, its symbol's name
    /// being none of the system's. Every command of the menu names a symbol that exists.
    func testEveryTableCellCommandHasASymbolThatExists() {
        for command in TableCellCommand.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: command.symbolName, accessibilityDescription: nil), "\(command): \(command.symbolName)")
        }
    }
    #endif
}
