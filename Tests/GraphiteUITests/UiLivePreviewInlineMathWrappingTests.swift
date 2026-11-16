/**
 * File: UiLivePreviewInlineMathWrappingTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: Live Preview's own text draws a long inline formula in pieces that wrap after its operators, as the
 *              reading view and tables do, while the cursor, copying and Read Aloud still see one formula (issue #109).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import AppKit
import GraphiteCore
import Textual
@testable import GraphiteUI
import GraphiteTestSupport

/// A long `$…$` in a paragraph was one image whose room the line kept whole: it never wrapped, and ran past the
/// column's edge, where Obsidian breaks it after `+` or `=`.
@MainActor
final class UiLivePreviewInlineMathWrappingTests: XCTestCase {
    /// The owner's table cell's formula, longer, as a paragraph might hold it.
    private static let longLatex = #"(C_{jb} \cdot L_A + C_{jsw})W + C_j \cdot W \cdot L/2 + C_{ox} \cdot W \cdot L = C_{total}"#
    private static let paragraph = "The capacitance is $\(longLatex)$ in this region.\n"

    private let styler = MarkdownTextStyler(configuration: EditorConfiguration(mode: .livePreview, textSize: 17), accentColor: .systemBlue,
                                            drawsConcealedReplacements: true)

    private struct LaidOutText {
        let textStorage: NSTextStorage
        let fragments: [NSTextLayoutFragment]
        let containerWidth: CGFloat
    }

    private func layOut(_ text: String, width: CGFloat, revealedMarkup: RevealedMarkup? = nil,
                        restyle: (NSTextStorage) -> Void = { _ in }) throws -> LaidOutText {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let fragmentMaker = PiecesFragmentMaker()
        layoutManager.delegate = fragmentMaker
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = NSTextContainer(size: CGSize(width: width, height: 0))
        let textStorage = try XCTUnwrap(contentStorage.textStorage)
        textStorage.setAttributedString(NSAttributedString(string: text))
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: revealedMarkup,
                           concealedBlocks: [])
        restyle(textStorage)
        var fragments: [NSTextLayoutFragment] = []
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            fragments.append(fragment)
            return true
        }
        return withExtendedLifetime(fragmentMaker) { LaidOutText(textStorage: textStorage, fragments: fragments, containerWidth: width) }
    }

    /// Each drawn formula or piece of one in the first paragraph: its source range, its room's left edge and
    /// width, and the line it is drawn on.
    private func rooms(in laidOut: LaidOutText) throws -> [(range: NSRange, start: CGFloat, width: CGFloat, lineIndex: Int)] {
        let fragment = try XCTUnwrap(laidOut.fragments.first)
        var rooms: [(range: NSRange, start: CGFloat, width: CGFloat, lineIndex: Int)] = []
        let storage = laidOut.textStorage
        storage.enumerateAttribute(ConcealedReplacement.mathAttributeKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let layout = value as? InlineMathLayout,
                  let lineIndex = fragment.textLineFragments.firstIndex(where: { line in NSLocationInRange(NSMaxRange(range) - 2, line.characterRange) })
            else { return }
            let line = fragment.textLineFragments[lineIndex]
            rooms.append((range, line.typographicBounds.minX + line.locationForCharacter(at: NSMaxRange(range) - 2).x, layout.roomWidth, lineIndex))
        }
        return rooms
    }

    // MARK: Wrapping

    func testALongFormulaInAParagraphWrapsAfterItsOperatorsAndEveryLineFitsTheColumn() throws {
        let source = Self.paragraph as NSString
        let formula = source.range(of: "$" + Self.longLatex + "$")
        let wholeWidth = try XCTUnwrap(InlineMathRendering.metrics(for: Self.longLatex, fontSize: 17 * 1.2)).width
        let laidOut = try layOut(Self.paragraph, width: 300)
        XCTAssertGreaterThan(wholeWidth, laidOut.containerWidth, "Drawn whole, the formula is wider than the column.")
        let rooms = try rooms(in: laidOut)
        XCTAssertGreaterThan(rooms.count, 5, "The formula is drawn in pieces.")
        XCTAssertEqual(rooms.first?.range.location, formula.location, "The first piece starts at the opening dollar.")
        XCTAssertEqual(rooms.last.map { room in NSMaxRange(room.range) }, NSMaxRange(formula), "The last piece ends at the closing dollar.")
        XCTAssertGreaterThanOrEqual(Set(rooms.map(\.lineIndex)).count, 3, "The formula takes several lines.")
        for room in rooms {
            XCTAssertLessThanOrEqual(room.start + room.width, laidOut.containerWidth + 0.5,
                                     "\(source.substring(with: room.range)) fits the text container on line \(room.lineIndex + 1).")
        }
        // Each piece but the last ends after its operator and the space after it, where the line breaks.
        for room in rooms.dropLast() {
            let piece = source.substring(with: room.range)
            XCTAssertTrue(piece.hasSuffix("+ ") || piece.hasSuffix("\\cdot ") || piece.hasSuffix("= "), piece)
        }
        let fragment = try XCTUnwrap(laidOut.fragments.first)
        for (lineIndex, line) in fragment.textLineFragments.enumerated() {
            let lineEnd = line.typographicBounds.minX + line.locationForCharacter(at: NSMaxRange(line.characterRange)).x
            XCTAssertLessThanOrEqual(lineEnd, laidOut.containerWidth + 0.5, "Line \(lineIndex + 1) fits the text container.")
        }
    }

    func testThePiecesAreAsWideAsTheFormulaDrawnWholeAndKeepRoomOnlyAtItsEnds() throws {
        let source = Self.paragraph as NSString
        let pieces = try XCTUnwrap(LivePreviewInlineMathPieces.pieces(ofFormulaAt: source.range(of: "$" + Self.longLatex + "$"), in: source))
        // As the reading view cuts it: after `\cdot`, `+` and `=` at the outer level, never inside the brackets' scripts.
        XCTAssertEqual(pieces.map { piece in source.substring(with: piece.range) },
                       [#"$(C_{jb} \cdot "#, "L_A + ", "C_{jsw})W + ", #"C_j \cdot "#, #"W \cdot "#, "L/2 + ", #"C_{ox} \cdot "#, #"W \cdot "#, "L = ",
                        "C_{total}$"])
        XCTAssertEqual(pieces.last?.latex, " C_{total}")
        XCTAssertEqual(pieces.first?.latex, #"(C_{jb} \cdot\>"#, "A piece ends with the space TeX puts after its operator.")
        let wholeWidth = try XCTUnwrap(InlineMathRendering.metrics(for: Self.longLatex, fontSize: 17 * 1.2)).width
        let rooms = try rooms(in: try layOut(Self.paragraph, width: 2_000))
        XCTAssertEqual(rooms.reduce(0) { width, room in width + room.width }, wholeWidth + 2 * InlineMathLayout.horizontalPadding, accuracy: 0.5)
        // On one line the pieces meet: each room starts where the one before it ends.
        for (previous, next) in zip(rooms, rooms.dropFirst()) {
            XCTAssertEqual(next.lineIndex, previous.lineIndex)
            XCTAssertEqual(next.start, previous.start + previous.width, accuracy: 0.5)
        }
    }

    func testFormulasWithoutABreakOrThatCannotBeCutSafelyStayWhole() throws {
        func pieceTexts(_ formula: String) -> [String]? {
            let source = "Text \(formula) text" as NSString
            return LivePreviewInlineMathPieces.pieces(ofFormulaAt: source.range(of: formula), in: source)?.map { piece in source.substring(with: piece.range) }
        }
        XCTAssertNil(pieceTexts("$$a + b$$"), "Display math is not inline math.")
        for whole in ["$k_n$", #"$\frac{a + b}{c}$"#, #"$\left( a + b \right)$"#, #"$\bf a + b$"#, "$a +b$"] {
            XCTAssertNil(pieceTexts(whole), whole)
        }
        XCTAssertEqual(pieceTexts("$a+b=c$"), ["$a+", "b=", "c$"], "Written without spaces, the pieces end at their operators.")
        XCTAssertEqual(pieceTexts("$a +b + c$"), ["$a +b + ", "c$"], "A piece whose room would follow a space is drawn with the next.")
        // A formula the typesetter cannot read stays its source, as before.
        let laidOut = try layOut(#"See $\notacommand + x$ here"# + "\n", width: 600)
        XCTAssertTrue(try rooms(in: laidOut).isEmpty)
    }

    // MARK: One formula for the cursor, copying and Read Aloud

    func testTheCursorInTheFormulaShowsItsWholeSource() throws {
        let source = Self.paragraph as NSString
        let formula = source.range(of: "$" + Self.longLatex + "$")
        let cursorInFormula = RevealedMarkup(selection: NSRange(location: formula.location + 30, length: 0), in: source)
        let laidOut = try layOut(Self.paragraph, width: 300, revealedMarkup: cursorInFormula)
        XCTAssertTrue(try rooms(in: laidOut).isEmpty, "No piece is drawn while the cursor is in the formula.")
        for location in formula.location..<NSMaxRange(formula) {
            let font = try XCTUnwrap(laidOut.textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
            XCTAssertGreaterThan(font.pointSize, 5, "Every character of the source shows.")
        }
    }

    func testCopyingAcrossTheFormulaGivesItsSourceOnce() throws {
        // The editor's own text view, which copies a selection as plain text.
        let textView = try XCTUnwrap(MarkdownMacTextView.makeScrollableTextView().documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.string = Self.paragraph
        styler.applyStyles(to: try XCTUnwrap(textView.textStorage), editedRange: NSRange(location: 0, length: 0), restyleEverything: true,
                           revealedMarkup: nil, concealedBlocks: [])
        textView.setSelectedRange(NSRange(location: 0, length: (Self.paragraph as NSString).length))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("UiLivePreviewInlineMathWrappingTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertEqual(copied, Self.paragraph)
        XCTAssertEqual(copied.components(separatedBy: "C_{total}").count, 2, "The formula is copied once.")
    }

    func testReadAloudReadsTheFormulaAsOneEquation() throws {
        let source = Self.paragraph as NSString
        let document = try ReadAloudDocument.markdown(Self.paragraph, mathematicalSpeech: { _ in "an equation" })
        let equations = document.passages.flatMap(\.spans).filter(\.isEquation)
        XCTAssertEqual(equations.count, 1)
        XCTAssertEqual(equations.first?.sourceRange, source.range(of: "$" + Self.longLatex + "$"))
    }

    // MARK: Short formulas

    /// A formula short enough for its line is drawn in pieces too, and looks as it did drawn whole: the same room,
    /// and the same pixels but for anti-aliasing at the seams.
    func testAShortFormulaInPiecesLooksAsItDidWhole() throws {
        let text = "Energy $E = mc^2 + x \\cdot y$ here\n"
        let formula = (text as NSString).range(of: "$E = mc^2 + x \\cdot y$")
        let inPieces = try layOut(text, width: 600)
        XCTAssertEqual(try rooms(in: inPieces).count, 4, "The formula is drawn in its four pieces.")
        let whole = try layOut(text, width: 600) { textStorage in
            for key in [NSAttributedString.Key.kern, .baselineOffset, ConcealedReplacement.mathAttributeKey] {
                textStorage.removeAttribute(key, range: formula)
            }
            guard let layout = self.styler.inlineMathLayout(for: (text as NSString).substring(with: formula), baseFont: self.styler.baseFont) else { return }
            self.styler.drawInlineMath(layout, over: formula, in: textStorage)
        }
        XCTAssertEqual(try rooms(in: whole).count, 1, "Drawn whole, as before.")
        let piecesImage = try drawing(of: inPieces), wholeImage = try drawing(of: whole)
        XCTAssertEqual(piecesImage.count, wholeImage.count)
        let differingPixels = zip(piecesImage, wholeImage).filter { piecePixel, wholePixel in abs(Int(piecePixel) - Int(wholePixel)) > 96 }.count
        let inkPixels = wholeImage.filter { pixel in pixel < 128 }.count
        XCTAssertGreaterThan(inkPixels, 100, "The formula is drawn.")
        XCTAssertLessThan(Double(differingPixels), Double(inkPixels) * 0.03, "\(differingPixels) of \(inkPixels) inked pixels differ.")
    }

    // MARK: Typing

    /// Typing in a long note of long formulas: each keystroke restyles its line, whose formulas are cut into pieces
    /// again, their pieces' sizes coming from the styler's cache. Measured 2026-11-12 on the Mac (Debug, 32 keystrokes
    /// in this note, three runs each): a keystroke's median 1.7 ms with the formulas drawn whole, 2.1 ms in pieces;
    /// styling the whole note 73 and 83 ms. The budget is one frame at 60 Hz.
    func testTypingInALongNoteOfLongFormulasStaysWithinItsBudget() async throws {
        let paragraphs = (1...300).map { number in "Paragraph \(number): the load is $\(Self.longLatex)$ and $a_\(number) + b \\cdot c = d$ here." }
        let note = paragraphs.joined(separator: "\n\n") + "\n"
        let vault = try TemporaryVault.make(prefix: "FormulaTyping", for: self).root
        try Data(note.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: EditorConfiguration(mode: .livePreview, textSize: 17))
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.string = note
        textView.delegate = coordinator
        coordinator.connect(textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil }
        window.contentView = scrollView
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        textView.frame.size.width = 700
        window.showInvisibly()
        let clock = ContinuousClock()
        let opening = clock.measure { coordinator.restyleEverything(in: textView) }
        textView.setSelectedRange(NSRange(location: NSMaxRange((note as NSString).range(of: "Paragraph 150:")), length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        var keystrokes: [Duration] = []
        for character in " with a long load" + " and more" + " words" {
            keystrokes.append(clock.measure {
                textView.insertText(String(character), replacementRange: textView.selectedRange())
                coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            })
        }
        withExtendedLifetime(coordinator) {}
        let milliseconds = keystrokes.map { duration in Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1_000 }.sorted()
        let median = milliseconds[milliseconds.count / 2]
        print("Typing in 300 paragraphs of long formulas: median \(median) ms, slowest \(milliseconds.last ?? 0) ms; styling the note \(opening)")
        XCTAssertLessThan(median, 16, "A keystroke restyles its line in \(median) ms.")
    }

    /// The first paragraph drawn in gray at twice its size, a byte a pixel.
    private func drawing(of laidOut: LaidOutText) throws -> [UInt8] {
        let fragment = try XCTUnwrap(laidOut.fragments.first)
        let scale: CGFloat = 2
        let width = Int(laidOut.containerWidth * scale), height = Int((fragment.layoutFragmentFrame.height + 20) * scale)
        var pixels = [UInt8](repeating: 255, count: width * height)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            fragment.draw(at: CGPoint(x: 0, y: 10), in: context)
            NSGraphicsContext.restoreGraphicsState()
        }
        return pixels
    }
}

/// Makes the fragments both editors make, which draw formulas over their hidden source.
private final class PiecesFragmentMaker: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        ConcealedReplacementLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
