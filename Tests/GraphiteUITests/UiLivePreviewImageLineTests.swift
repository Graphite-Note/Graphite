/**
 * File: UiLivePreviewImageLineTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A line of image embeds, or of images among text, is drawn in Live Preview as pictures side by
 *              side at their sizes (HUNT-323); with the cursor on it, only the embed the cursor is in shows its
 *              source and the others stay pictures; a list item's pictures stand beside its bullet, wrapping
 *              under the first (issue #102).
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 12/11/2026
 */

import XCTest
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner's photo row showed in Live Preview as blue link text, `IMG_6482.JPG|200 …`, while
/// reading view showed the pictures: Live Preview drew an embed only when it was alone on its line.
@MainActor
final class UiLivePreviewImageLineTests: XCTestCase {
    private var vault: URL!

    private var windows: [NSWindow] = []

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ImageLine", for: self).root
    }

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    /// The owner's line, with made-up file names: nine photos 200 points wide, uppercase `.JPG`.
    private static let photoRow = (1...9).map { number in "![[Photo_\(number).JPG|200]]" }.joined(separator: " ")

    /// A red picture of `width` by `height` pixels, written as JPEG or PNG by its extension.
    @discardableResult
    private func writeRedImage(named name: String, width: Int = 80, height: Int = 40) throws -> URL {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let location = vault.appendingPathComponent(name)
        let type = (name as NSString).pathExtension.lowercased() == "png" ? UTType.png : UTType.jpeg
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return location
    }

    private func imageLinePieces(_ line: String) throws -> [ImageLinePiece] {
        let blocks = LivePreviewBlockScanner.blocks(in: line as NSString)
        XCTAssertEqual(blocks.count, 1, "The line is one block.")
        let block = try XCTUnwrap(blocks.first)
        guard case .imageLine(let pieces) = block.kind else {
            XCTFail("The scanner did not find a line of images in \(line): \(block.kind)")
            return []
        }
        XCTAssertEqual(block.range, NSRange(location: 0, length: (line as NSString).length))
        return pieces
    }

    private func images(in pieces: [ImageLinePiece]) -> [EmbedReference] {
        pieces.compactMap { piece in if case .image(let embed) = piece { embed } else { nil } }
    }

    /// What an earlier look-up of each picture left behind: where it was found and its decoded
    /// pixels, for the width it is shown at one pixel a point. The first frame of a new view
    /// draws those, since a look-up only ends after it.
    private func rememberPictures(of pieces: [ImageLinePiece]) async throws {
        for embed in images(in: pieces) {
            let path = try VaultPath(embed.target)
            let location = try path.url(in: vault)
            let pixelWidth = EmbeddedImageDisplayWidth.pixelWidth(columnWidth: nil, displaySize: embed.displaySize, displayScale: 1)
            _ = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: pixelWidth)
            LivePreviewEmbedImageLocations.remember(.init(path: path, location: location), for: embed, in: vault)
        }
    }

    /// Each embed's file is where its target says; the decoded pixels remembered for it are
    /// what a first frame draws.
    private func environment() -> LivePreviewEnvironment {
        LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                               resolve: { target, _ in try? VaultPath(target) },
                               open: { _ in }, follow: { _, _ in }, updateProperties: nil)
    }

    private func firstFrame(of line: String, width: CGFloat) throws -> CGImage {
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: line as NSString).first)
        let renderer = ImageRenderer(content: LivePreviewWidgetView(block: block, environment: environment(), revealSource: {}, reportHeight: { _ in })
            .environment(\.displayScale, 1)
            .frame(width: width))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func isRed(_ image: CGImage, x pixelColumn: Int, y pixelRow: Int) throws -> Bool {
        let pixel = try pixelBytes(of: image, x: pixelColumn, y: pixelRow)
        return pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60 && pixel[3] > 200
    }

    /// The red, green, blue and alpha bytes of one pixel, counted from the top-left corner.
    private func pixelBytes(of image: CGImage, x pixelColumn: Int, y pixelRow: Int) throws -> [UInt8] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -pixelColumn, y: pixelRow - image.height + 1, width: image.width, height: image.height))
        let pixelBytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return (0..<4).map { componentIndex in pixelBytes[componentIndex] }
    }

    /// The rows, top first, in which something is drawn left of `column`.
    private func drawnRows(of image: CGImage, leftOf column: Int) throws -> [Int] {
        try (0..<image.height).filter { pixelRow in
            try (0..<column).contains { pixelColumn in try pixelBytes(of: image, x: pixelColumn, y: pixelRow)[3] > 100 }
        }
    }

    /// The width the editor gives the marker `- ` of a top-level bullet item in the test's text size.
    private func bulletMarkerWidth() -> Int {
        let marker = ImageLineListMarker(indentation: "", marker: "-", spacing: " ")
        return Int(ImageLineListMarkerView.widths(of: marker, in: NoteTypography.standard.textFont(ofSize: 17)).total.rounded(.up))
    }

    // MARK: The owner's line

    func testTheOwnersLineOfNinePhotosIsOneBlockOfNinePicturesTwoHundredPointsWide() throws {
        let embeds = images(in: try imageLinePieces(Self.photoRow))
        XCTAssertEqual(embeds.count, 9)
        XCTAssertEqual(embeds.map(\.target), (1...9).map { number in "Photo_\(number).JPG" })
        XCTAssertTrue(embeds.allSatisfy { embed in embed.displaySize == EmbedDisplaySize(width: 200, height: nil) })
    }

    func testTheOwnersLineDrawsNinePicturesTwoHundredPointsWideThreeToARow() async throws {
        for number in 1...9 { try writeRedImage(named: "Photo_\(number).JPG") }
        try await rememberPictures(of: try imageLinePieces(Self.photoRow))

        // 700 points take three 200-point pictures and their gaps, 608 points; a fourth would need 812.
        let rendered = try firstFrame(of: Self.photoRow, width: 700)
        // Two to one, each picture is 100 points tall: three rows and their two gaps, under 4 points of padding each side.
        XCTAssertEqual(rendered.height, 3 * 100 + 2 * 4 + 2 * 4, "The nine pictures take three rows.")
        let spacing = Int(ImageLineFlowLayout.spacing)
        for row in 0..<3 {
            let middleY = 4 + row * (100 + spacing) + 50
            for column in 0..<3 {
                let left = column * (200 + spacing)
                XCTAssertTrue(try isRed(rendered, x: left + 2, y: middleY), "Picture \(row * 3 + column + 1) starts at \(left) points.")
                XCTAssertTrue(try isRed(rendered, x: left + 197, y: middleY), "Picture \(row * 3 + column + 1) is 200 points wide.")
                XCTAssertFalse(try isRed(rendered, x: left + 201, y: middleY), "A gap follows picture \(row * 3 + column + 1).")
            }
            XCTAssertFalse(try isRed(rendered, x: 650, y: middleY), "No fourth picture in row \(row + 1).")
        }
    }

    func testTheSourceShowsWhileTheCursorIsOnTheLineAndThePicturesOtherwise() {
        let text = "## Photos\n" + Self.photoRow + "\nAfter"
        let source = text as NSString
        let lineRange = source.range(of: Self.photoRow)
        // The blocks as the editor keeps them, and the ones it conceals under their views for a selection.
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        let entries = zip(blocks, LivePreviewBlockKey.keys(for: blocks)).map { block, key in LivePreviewBlockEntry(block: block, range: block.range, key: key) }
        func concealed(cursorAt location: Int) -> [LivePreviewBlockEntry] {
            LivePreviewRenderedBlocks.concealedEntries(entries, in: source, selection: NSRange(location: location, length: 0),
                                                       propertiesSource: .afterEditSource(isShown: false))
        }
        let concealedElsewhere = concealed(cursorAt: 2)
        XCTAssertEqual(concealedElsewhere.count, 1, "The line is drawn as its pictures while the cursor is elsewhere.")
        XCTAssertEqual(concealedElsewhere.first?.range.location, lineRange.location)
        XCTAssertTrue(concealed(cursorAt: lineRange.location + 40).isEmpty, "The cursor on the line shows its source.")
        XCTAssertTrue(concealed(cursorAt: NSMaxRange(lineRange) - 1).isEmpty, "The cursor at the line's end shows its source.")
    }

    // MARK: The cursor on one embed (issue #102)

    /// Three two-to-one pictures, 300, 200 and 100 points wide, between two lines of text.
    private static let threePictures = "![[Left.png|300]] ![[Middle.png|200]] ![[Right.png|100]]"
    private static let threePicturesNote = "Intro\n\n" + threePictures + "\n\nAfter the pictures\n"

    /// The owner's screenshot showed the cursor on one photo of a row turning the whole row into its text. As in
    /// Obsidian, only the embed the cursor is in shows its source; the line's other pictures stay drawn, at their
    /// sizes and in their places among its text.
    func testTheCursorInTheSecondEmbedShowsItsSourceAndTheOtherEmbedsStayPictures() async throws {
        let (coordinator, textView, _) = try await makeEditorWithThreePictures()
        defer { withExtendedLifetime(coordinator) {} }
        let source = Self.threePicturesNote as NSString
        let (left, middle, right) = (source.range(of: "![[Left.png|300]]"), source.range(of: "![[Middle.png|200]]"), source.range(of: "![[Right.png|100]]"))
        moveCursor(to: NSRange(location: middle.location + 5, length: 0), in: textView, coordinator)

        XCTAssertFalse(isConcealedBlock(middle.location, in: textView), "The line shows its text.")
        XCTAssertTrue(showsSource(middle, in: textView), "The embed the cursor is in shows its source.")
        XCTAssertEqual(picture(at: left, in: textView)?.size, CGSize(width: 300, height: 150), "The first embed stays a picture at its width.")
        XCTAssertEqual(picture(at: right, in: textView)?.size, CGSize(width: 100, height: 50), "The third embed stays a picture at its width.")

        // In their places in the line: the first picture, then the second embed's source, then the third picture.
        let line = try laidOutLine(holding: middle.location, in: textView)
        // The line's characters are counted from its paragraph's start, the line's own.
        let lineStart = source.lineRange(for: middle).location
        func horizontalPosition(_ location: Int) -> CGFloat { line.locationForCharacter(at: location - lineStart).x }
        // TextKit shares the room between the embed's last two characters, so it ends after the last.
        let leftRoom = horizontalPosition(NSMaxRange(left)) - horizontalPosition(NSMaxRange(left) - 2)
        XCTAssertEqual(leftRoom, 300 + 2 * InlinePictureLayout.horizontalPadding, accuracy: 1,
                       "The first picture's room is as wide as it.")
        XCTAssertGreaterThan(horizontalPosition(middle.location), 300, "The source follows the first picture.")
        XCTAssertGreaterThan(horizontalPosition(NSMaxRange(right) - 2), horizontalPosition(NSMaxRange(middle)), "The third picture follows the source.")
        XCTAssertTrue(NSLocationInRange(NSMaxRange(right) - 1 - lineStart, line.characterRange), "The three share one line.")
        XCTAssertGreaterThanOrEqual(line.typographicBounds.height, 150, "The line is as tall as its tallest picture.")
        // Drawn: a row through the pictures' lower halves is red for 400 points, the first and third pictures.
        let redPoints = try redPointsAcrossTheLine(holding: middle.location, belowBaselineBy: -20, in: textView)
        XCTAssertEqual(Double(redPoints), 400, accuracy: 6, "The first and third pictures are drawn, the second is text.")
    }

    /// Moving the cursor off the line draws every picture again in the line's view.
    func testTheCursorLeavingTheLineDrawsEveryPictureAgain() async throws {
        let (coordinator, textView, _) = try await makeEditorWithThreePictures()
        defer { withExtendedLifetime(coordinator) {} }
        let source = Self.threePicturesNote as NSString
        let middle = source.range(of: "![[Middle.png|200]]")
        moveCursor(to: NSRange(location: middle.location + 5, length: 0), in: textView, coordinator)
        XCTAssertNotNil(picture(at: source.range(of: "![[Left.png|300]]"), in: textView))
        moveCursor(to: NSRange(location: source.range(of: "After").location, length: 0), in: textView, coordinator)
        XCTAssertTrue(isConcealedBlock(middle.location, in: textView), "The line is drawn by its view again.")
        let storage = try XCTUnwrap(textView.textStorage)
        var drawnPictures = 0
        storage.enumerateAttribute(ConcealedReplacement.pictureAttributeKey, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { drawnPictures += 1 }
        }
        XCTAssertEqual(drawnPictures, 0, "No picture is left among the text.")
        try await awaitConditionAfterLayout { self.blockViews(in: textView).count == 1 }
    }

    /// The right arrow walks through the line embed by embed: wherever the cursor is, exactly the embed it is in
    /// shows its source, and the others are pictures.
    func testTheArrowKeysWalkThroughTheLineEmbedByEmbed() async throws {
        let (coordinator, textView, _) = try await makeEditorWithThreePictures()
        defer { withExtendedLifetime(coordinator) {} }
        let source = Self.threePicturesNote as NSString
        let embeds = ["![[Left.png|300]]", "![[Middle.png|200]]", "![[Right.png|100]]"].map { embed in source.range(of: embed) }
        moveCursor(to: NSRange(location: embeds[0].location, length: 0), in: textView, coordinator)
        var shownInOrder: [Int] = []
        while textView.selectedRange().location <= NSMaxRange(embeds[2]) {
            let cursor = textView.selectedRange().location
            let shown = embeds.indices.filter { index in showsSource(embeds[index], in: textView) }
            let expected = embeds.indices.filter { index in cursor >= embeds[index].location && cursor <= NSMaxRange(embeds[index]) }
            XCTAssertEqual(shown, expected, "At \(cursor) the embed the cursor is in shows its source.")
            for index in embeds.indices where !expected.contains(index) {
                XCTAssertNotNil(picture(at: embeds[index], in: textView), "At \(cursor) embed \(index + 1) is a picture.")
            }
            if let index = shown.first, shownInOrder.last != index { shownInOrder.append(index) }
            textView.moveRight(nil)
            coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        }
        XCTAssertEqual(shownInOrder, [0, 1, 2], "Each embed shows its source in turn.")
    }

    /// Typing in the source the cursor shows edits that embed, and the line's other embeds stay pictures.
    func testTypingInTheShownSourceEditsThatEmbed() async throws {
        let (coordinator, textView, _) = try await makeEditorWithThreePictures()
        defer { withExtendedLifetime(coordinator) {} }
        let source = Self.threePicturesNote as NSString
        let width = source.range(of: "200]]")
        moveCursor(to: NSRange(location: width.location, length: 3), in: textView, coordinator)
        textView.insertText("150", replacementRange: textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        let edited = textView.string as NSString
        XCTAssertTrue(textView.string.contains("![[Left.png|300]] ![[Middle.png|150]] ![[Right.png|100]]"), textView.string)
        XCTAssertTrue(showsSource(edited.range(of: "![[Middle.png|150]]"), in: textView), "The edited embed still shows its source.")
        XCTAssertEqual(picture(at: edited.range(of: "![[Left.png|300]]"), in: textView)?.size.width, 300)
        XCTAssertEqual(picture(at: edited.range(of: "![[Right.png|100]]"), in: textView)?.size.width, 100)
    }

    /// Text between the pictures shows as text, and a list item's marker as it did, while one embed shows its source.
    func testTextBetweenThePicturesAndAListMarkerShowAsBefore() async throws {
        try writeRedImage(named: "Left.png")
        try writeRedImage(named: "Right.png")
        let line = "- ![[Left.png|100]] and then ![[Right.png|100]]"
        try await rememberPictures(of: try imageLinePieces(line))
        let note = "Intro\n\n" + line + "\n\nAfter\n"
        let (coordinator, textView, _) = try await makeEditor(text: note)
        defer { withExtendedLifetime(coordinator) {} }
        let source = note as NSString
        let right = source.range(of: "![[Right.png|100]]")
        moveCursor(to: NSRange(location: right.location + 4, length: 0), in: textView, coordinator)
        XCTAssertTrue(showsSource(right, in: textView))
        XCTAssertEqual(picture(at: source.range(of: "![[Left.png|100]]"), in: textView)?.size, CGSize(width: 100, height: 50))
        XCTAssertTrue(showsSource(source.range(of: "and then"), in: textView), "The text between the pictures shows.")
        XCTAssertTrue(showsSource(NSRange(location: source.range(of: "- ![[").location, length: 1), in: textView),
                      "The list marker shows as written while the cursor is on its line, as before.")
    }

    // MARK: Editor helpers

    private func makeEditorWithThreePictures() async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, NSScrollView) {
        for name in ["Left.png", "Middle.png", "Right.png"] { try writeRedImage(named: name) }
        try await rememberPictures(of: try imageLinePieces(Self.threePictures))
        let editor = try await makeEditor(text: Self.threePicturesNote)
        try await awaitConditionAfterLayout { self.blockViews(in: editor.1).count == 1 }
        return editor
    }

    /// A Mac Live Preview editor of `text` in the test's vault, whose embeds are found where their targets say,
    /// in a window with the note's keyboard focus, as after a click in it.
    private func makeEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, NSScrollView) {
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = environment()
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        textView.frame.size.width = 760
        window.showInvisibly()
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView, scrollView)
    }

    private func moveCursor(to selection: NSRange, in textView: NSTextView, _ coordinator: NativeMarkdownEditor.Coordinator) {
        textView.setSelectedRange(selection)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
    }

    private func awaitConditionAfterLayout(_ condition: () -> Bool) async throws {
        try await waitUntil(timeoutSeconds: 10) {
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            return condition()
        }
    }

    private func blockViews(in textView: NSTextView) -> [NSView] {
        textView.subviews.filter { subview in subview is NSHostingView<AnyView> }
    }

    /// Whether the line at `location` is concealed under a block's view.
    private func isConcealedBlock(_ location: Int, in textView: NSTextView) -> Bool {
        ((textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.maximumLineHeight ?? 0) == 0.01
    }

    /// Whether every character of `range` is text of the note's size, none hidden or under a picture.
    private func showsSource(_ range: NSRange, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, range.location != NSNotFound else { return false }
        return (range.location..<NSMaxRange(range)).allSatisfy { location in
            ((storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0) > 5
                && storage.attribute(ConcealedReplacement.pictureAttributeKey, at: location, effectiveRange: nil) == nil
        }
    }

    /// The picture drawn over all of `range`, when one is.
    private func picture(at range: NSRange, in textView: NSTextView) -> InlinePictureLayout? {
        guard let storage = textView.textStorage, range.location != NSNotFound else { return nil }
        var pictureRange = NSRange(location: NSNotFound, length: 0)
        let layout = storage.attribute(ConcealedReplacement.pictureAttributeKey, at: range.location, longestEffectiveRange: &pictureRange,
                                       in: NSRange(location: 0, length: storage.length)) as? InlinePictureLayout
        return pictureRange == range ? layout : nil
    }

    private func layoutFragment(holding location: Int, in textView: NSTextView) throws -> NSTextLayoutFragment {
        let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let contentStorage = try XCTUnwrap(textLayoutManager.textContentManager as? NSTextContentStorage)
        let textLocation = try XCTUnwrap(contentStorage.location(contentStorage.documentRange.location, offsetBy: location))
        return try XCTUnwrap(textLayoutManager.textLayoutFragment(for: textLocation))
    }

    /// The laid-out line holding `location`, its character ranges counted in its paragraph's line, which here starts the
    /// paragraph at the line's start.
    private func laidOutLine(holding location: Int, in textView: NSTextView) throws -> NSTextLineFragment {
        let fragment = try layoutFragment(holding: location, in: textView)
        let paragraphStart = (textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
        return try XCTUnwrap(fragment.textLineFragments.first { line in NSLocationInRange(location - paragraphStart, line.characterRange) })
    }

    /// How many points of a row `offset` points below the baseline of the line holding `location` are red, drawn
    /// by the line's layout fragment one pixel a point.
    private func redPointsAcrossTheLine(holding location: Int, belowBaselineBy offset: CGFloat, in textView: NSTextView) throws -> Int {
        let fragment = try layoutFragment(holding: location, in: textView)
        let line = try laidOutLine(holding: location, in: textView)
        let width = Int(fragment.layoutFragmentFrame.width) + 20, height = Int(fragment.layoutFragmentFrame.height) + 20
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            fragment.draw(at: .zero, in: context)
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = try XCTUnwrap(context.makeImage())
        let row = Int(line.typographicBounds.minY + line.glyphOrigin.y + offset)
        return try (0..<width).filter { column in try isRed(image, x: column, y: row) }.count
    }

    // MARK: Other forms

    func testAWidthAndHeightFitsThePictureInsideBoth() async throws {
        try writeRedImage(named: "Square.png", width: 40, height: 40)
        try writeRedImage(named: "Wide.png")
        let line = "![[Square.png|200x150]] ![[Wide.png|200x150]]"
        let pieces = try imageLinePieces(line)
        XCTAssertEqual(images(in: pieces).map(\.displaySize), [EmbedDisplaySize(width: 200, height: 150), EmbedDisplaySize(width: 200, height: 150)])
        try await rememberPictures(of: pieces)

        let rendered = try firstFrame(of: line, width: 700)
        // The square is held to 150 points by its height; the two-to-one picture, 200 by 100, by its width.
        XCTAssertEqual(rendered.height, 150 + 2 * 4)
        XCTAssertTrue(try isRed(rendered, x: 147, y: 4 + 75))
        XCTAssertFalse(try isRed(rendered, x: 152, y: 4 + 75), "The square is 150 points wide.")
        // The rows' pieces stand on its bottom edge.
        XCTAssertTrue(try isRed(rendered, x: 154 + 100, y: 4 + 150 - 50))
        XCTAssertFalse(try isRed(rendered, x: 154 + 100, y: 4 + 20), "The wide picture is 100 points tall, at the row's bottom.")
        XCTAssertTrue(try isRed(rendered, x: 154 + 197, y: 4 + 100))
    }

    func testAMarkdownImageWithAWidthInItsTextIsAPictureOfTheLine() async throws {
        try writeRedImage(named: "Wide.png")
        let line = "![Wide|200](Wide.png) ![[Wide.png|100]]"
        let pieces = try imageLinePieces(line)
        let embeds = images(in: pieces)
        XCTAssertEqual(embeds.map(\.isWiki), [false, true])
        XCTAssertEqual(embeds.map(\.displayWidth), [200, 100])
        try await rememberPictures(of: pieces)

        let rendered = try firstFrame(of: line, width: 700)
        XCTAssertEqual(rendered.height, 100 + 2 * 4)
        XCTAssertTrue(try isRed(rendered, x: 197, y: 4 + 50))
        XCTAssertTrue(try isRed(rendered, x: 204 + 97, y: 4 + 75))
        XCTAssertFalse(try isRed(rendered, x: 204 + 102, y: 4 + 75), "The wiki embed is 100 points wide.")
    }

    func testTextAndPicturesOnOneLineKeepTheirOrder() throws {
        let pieces = try imageLinePieces("Before ![[a.png|100]] between **bold** ![alt|50](b.jpg) after")
        XCTAssertEqual(pieces.count, 5)
        guard pieces.count == 5, case .text(let before) = pieces[0], case .image(let first) = pieces[1], case .text(let between) = pieces[2],
              case .image(let second) = pieces[3], case .text(let after) = pieces[4] else { return XCTFail("Text, picture, text, picture, text: \(pieces)") }
        XCTAssertEqual([before, between, after], ["Before", "between **bold**", "after"])
        XCTAssertEqual(first.target, "a.png")
        XCTAssertEqual(first.range, NSRange(location: 7, length: 14))
        XCTAssertEqual(second.target, "b.jpg")
        XCTAssertEqual(second.displayWidth, 50)
    }

    func testTheHeightEstimatePlacesThePicturesInRows() throws {
        let pieces = try imageLinePieces(Self.photoRow)
        // 200 by 150 each, three to a row of 700 points: three rows, two gaps, the block's padding.
        XCTAssertEqual(LivePreviewBlockHeightEstimate.height(of: LivePreviewBlockScanner.blocks(in: Self.photoRow as NSString)[0], columnWidth: 700),
                       3 * 150 + 2 * 4 + 8)
        XCTAssertEqual(LivePreviewImageLineView.estimatedHeight(of: pieces, columnWidth: 200), 9 * 150 + 8 * 4 + 8, "One to a row in a narrow column.")
    }

    // MARK: List items

    /// The owner's photos in a bulleted list, as Obsidian draws them: the bullet, then the pictures beside it.
    func testABulletItemDrawsItsBulletOnTheRowsBottomAndItsPicturesBesideIt() async throws {
        try writeRedImage(named: "First.png")
        try writeRedImage(named: "Second.png")
        let line = "- ![[First.png|200]] ![[Second.png|200]]"
        try await rememberPictures(of: try imageLinePieces(line))
        let markerWidth = bulletMarkerWidth()
        XCTAssertGreaterThan(markerWidth, 8, "A bullet and a space take some room.")

        let rendered = try firstFrame(of: line, width: 700)
        // Each picture is 200 by 100 points; the row has 4 points of padding above and below.
        XCTAssertEqual(rendered.height, 100 + 2 * 4)
        XCTAssertTrue(try isRed(rendered, x: markerWidth + 2, y: 4 + 50), "The first picture starts after the marker.")
        XCTAssertTrue(try isRed(rendered, x: markerWidth + 197, y: 4 + 50))
        XCTAssertTrue(try isRed(rendered, x: markerWidth + 204 + 2, y: 4 + 50), "The second picture is beside the first.")
        let bulletRows = try drawnRows(of: rendered, leftOf: markerWidth - 1)
        XCTAssertFalse(bulletRows.isEmpty, "The bullet is drawn.")
        XCTAssertGreaterThan(bulletRows.min() ?? 0, 4 + 100 - 24, "The bullet stands on the row's bottom, as text does: \(bulletRows)")
        XCTAssertLessThanOrEqual(bulletRows.max() ?? 0, 4 + 100)
    }

    func testANumberedItemsPicturesWrapUnderTheFirstPictureNotUnderTheNumber() async throws {
        try writeRedImage(named: "First.png")
        try writeRedImage(named: "Second.png")
        let line = "1. ![[First.png|200]] ![[Second.png|200]]"
        try await rememberPictures(of: try imageLinePieces(line))
        let marker = ImageLineListMarker(indentation: "", marker: "1.", spacing: " ")
        let markerWidth = Int(ImageLineListMarkerView.widths(of: marker, in: NoteTypography.standard.textFont(ofSize: 17)).total.rounded(.up))

        // Room for one picture beside the number: the second wraps onto a row of its own.
        let rendered = try firstFrame(of: line, width: CGFloat(markerWidth + 300))
        XCTAssertEqual(rendered.height, 2 * 100 + 4 + 2 * 4)
        for row in 0..<2 {
            let middleY = 4 + row * 104 + 50
            XCTAssertTrue(try isRed(rendered, x: markerWidth + 2, y: middleY), "Picture \(row + 1) starts after the number.")
            XCTAssertFalse(try isRed(rendered, x: markerWidth - 3, y: middleY), "Nothing red under the number in row \(row + 1).")
        }
        let numberRows = try drawnRows(of: rendered, leftOf: markerWidth - 1)
        XCTAssertFalse(numberRows.isEmpty, "The number is drawn.")
        XCTAssertTrue(numberRows.allSatisfy { pixelRow in pixelRow < 4 + 100 + 1 }, "The number is on the first row only: \(numberRows)")
    }

    func testTheHeightEstimateOfAListItemLeavesRoomForItsMarker() throws {
        let pieces = try imageLinePieces("- " + Self.photoRow)
        // 700 points less the marker take three 200-point pictures a row, as without it; 620 less the marker take two.
        XCTAssertEqual(LivePreviewImageLineView.estimatedHeight(of: pieces, columnWidth: 700), 3 * 150 + 2 * 4 + 8)
        XCTAssertEqual(LivePreviewImageLineView.estimatedHeight(of: pieces, columnWidth: 620), 5 * 150 + 4 * 4 + 8)
    }

    // MARK: Tables and callouts

    /// A table or callout is drawn by the reading view's renderer, which draws a picture inside text. A Markdown
    /// image there (`![Done|100](Photos/Done.png)`) is looked up in the vault as a Wikilink embed is: its path was
    /// read as a web address, and nothing was drawn.
    func testATablesWikiAndMarkdownImagesBecomePicturesOfTheVaultWithTheirSizes() async throws {
        let table = "| Before | After |\n| --- | --- |\n| ![[Raw.png\\|100]] | ![Done\\|120](Photos/Done.png) `![](Code.png)` |\n"
        var looked: [String] = []
        let resolvingEverything = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
            resolve: { target, isWiki in looked.append("\(target)|\(isWiki)"); return try? VaultPath(target) },
            open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let preparation = await LivePreviewText.preparedResolvingEmbeds(table, environment: resolvingEverything)
        XCTAssertEqual(looked.sorted(), ["Photos/Done.png|false", "Raw.png|true"], "The embed in code is not looked up.")
        XCTAssertFalse(preparation.hasUnresolvedEmbeds)
        let rawImage = PreviewImageFragment.url(for: vault.appendingPathComponent("Raw.png"), displaySize: EmbedDisplaySize(width: 100, height: nil), version: 0)
        let doneImage = PreviewImageFragment.url(for: vault.appendingPathComponent("Photos/Done.png"), displaySize: EmbedDisplaySize(width: 120, height: nil), version: 0)
        XCTAssertTrue(preparation.markdown.contains("![Raw](\(GraphiteOpenLink.markdownDestination(rawImage)))"), preparation.markdown)
        XCTAssertTrue(preparation.markdown.contains("![Done](\(GraphiteOpenLink.markdownDestination(doneImage)))"), preparation.markdown)
        XCTAssertTrue(preparation.markdown.contains("`![](Code.png)`"), "Code keeps its text.")

        let resolvingNothing = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
            resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let unresolved = await LivePreviewText.preparedResolvingEmbeds("> [!tip]\n> ![Done|120](Photos/Done.png)\n", environment: resolvingNothing)
        XCTAssertTrue(unresolved.hasUnresolvedEmbeds, "A Markdown image not found yet is looked up again when the index changes.")
        XCTAssertTrue(LivePreviewText.hasWikiEmbed("![Done](Photos/Done.png)"))
        XCTAssertFalse(LivePreviewText.hasWikiEmbed("A [link](Note.md) and [[a Wikilink]]"))
    }

    // MARK: Lines that keep their drawing

    func testLinesWhoseImagesStayInlineAreNotLinesOfImages() {
        for line in ["- [ ] ![[a.png|100]] ![[b.png|100]]", "# Title ![[a.png|100]]", "> ![[a.png|100]] ![[b.png|100]]",
                     "    ![[a.png|100]] ![[b.png|100]]", "`![[a.png|100]]` and `![[b.png]]`", "![](https://example.com/a.png) ![](https://example.com/b.png)",
                     "![[Other note]] ![[Second note]]", "Plain text with [[a link]]"] {
            let blocks = LivePreviewBlockScanner.blocks(in: line as NSString)
            XCTAssertFalse(blocks.contains { block in if case .imageLine = block.kind { true } else { false } }, line)
        }
        // A single image alone on its line is still an embed block of its own.
        guard case .embed = LivePreviewBlockScanner.blocks(in: "![[a.png|200]]" as NSString).first?.kind else { return XCTFail("A lone image is an embed block.") }
    }
}
