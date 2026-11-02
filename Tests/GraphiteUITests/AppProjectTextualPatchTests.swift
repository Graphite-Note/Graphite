/**
 * File: AppProjectTextualPatchTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Regression tests for the patches Graphite carries in its vendored Textual and
 *              SwiftUIMath.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 01/11/2026
 */

import XCTest
import AppKit
import SwiftUI
import GraphiteCore
@testable import Textual
import SwiftUIMath

/// Regression tests for the patches Graphite carries in its vendored Textual
/// (Vendor/textual/GRAPHITE-PATCHES.md) and SwiftUIMath (Vendor/swiftui-math/GRAPHITE-PATCHES.md).
/// Upstream's own tests are not vendored.
@MainActor
final class AppProjectTextualPatchTests: XCTestCase {
    private static let objectReplacementCharacter: Character = "\u{FFFC}"

    private func inlineMathFormulas(in text: String) throws -> [String] {
        try PatternTokenizer(patterns: [.mathBlock, .mathInline]).tokenize(text)
            .filter { token in token.type == .mathInline }
            .compactMap(\.capturedContent)
    }

    /// How many formulas the Markdown has as attachments; a formula drawn in pieces counts once.
    private func mathAttachmentCount(inMarkdown markdown: String) throws -> Int {
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        return try parser.attributedString(for: markdown).runs.filter { run in
            run.textual.attachment.map { attachment in !attachment.continuesFormula } ?? false
        }.count
    }

    private func mathPieces(inMarkdown markdown: String) throws -> [MathAttachment] {
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        return try parser.attributedString(for: markdown).runs.compactMap { run in run.textual.attachment?.base as? MathAttachment }
    }

    // MARK: Patch 4, Obsidian's inline math delimiters

    func testInlineMathNeedsNoSpaceInsideTheDollarsAndNoDigitAfterTheClosingOne() throws {
        XCTAssertEqual(try inlineMathFormulas(in: "$x$"), ["x"])
        XCTAssertEqual(try inlineMathFormulas(in: "$x_1$, $x_2$"), ["x_1", "x_2"])
        XCTAssertEqual(try inlineMathFormulas(in: "It costs $5 and $10"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "$x$2"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "$ x$ and $x $"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "a \\$ sign: $\\$5$"), ["\\$5"])
    }

    func testPricesStayTextWhileFormulasBecomeAttachments() throws {
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: "It costs $5 and $10."), 0)
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: "Energy $E = mc^2$ and $k_n$."), 2)
    }

    // MARK: Patch 5, formulas that cannot be typeset stay as text

    func testUnparseableFormulaStaysAsItsSource() throws {
        XCTAssertTrue(MathAttachment.canTypeset("x^2"))
        XCTAssertFalse(MathAttachment.canTypeset("\\begin{notanenvironment}x\\end{notanenvironment}"))
        let markdown = "See $\\begin{notanenvironment}x\\end{notanenvironment}$ here."
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        XCTAssertEqual(String(try parser.attributedString(for: markdown).characters), markdown)
    }

    // MARK: Patch 3, inline math for other text views

    func testInlineMathRenderingMeasuresFormulasAndRejectsUnparseableOnes() {
        let metrics = InlineMathRendering.metrics(for: "x^2", fontSize: 17)
        XCTAssertGreaterThan(metrics?.width ?? 0, 0)
        XCTAssertGreaterThan(metrics?.ascent ?? 0, 0)
        XCTAssertNil(InlineMathRendering.metrics(for: "\\begin{notanenvironment}x\\end{notanenvironment}", fontSize: 17))
    }

    // MARK: Patch 1, math keeps its natural width

    func testReportedColoredRankFormulaBecomesDisplayMathAndDrawsInItsColor() throws {
        let formula = #"\color{#7852ee} A^{T}A:\mathbb{R}^{n}\to\mathbb{R}^{n},\qquad (A^{T}A)^{T}=A^{T}A, \qquad \operatorname{rank}(A^{T}A)=r."#
        for markdown in ["$$ " + formula + " $$", "$$\n" + formula + "\n$$"] {
            let prepared = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: false, paletteHexByName: [:])
            let parsed = try AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: [.math]).attributedString(for: prepared)
            let attachment = try XCTUnwrap(parsed.attachments().first?.base as? MathAttachment)
            XCTAssertEqual(attachment.displayStyle, .block)
            XCTAssertFalse(String(parsed.characters).contains("$$"), "The formula must not fall back to source text.")

            let renderer = ImageRenderer(content: attachment.body.font(.system(size: 22)).padding(12).background(.black).environment(\.colorScheme, .dark))
            let renderedImage = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: renderedImage)
            var purplePixelsByHalf = [0, 0]
            for verticalPosition in 0..<bitmap.pixelsHigh {
                for horizontalPosition in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: horizontalPosition, y: verticalPosition)?.usingColorSpace(.deviceRGB) else { continue }
                    if abs(color.redComponent - 120.0 / 255) < 0.08,
                       abs(color.greenComponent - 82.0 / 255) < 0.08,
                       abs(color.blueComponent - 238.0 / 255) < 0.08 {
                        purplePixelsByHalf[horizontalPosition < bitmap.pixelsWide / 2 ? 0 : 1] += 1
                    }
                }
            }
            XCTAssertGreaterThan(purplePixelsByHalf[0], 30)
            XCTAssertGreaterThan(purplePixelsByHalf[1], 30, "The declaration colors the entire formula, including rank.")
            if let outputPath = ProcessInfo.processInfo.environment["GRAPHITE_MATH_PREVIEW_PATH"] {
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    func testColorDeclarationsRespectBraceScopeAndEscapedBraces() {
        XCTAssertEqual(LaTeXCompatibility.normalized(#"a+{\color{#7852ee}b+c}+d"#), #"a+{\textcolor{#7852ee}{b+c}}+d"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\color{#7852ee}a+{\color{#ff0000}b}+c"#), #"\textcolor{#7852ee}{a+{\textcolor{#ff0000}{b}}+c}"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\color{#7852ee}\{a\}+b"#), #"\textcolor{#7852ee}{\{a\}+b}"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\textcolor{#7852ee}{a}+b"#), #"\textcolor{#7852ee}{a}+b"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\operatorname{rank}(A)"#), #"\mathrm{rank}(A)"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\operatorname*{argmax}_x f(x)"#), #"\operatorname*{argmax}_x f(x)"#)
    }

    func testInlineMathKeepsItsNaturalWidthInANarrowProposal() {
        let attachment = MathAttachment(latex: "k_n", style: .inline)
        let environment = TextEnvironmentValues()
        let naturalSize = attachment.sizeThatFits(.unspecified, in: environment)
        XCTAssertGreaterThan(naturalSize.width, 0)
        let narrowSize = attachment.sizeThatFits(ProposedViewSize(width: naturalSize.width / 2, height: nil), in: environment)
        XCTAssertEqual(narrowSize, naturalSize)
    }

    // MARK: SwiftUIMath patch 1, a formula is not broken by its rounded frame

    /// `Math` typesets its formula again at the width of its canvas. A canvas a fraction of
    /// a point narrower than the formula, as frames rounded to whole pixels are, broke `g_m`
    /// into `g` over `m`, and the reading view showed only the subscript (Vendor/swiftui-math/
    /// GRAPHITE-PATCHES.md). Each formula is drawn in a frame of its own height, 0.4 points
    /// narrower than it: everything must be drawn on one line, around the frame.
    func testFormulaInAFrameNarrowerByAFractionOfAPointStaysOnOneLine() throws {
        let fontSize: CGFloat = 22
        for latex in ["g_m", "r_o", "V_A", "V_{ov}", "k_n"] {
            let metrics = try XCTUnwrap(InlineMathRendering.metrics(for: latex, fontSize: fontSize))
            let height = metrics.ascent + metrics.descent
            let narrowMetrics = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: fontSize, fittingWidth: metrics.width - 0.4))
            XCTAssertEqual(narrowMetrics.width, metrics.width, accuracy: 0.001, latex)

            let margin: CGFloat = 30
            let renderer = ImageRenderer(content: Math(latex)
                .mathFont(Math.Font(name: .latinModern, size: fontSize))
                .mathTypesettingStyle(.text)
                .frame(width: metrics.width - 0.4, height: height, alignment: .topLeading)
                .padding(margin)
                .background(Color.white)
                .environment(\.colorScheme, .light))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            var inkInsideFrame = 0
            var inkOutsideFrame = 0
            for row in 0..<bitmap.pixelsHigh {
                for column in 0..<bitmap.pixelsWide {
                    // The image is a whole number of pixels; its partly covered last row and
                    // column are transparent, not ink.
                    guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.9, color.brightnessComponent < 0.5 else { continue }
                    let point = CGPoint(x: CGFloat(column) / 2, y: CGFloat(row) / 2)
                    // Descenders and subscripts reach below the typographic height; a
                    // second line would start a whole line lower.
                    if CGRect(x: margin, y: margin, width: metrics.width, height: height).insetBy(dx: -1, dy: -height / 2).contains(point) {
                        inkInsideFrame += 1
                    } else {
                        inkOutsideFrame += 1
                    }
                }
            }
            XCTAssertGreaterThan(inkInsideFrame, 20, latex)
            XCTAssertEqual(inkOutsideFrame, 0, "\(latex) broke onto a second line")
        }
        // A formula genuinely wider than its width still breaks into lines.
        let long = "a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p"
        let naturalLong = try XCTUnwrap(DisplayMathRendering.metrics(for: long, fontSize: fontSize))
        let brokenLong = try XCTUnwrap(DisplayMathRendering.metrics(for: long, fontSize: fontSize, fittingWidth: naturalLong.width / 2))
        XCTAssertGreaterThan(brokenLong.ascent + brokenLong.descent, 1.5 * (naturalLong.ascent + naturalLong.descent))
    }

    /// A fraction late in a long formula goes onto a new line when it would run past the
    /// width. The typesetter measured only the text since the last fraction, so the third
    /// fraction here was placed past the edge of a callout and cut off.
    func testFractionAfterEarlierFractionsBreaksOntoANewLine() throws {
        let fontSize: CGFloat = 22
        let latex = #"\text{new time} = \frac{1-f}{s} + f, \qquad \text{memory share} = \frac{f}{\frac{1-f}{s} + f}, \qquad \text{overall speedup} = \frac{1}{\frac{1-f}{s} + f}"#
        let natural = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: fontSize))
        for fraction in [0.95, 0.8, 0.6] {
            let width = natural.width * fraction
            let fitted = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: fontSize, fittingWidth: width))
            XCTAssertLessThanOrEqual(fitted.width, width + MathAttachment.naturalWidthTolerance, "at \(fraction) of its width")
            XCTAssertGreaterThan(fitted.ascent + fitted.descent, 1.5 * (natural.ascent + natural.descent), "at \(fraction) of its width")
        }
    }

    /// `\underbrace` and `\overbrace` are typeset, with their labels below or above the
    /// brace. The typesetter did not know them, so a formula using one showed as its source.
    func testUnderbraceAndOverbraceAreTypesetWithTheirLabels() throws {
        let fontSize: CGFloat = 22
        let note = #"t_{\text{wear-out}} = \underbrace{\frac{C}{G}}_{\text{write requests to write every cell once}} \times \underbrace{E}_{\text{writes each cell survives}} \times \underbrace{t_{req}}_{\text{time per write request}}"#
        XCTAssertTrue(MathAttachment.canTypeset(note))
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: #"Under $\underbrace{a+b}_{n}$ and over $\overbrace{a+b}^{n}$."#), 2)

        let plain = try XCTUnwrap(DisplayMathRendering.metrics(for: "a+b", fontSize: fontSize))
        let under = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\underbrace{a+b}"#, fontSize: fontSize))
        let underLabelled = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\underbrace{a+b}_{\text{a long label}}"#, fontSize: fontSize))
        let over = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\overbrace{a+b}"#, fontSize: fontSize))
        let overLabelled = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\overbrace{a+b}^{\text{a long label}}"#, fontSize: fontSize))
        let label = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\scriptstyle\text{a long label}"#, fontSize: fontSize))
        // The brace adds height on its side only, and is as wide as what it spans.
        XCTAssertEqual(under.width, plain.width, accuracy: 0.01)
        XCTAssertEqual(under.ascent, plain.ascent, accuracy: 0.01)
        XCTAssertGreaterThan(under.descent, plain.descent + 0.3 * fontSize)
        XCTAssertEqual(over.descent, plain.descent, accuracy: 0.01)
        XCTAssertGreaterThan(over.ascent, plain.ascent + 0.3 * fontSize)
        // The label goes beyond the brace, as wide as it is, and not beside it.
        XCTAssertGreaterThan(underLabelled.descent, under.descent + label.ascent)
        XCTAssertEqual(underLabelled.width, label.width, accuracy: 0.5)
        XCTAssertGreaterThan(overLabelled.ascent, over.ascent + label.descent)
        XCTAssertEqual(overLabelled.width, label.width, accuracy: 0.5)
    }

    /// A hyphen inside `\text` stays a hyphen: `\text{wear-out}` read as "wear − out",
    /// with a minus sign and the spaces of a binary operator.
    func testHyphenInsideTextIsAHyphen() throws {
        let fontSize: CGFloat = 22
        let hyphenated = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\text{wear-out}"#, fontSize: fontSize))
        let minus = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\text{wear}-\text{out}"#, fontSize: fontSize))
        let joined = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\text{wearout}"#, fontSize: fontSize))
        XCTAssertLessThan(hyphenated.width, minus.width - 0.3 * fontSize)
        XCTAssertLessThan(hyphenated.width - joined.width, 0.4 * fontSize, "one hyphen wide")
    }

    /// KaTeX's arrows are typeset. The typesetter knew only the plain ones, so a caption with
    /// `$R_G \rightsquigarrow R_G/4$` showed its source in the reading view (owner's Mac, 2026-10-24).
    func testKaTeXArrowsAreTypesetAsOneRelation() throws {
        let fontSize: CGFloat = 22
        let arrows = ["rightsquigarrow", "leadsto", "leftrightsquigarrow", "hookrightarrow", "hookleftarrow", "twoheadrightarrow", "twoheadleftarrow",
                      "rightarrowtail", "leftarrowtail", "looparrowright", "looparrowleft", "curvearrowright", "curvearrowleft", "circlearrowright",
                      "circlearrowleft", "rightleftharpoons", "leftrightharpoons", "rightharpoonup", "rightharpoondown", "leftharpoonup",
                      "leftharpoondown", "upharpoonright", "upharpoonleft", "downharpoonright", "downharpoonleft", "restriction",
                      "rightrightarrows", "leftleftarrows", "rightleftarrows", "leftrightarrows", "upuparrows", "downdownarrows",
                      "nrightarrow", "nleftarrow", "nleftrightarrow", "nRightarrow", "nLeftarrow", "nLeftrightarrow", "Rrightarrow",
                      "Lleftarrow", "Rsh", "Lsh", "multimap", "longmapsto", "impliedby"]
        let relation = try XCTUnwrap(DisplayMathRendering.metrics(for: #"a \rightarrow b"#, fontSize: fontSize))
        for arrow in arrows {
            XCTAssertTrue(MathAttachment.canTypeset(#"R_G \\#(arrow) R_G/4"#), arrow)
            // A relation between two letters, with a relation's spaces: about as wide as `\rightarrow`.
            let arrowed = try XCTUnwrap(DisplayMathRendering.metrics(for: #"a \\#(arrow) b"#, fontSize: fontSize), arrow)
            XCTAssertEqual(arrowed.width, relation.width, accuracy: 0.6 * fontSize, arrow)
        }
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: #"once the gate is contacted at both ends; $R_G \rightsquigarrow R_G/4$ (pink)"#), 1)
    }

    /// A row break inside braces in a cell ends only the braces' list, so one cell could bring
    /// two row breaks at once, and building the table read past its last row: Graphite crashed
    /// on a note whose `aligned` rows each sat in their own `\textcolor{…}{…}` (owner's vault,
    /// 2026-10-24). Such a formula now shows as its source, as any the typesetter cannot read.
    func testRowBreaksInsideColorGroupsOfAnAlignedFormulaDoNotCrash() throws {
        let colorGroupedRows = #"\begin{aligned} \textcolor{red}{a \textcolor{black}{ &= 1 \\ \textcolor{red}{b \textcolor{black}{ &= 2 \\ &= 3 \end{aligned}}}}}"#
        XCTAssertFalse(MathAttachment.canTypeset(colorGroupedRows))
        XCTAssertNil(DisplayMathRendering.metrics(for: colorGroupedRows, fontSize: 20))
        XCTAssertFalse(MathAttachment.canTypeset(#"\begin{aligned} a &= \textcolor{red}{1 \\ 2} \\ b &= 3 \end{aligned}"#))
        // Row breaks the parser has always read are drawn as before: three rows, and braces of rows.
        let plainRows = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\begin{aligned} a &= 1 \\ b &= 2 \\ &= 3 \end{aligned}"#, fontSize: 20))
        let oneRow = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\begin{aligned} a &= 1 \end{aligned}"#, fontSize: 20))
        XCTAssertGreaterThan(plainRows.ascent + plainRows.descent, 2.5 * (oneRow.ascent + oneRow.descent))
        XCTAssertTrue(MathAttachment.canTypeset(#"\textcolor{red}{x \\ y \\ z}"#))
    }

    /// The view draws display math at its natural width when it overhangs the column by
    /// up to a point; the measurement used to refit it (and reserve the wrapped height)
    /// as soon as it overhung at all.
    func testDisplayMathOverhangingByLessThanTheToleranceIsMeasuredAtItsNaturalSize() {
        let attachment = MathAttachment(latex: "a + b + c + d + e + f + g + h + i + j + k + l + m + n", style: .block)
        let environment = TextEnvironmentValues()
        let naturalSize = attachment.sizeThatFits(.unspecified, in: environment)
        XCTAssertGreaterThan(naturalSize.width, 0)
        let slightOverhang = MathAttachment.naturalWidthTolerance / 2
        let almostWideEnough = ProposedViewSize(width: naturalSize.width - slightOverhang, height: nil)
        XCTAssertEqual(attachment.sizeThatFits(almostWideEnough, in: environment), naturalSize)
        let halfWidth = ProposedViewSize(width: naturalSize.width / 2, height: nil)
        let wrappedSize = attachment.sizeThatFits(halfWidth, in: environment)
        XCTAssertNotEqual(wrappedSize, naturalSize, "Display math genuinely wider than the column still wraps.")
    }

    // MARK: Patch 7, tables fit the width they are offered

    func testColumnsGiveUpTheSameShareOfTheWidthTheyCanGiveUp() {
        func columnWidths(availableWidth: CGFloat?) -> [CGFloat] {
            StructuredText.TableColumnsLayout.columnWidths(narrowestWidths: [40, 60], widestWidths: [100, 300], availableWidth: availableWidth)
        }
        XCTAssertEqual(columnWidths(availableWidth: nil), [100, 300], "any width: nothing wraps")
        XCTAssertEqual(columnWidths(availableWidth: 500), [100, 300], "more than the table needs: it does not stretch")
        XCTAssertEqual(columnWidths(availableWidth: 250), [70, 180], "half of what each column can give up")
        XCTAssertEqual(columnWidths(availableWidth: 251.5), [70, 181], "whole points, never more than is available")
        XCTAssertEqual(columnWidths(availableWidth: 80), [40, 60], "less than the widest words: the table overflows")
    }

    func testEveryWordGetsALineOfItsOwnExceptAcrossNonBreakingSpacesAndAttachments() throws {
        XCTAssertEqual(String(AttributedString("one two\tthree\u{00A0}four").breakingAfterEveryWord().characters), "one\ntwo\nthree\u{00A0}four")

        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        let formulaBetweenWords = try parser.attributedString(for: "**bold** then $\\sqrt{a + b}$ end")
        let broken = formulaBetweenWords.breakingAfterEveryWord()
        XCTAssertEqual(String(broken.characters), "bold\nthen\n\u{FFFC}\nend")
        XCTAssertEqual(broken.attachments(), formulaBetweenWords.attachments(), "the formula stays whole")
        XCTAssertEqual(broken.runs.first?.inlinePresentationIntent, .stronglyEmphasized, "words keep their style")

        // A formula drawn in pieces gets a line of its own for each piece.
        let formulaInPieces = try parser.attributedString(for: "$a + b = c$")
        XCTAssertTrue(formulaInPieces.hasWordBreaks)
        XCTAssertEqual(String(formulaInPieces.breakingAfterEveryWord().characters), "\u{FFFC}\n\u{FFFC}\n\u{FFFC}")
    }

    func testOnlyAttachmentsThatShrinkMakeACellFollowItsColumn() throws {
        let environment = TextEnvironmentValues()
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        XCTAssertFalse(try parser.attributedString(for: "Energy $E = mc^2$").hasAttachmentsThatFitTheirWidth(in: environment))

        var figure = AttributedString("\u{FFFC}")
        figure.textual.attachment = AnyAttachment(ShrinkingFigureAttachment(naturalWidth: 400))
        XCTAssertTrue(figure.hasAttachmentsThatFitTheirWidth(in: environment))
    }

    /// Three figures, each wider than the table is offered in all: each shrinks to its
    /// column, as an image does in a browser's table, where it used to keep the width of
    /// the whole text and push the table far past its container.
    func testFiguresInATableShrinkToTheirColumns() async throws {
        let markdown = "| One | Two | Six |\n| --- | --- | --- |\n| ![](a.png) | ![](b.png) | ![](c.png) |\n"
        let layout = try await tableLayout(ofMarkdown: markdown, offeredWidth: 302) { layout in
            layout.numberOfRows == 2 && layout.bounds.width <= 302 && layout.rowBounds(1).height > 40
        }
        XCTAssertEqual(layout.numberOfColumns, 3)
        XCTAssertLessThanOrEqual(layout.bounds.width, 302)
        for column in 0..<3 {
            // 302 less the two gaps of one point, shared by three equal columns.
            XCTAssertEqual(layout.cellBounds(row: 1, column: column).width, 100, accuracy: 1)
        }
        // A figure is half as tall as it is wide, so the row is as tall as a figure one column
        // wide, and the line it is on adds a few points below it.
        XCTAssertGreaterThanOrEqual(layout.rowBounds(1).height, 49)
        XCTAssertLessThanOrEqual(layout.rowBounds(1).height, 56)
    }

    func testFiguresThatFitKeepTheirSizeAndTheTableDoesNotStretch() async throws {
        let markdown = "| One | Two |\n| --- | --- |\n| ![](a.png) | ![](b.png) |\n"
        let layout = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000) { layout in
            layout.numberOfRows == 2 && layout.rowBounds(1).height > 190
        }
        XCTAssertEqual(layout.bounds.width, 2 * ShrinkingFigureLoader.naturalWidth + 1, accuracy: 1)
        XCTAssertGreaterThanOrEqual(layout.rowBounds(1).height, ShrinkingFigureLoader.naturalWidth / 2)
        XCTAssertLessThanOrEqual(layout.rowBounds(1).height, ShrinkingFigureLoader.naturalWidth / 2 + 6)
    }

    func testTextWrapsToTheOfferedWidthButNoWordIsBroken() async throws {
        let sentence = "alpha beta gamma delta epsilon zeta eta theta iota kappa"
        let markdown = "| Name | Notes |\n| --- | --- |\n| x | \(sentence) |\n"
        let unwrapped = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000) { layout in layout.numberOfRows == 2 }
        let wrapped = try await tableLayout(ofMarkdown: markdown, offeredWidth: 160) { layout in layout.numberOfRows == 2 }
        XCTAssertGreaterThan(unwrapped.bounds.width, 160, "the sentence on one line is wider than the narrow table")
        XCTAssertLessThanOrEqual(wrapped.bounds.width, 160)
        XCTAssertGreaterThan(wrapped.rowBounds(1).height, unwrapped.rowBounds(1).height * 2, "the sentence takes several lines")

        // Offered almost nothing, the table keeps the width of its widest words and
        // overflows; a word broken letter by letter would make the row far taller.
        let narrowest = try await tableLayout(ofMarkdown: markdown, offeredWidth: 10) { layout in layout.numberOfRows == 2 }
        XCTAssertGreaterThan(narrowest.bounds.width, 40)
        let wordsInTheSentence = CGFloat(sentence.split(separator: " ").count)
        XCTAssertLessThanOrEqual(narrowest.rowBounds(1).height, unwrapped.rowBounds(1).height * wordsInTheSentence + 1, "one word on each line at most")
    }

    // MARK: SwiftUIMath patches 10 to 16, MathJax's other commands

    /// A formula's width and height at 20 points, which any of these formulas must have.
    private func mathMetrics(_ latex: String, file: StaticString = #filePath, line: UInt = #line) throws -> DisplayMathRendering.Metrics {
        try XCTUnwrap(DisplayMathRendering.metrics(for: LaTeXCompatibility.normalized(latex), fontSize: Self.mathFontSize), latex, file: file, line: line)
    }

    private static let mathFontSize: CGFloat = 20

    /// How many pixels of a formula have ink, drawn as `Math` draws it (patch 5) at twice its size.
    private func inkPixelCount(_ latex: String) throws -> Int {
        let drawn = LaTeXCompatibility.normalized(latex)
        let renderer = ImageRenderer(content: Math(drawn).mathFont(.init(name: .latinModern, size: Self.mathFontSize)).foregroundStyle(.black).padding(10).background(.white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, latex)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 255, count: image.width * image.height)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels.filter { pixel in pixel < 128 }.count
    }

    /// Patch 10. The vault has formulas typed with `δ` and `≤`: the parser skipped those letters,
    /// so `$δ$` could not be typeset and `$κ(x)$` lost its `κ`.
    func testCharactersTypedInAFormulaAreDrawnAsTheirCommands() throws {
        XCTAssertEqual(try mathMetrics("δ + ξ ≤ θ").width, try mathMetrics(#"\delta + \xi \leq \theta"#).width, accuracy: 0.01)
        XCTAssertEqual(try mathMetrics("κ(x)").width, try mathMetrics(#"\kappa(x)"#).width, accuracy: 0.01)
        XCTAssertEqual(try mathMetrics(#"\cosθ"#).width, try mathMetrics(#"\cos\theta"#).width, accuracy: 0.01, "A command's name ends at a letter that is not ASCII.")
        XCTAssertEqual(try mathMetrics("a\\\nb").width, try mathMetrics(#"a\ b"#).width, accuracy: 0.01, "A backslash before a line break is a space.")
        XCTAssertTrue(MathAttachment.canTypeset(#"1 \,\&\, 1"#))
        XCTAssertTrue(MathAttachment.canTypeset("日本語 x"), "A character the font lacks is left to a fallback font.")
        XCTAssertFalse(MathAttachment.canTypeset("\u{200B}"), "An invisible character draws nothing.")
    }

    /// Patch 11. Each is drawn with a glyph Latin Modern has, in its class.
    func testKaTeXSymbolsAreTypesetInTheirClasses() throws {
        let relation = try mathMetrics(#"a = b"#).width - mathMetrics(#"="#).width
        for symbol in ["leqslant", "geqslant", "lesssim", "gtrsim", "succeq", "preceq", "triangleq", "therefore", "because", "vdash", "lll", "ggg", "subsetneq", "nmid"] {
            XCTAssertEqual(try mathMetrics(#"a \\#(symbol) b"#).width - (try mathMetrics(#"\\#(symbol)"#).width), relation, accuracy: 0.01, symbol)
        }
        for symbol in ["diamond", "blacksquare", "varnothing", "checkmark", "llbracket", "rrbracket", "circledast", "barwedge", "bigcirc", "oiint", "oiiint", "lozenge", "complement", "sharp", "flat", "bigstar", "blacklozenge"] {
            XCTAssertGreaterThan(try mathMetrics(#"\\#(symbol)"#).width, 0, symbol)
        }
        XCTAssertGreaterThan(try mathMetrics(#"\left\llbracket \frac{a}{b} \right\rrbracket"#).ascent, try mathMetrics(#"\frac{a}{b}"#).ascent - 1, "As delimiters too.")
        XCTAssertGreaterThan(try mathMetrics(#"\mathring{A}"#).ascent, try mathMetrics("A").ascent)
        XCTAssertEqual(try mathMetrics(#"a \not\leq b"#).width, try mathMetrics(#"a \leq b"#).width, accuracy: 2)
    }

    /// Patch 12. The owner's vault had 2,341 formulas with `\boxed`, drawn as their source.
    func testFramesAndCirclesStandAroundWhatTheyHold() throws {
        let fontSize = Self.mathFontSize
        let letter = try mathMetrics("x")
        let framed = try mathMetrics(#"\boxed{x}"#)
        XCTAssertEqual(framed.width, letter.width + 2 * 0.34 * fontSize, accuracy: 0.01, "0.3 em of room and a line of 0.04 em on each side")
        XCTAssertEqual(framed.ascent, letter.ascent + 0.34 * fontSize, accuracy: 0.01)
        XCTAssertEqual(framed.descent, letter.descent + 0.34 * fontSize, accuracy: 0.01)
        XCTAssertGreaterThan(try mathMetrics(#"\boxed{\frac{a}{b}}"#).ascent, try mathMetrics(#"\textstyle\frac{a}{b}"#).ascent, "It sets its content in display style.")
        XCTAssertGreaterThan(try inkPixelCount(#"\boxed{x}"#), try inkPixelCount("x") * 2, "The frame is drawn.")
        XCTAssertGreaterThan(try mathMetrics(#"\boxed{x}^2"#).width, framed.width, "It takes a script.")
        XCTAssertGreaterThan(try mathMetrics(#"\fbox{some text}"#).width, try mathMetrics(#"\text{some text}"#).width)
        XCTAssertGreaterThan(try mathMetrics(#"\textcircled{1}"#).width, 1.1 * fontSize)
        XCTAssertGreaterThan(try inkPixelCount(#"\textcircled{a}"#), try inkPixelCount(#"\text{a}"#))
    }

    func testStrikeOutsCrossWhatTheyHold() throws {
        let fontSize = Self.mathFontSize
        for command in ["cancel", "bcancel", "xcancel"] {
            XCTAssertEqual(try mathMetrics(#"\\#(command){ab}"#).width, try mathMetrics("ab").width + 0.2 * fontSize, accuracy: 0.05, command)
        }
        XCTAssertGreaterThan(try inkPixelCount(#"\xcancel{x}"#), try inkPixelCount(#"\cancel{x}"#), "Two strokes, not one.")
        XCTAssertGreaterThan(try inkPixelCount(#"\cancel{x}"#), try inkPixelCount("x"))
    }

    func testPhantomsKeepTheRoomOfWhatTheyHideAndDrawNothing() throws {
        let hidden = try mathMetrics(#"\frac{a}{b}"#)
        let phantom = try mathMetrics(#"\phantom{\frac{a}{b}}"#)
        XCTAssertEqual(phantom.width, hidden.width, accuracy: 0.01)
        XCTAssertEqual(phantom.ascent, hidden.ascent, accuracy: 0.01)
        XCTAssertEqual(try inkPixelCount(#"\phantom{\frac{a}{b}}"#), 0)
        XCTAssertEqual(try mathMetrics(#"a\hphantom{\frac{a}{b}}"#).width, try mathMetrics("a").width + hidden.width, accuracy: 0.01)
        XCTAssertLessThan(try mathMetrics(#"a\hphantom{\frac{a}{b}}"#).ascent, hidden.ascent, "No height.")
        XCTAssertEqual(try mathMetrics(#"a\vphantom{\frac{a}{b}}"#).width, try mathMetrics("a").width, accuracy: 0.01, "No width.")
        XCTAssertEqual(try mathMetrics(#"a\vphantom{\frac{a}{b}}"#).ascent, hidden.ascent, accuracy: 0.01)
    }

    func testOversetUndersetAndStackrelKeepTheClassOfWhatTheyStandOver() throws {
        let plain = try mathMetrics(#"a = b"#)
        for stacked in [#"\overset{x}{=}"#, #"\stackrel{x}{=}"#, #"\underset{x}{=}"#] {
            XCTAssertEqual(try mathMetrics(#"a \#(stacked) b"#).width, plain.width, accuracy: 0.01, "A relation's spaces: \(stacked)")
            XCTAssertEqual(try mathMetrics(#"a \#(stacked) -b"#).width, try mathMetrics(#"a = -b"#).width, accuracy: 0.01, "The minus after it is a sign: \(stacked)")
        }
        XCTAssertGreaterThan(try mathMetrics(#"a \overset{x}{=} b"#).ascent, plain.ascent)
        XCTAssertGreaterThan(try mathMetrics(#"a \underset{x}{=} b"#).descent, plain.descent)
        XCTAssertEqual(try mathMetrics(#"a \overset{x}{y} b"#).width, try mathMetrics("ayb").width, accuracy: 0.5, "Over a letter it is a letter.")
        XCTAssertEqual(try mathMetrics(#"a \overset{x}{+} b"#).width, try mathMetrics("a + b").width, accuracy: 0.01, "Over an operator it is an operator.")
    }

    func testExtensibleArrowsAreRelationsAsWideAsTheirLabels() throws {
        let fontSize = Self.mathFontSize
        let spaces = try mathMetrics(#"a = b"#).width - (try mathMetrics("=").width + (try mathMetrics("ab").width))
        for command in ["xrightarrow", "xleftarrow"] {
            let shortLabel = try mathMetrics(#"\\#(command){x}"#)
            XCTAssertEqual(shortLabel.width, 1.47 * fontSize, accuracy: 0.01, command)
            XCTAssertEqual(try mathMetrics(#"a \\#(command){x} b"#).width, shortLabel.width + (try mathMetrics("ab").width) + spaces, accuracy: 0.6, "A relation's spaces: \(command)")
            let longLabel = try mathMetrics(#"\text{a very long label over it}"#)
            XCTAssertGreaterThan(try mathMetrics(#"\\#(command){\text{a very long label over it}}"#).width, 0.7 * longLabel.width, command)
            XCTAssertGreaterThan(try mathMetrics(#"\\#(command)[y]{x}"#).descent, shortLabel.descent, "The label below: \(command)")
            XCTAssertGreaterThan(try mathMetrics(#"\\#(command)[\text{a very long label}]{x}"#).width, shortLabel.width, "It widens the arrow too: \(command)")
        }
        XCTAssertGreaterThan(try mathMetrics(#"\xleftrightarrow{x}"#).width, 1.47 * fontSize, "Never narrower than its two heads.")
        XCTAssertTrue(MathAttachment.canTypeset(#"\xrightarrow{}"#))
        // The shaft continues the glyph's: a rule's ink for each point of length, with no gap.
        let shorter = try inkPixelCount(#"\xrightarrow{\phantom{\text{a long label}}}"#)
        let longer = try inkPixelCount(#"\xrightarrow{\phantom{\text{a long label a long label}}}"#)
        let addedWidth = try mathMetrics(#"\xrightarrow{\phantom{\text{a long label a long label}}}"#).width - (try mathMetrics(#"\xrightarrow{\phantom{\text{a long label}}}"#).width)
        XCTAssertEqual(Double(longer - shorter) / Double(addedWidth * 2), 2.5, accuracy: 1, "One rule's thickness in pixels, thickened as `Math` thickens outlines on the Mac")
    }

    func testArrowsOverAListSpanIt() throws {
        let long = try mathMetrics("ABCDEF")
        for command in ["overrightarrow", "overleftarrow"] {
            let arrowed = try mathMetrics(#"\\#(command){ABCDEF}"#)
            XCTAssertEqual(arrowed.width, long.width, accuracy: 0.01, command)
            XCTAssertGreaterThan(arrowed.ascent, long.ascent, command)
            XCTAssertEqual(arrowed.descent, long.descent, accuracy: 0.01, command)
            XCTAssertGreaterThan(try mathMetrics(#"\\#(command){A}^{ff}"#).width, try mathMetrics(#"\\#(command){A}"#).width, "It takes a script: \(command)")
        }
        XCTAssertTrue(MathAttachment.canTypeset(#"\overleftrightarrow{AB}"#))
        XCTAssertGreaterThan(try inkPixelCount(#"\overrightarrow{ABCDEF}"#), try inkPixelCount("ABCDEF"))
    }

    func testClassCommandsSpaceTheirArgumentAsTheClass() throws {
        XCTAssertEqual(try mathMetrics(#"a \mathbin{+} b"#).width, try mathMetrics("a + b").width, accuracy: 0.01)
        XCTAssertEqual(try mathMetrics(#"a \mathrel{=} b"#).width, try mathMetrics("a = b").width, accuracy: 0.01)
        XCTAssertEqual(try mathMetrics(#"a \mathord{+} b"#).width, try mathMetrics("a{}b").width + (try mathMetrics("+").width), accuracy: 0.5)
        XCTAssertTrue(MathAttachment.canTypeset(#"a \mathbin{\overline{\subset}} b \mathopen{(} c \mathclose{)} \mathpunct{,} d"#))
        XCTAssertGreaterThan(try mathMetrics(#"a \bmod b"#).width, try mathMetrics(#"a\mathrm{mod}b"#).width, "An operator's spaces.")
    }

    func testSizedDelimitersGrowInKaTeXSteps() throws {
        let fontSize = Self.mathFontSize
        var previousHeight: CGFloat = 0
        for (command, heightInEm) in [("big", 1.2), ("Big", 1.8), ("bigg", 2.4), ("Bigg", 3.0)] as [(String, CGFloat)] {
            for suffix in ["", "l", "r", "m"] {
                let metrics = try mathMetrics(#"\\#(command)\#(suffix)("#)
                XCTAssertGreaterThanOrEqual(metrics.ascent + metrics.descent, heightInEm * fontSize - 0.2, command + suffix)
                XCTAssertLessThan(metrics.ascent + metrics.descent, (heightInEm + 0.3) * fontSize, command + suffix)
                XCTAssertGreaterThan(metrics.ascent + metrics.descent, previousHeight, command + suffix)
            }
            let metrics = try mathMetrics(#"\\#(command)("#)
            previousHeight = metrics.ascent + metrics.descent
        }
        XCTAssertEqual(try mathMetrics(#"a \bigm| b"#).width - (try mathMetrics(#"\bigm|"#).width), try mathMetrics("a = b").width - (try mathMetrics("=").width), accuracy: 0.01, "\\bigm relates.")
        for delimiter in [#"\|"#, "|", "[", #"\{"#, #"\langle"#, #"\lfloor"#, #"\vert"#, #"\Vert"#, #"\lvert"#, #"\rVert"#] {
            XCTAssertTrue(MathAttachment.canTypeset(LaTeXCompatibility.normalized(#"\big\#(delimiter)"#)), delimiter)
        }
        XCTAssertGreaterThan(try mathMetrics(#"a\big.b"#).width, try mathMetrics("ab").width, "An empty delimiter keeps its small room.")
        XCTAssertFalse(MathAttachment.canTypeset(#"\big"#), "A size with no delimiter stays as source.")
    }

    func testMiddleDelimiterIsAsTallAsItsPair() throws {
        let plain = try mathMetrics(#"\left\{ \frac{a}{b} \middle| \frac{c}{d} \right\}"#)
        XCTAssertEqual(plain.ascent, try mathMetrics(#"\left\{ \frac{a}{b} \, \frac{c}{d} \right\}"#).ascent, accuracy: 0.5)
        let formula = #"\left\{ \frac{a}{b} \middle| \frac{c}{d} \right\}"#
        XCTAssertGreaterThan(try inkPixelCount(formula), try inkPixelCount(#"\left\{ \frac{a}{b} \mid \frac{c}{d} \right\}"#), "A taller bar than a relation's.")
    }

    /// Patch 13. The vault had 2,290 formulas with `array`.
    func testArrayAlignsItsColumnsAsItsPreambleSays() throws {
        let fontSize = Self.mathFontSize
        let cell = try mathMetrics("a")
        XCTAssertEqual(try mathMetrics(#"\begin{array}{ll} a & a \end{array}"#).width, 2 * cell.width + fontSize, accuracy: 0.01, "Columns 1 em apart")
        // A narrow row under a wide one: the rows' widths are the same, the ink stands elsewhere.
        for preamble in ["l", "c", "r", "p{3cm}", "@{}l", "l@{x}", " l "] {
            XCTAssertTrue(MathAttachment.canTypeset(#"\begin{array}{\#(preamble)} a \\ bbb \end{array}"#), preamble)
        }
        XCTAssertFalse(MathAttachment.canTypeset(#"\begin{array} a \end{array}"#), "An array needs its preamble.")
        XCTAssertGreaterThan(try mathMetrics(#"\left\{\begin{array}{l} x = 1 \\ y = 2 \end{array}\right."#).width, 0)
        XCTAssertEqual(try mathMetrics(#"\begin{array}{|c|} a \end{array}"#).width, cell.width + fontSize, accuracy: 0.5, "Half a column gap for each outer rule")
        XCTAssertGreaterThan(try inkPixelCount(#"\begin{array}{c|c} a & a \end{array}"#), try inkPixelCount(#"\begin{array}{cc} a & a \end{array}"#), "The rule is drawn.")
        let oneRow = try mathMetrics(#"\begin{array}{c} a \end{array}"#)
        let ruled = try mathMetrics(#"\begin{array}{c} a \\ \hline \end{array}"#)
        XCTAssertLessThan(ruled.ascent + ruled.descent, 1.5 * (oneRow.ascent + oneRow.descent) + fontSize / 2, "A rule at the end begins no row.")
        XCTAssertGreaterThan(try inkPixelCount(#"\begin{array}{c} a \\ \hline a \end{array}"#), try inkPixelCount(#"\begin{array}{c} a \\ a \end{array}"#))
    }

    func testRowBreakLengthAddsHeightAndIsNotDrawn() throws {
        let fontSize = Self.mathFontSize
        let plain = try mathMetrics(#"\begin{pmatrix} a \\ b \end{pmatrix}"#)
        let spaced = try mathMetrics(#"\begin{matrix} a \\[1em] b \end{matrix}"#)
        let unspaced = try mathMetrics(#"\begin{matrix} a \\ b \end{matrix}"#)
        XCTAssertEqual(spaced.ascent + spaced.descent, unspaced.ascent + unspaced.descent + fontSize, accuracy: 0.01)
        XCTAssertEqual(spaced.width, unspaced.width, accuracy: 0.01, "`[1em]` is not text in the cell.")
        XCTAssertEqual(try mathMetrics(#"\begin{pmatrix} a \\[2pt] b \end{pmatrix}"#).width, plain.width, accuracy: 0.01)
        XCTAssertGreaterThan(try mathMetrics(#"\begin{matrix} a \\ [b,c] \end{matrix}"#).width, unspaced.width, "A bracket after a space is the next row's.")
        XCTAssertGreaterThan(try mathMetrics(#"\begin{matrix} a \\[b,c] \end{matrix}"#).width, unspaced.width, "So are brackets that hold no length.")
    }

    func testCasesGatheredAndSubstackInAnEnvironment() throws {
        XCTAssertGreaterThan(try mathMetrics(#"\begin{cases} a & b & c \\ d & e & f \end{cases}"#).width, try mathMetrics(#"\begin{cases} a & b \\ d & e \end{cases}"#).width, "Any number of columns")
        XCTAssertGreaterThan(try mathMetrics(#"\begin{gathered} a \\ b \end{gathered}"#).ascent, try mathMetrics("a").ascent)
        // The substack's row break belongs to it, not to the `aligned` around it.
        XCTAssertTrue(MathAttachment.canTypeset(#"\begin{aligned} a &\underset{\substack{x \\ y}}{=} b \\ c &= d \end{aligned}"#))
    }

    /// Patch 14.
    func testBinomialStylesStarredOperatorNamesAndHorizontalSpaces() throws {
        let fontSize = Self.mathFontSize
        XCTAssertGreaterThan(try mathMetrics(#"\dbinom{n}{k}"#).ascent, try mathMetrics(#"\tbinom{n}{k}"#).ascent - 0.01)
        XCTAssertGreaterThan(try inkPixelCount(#"\dbinom{n}{k}"#), try inkPixelCount(#"\tbinom{n}{k}"#))
        for name in ["max", "m a x", #"arg\,max"#] {
            XCTAssertGreaterThan(try mathMetrics(#"\operatorname*{\#(name)}_x"#).descent, try mathMetrics(#"\operatorname{max}_x"#).descent, "Its limit goes below: \(name)")
        }
        XCTAssertTrue(MathAttachment.canTypeset(#"\operatorname*{x^2}_y"#), "Not a plain name: drawn upright, without limits.")
        XCTAssertEqual(try mathMetrics(#"a\hspace{1em}b"#).width, try mathMetrics("ab").width + fontSize, accuracy: 0.6)
        XCTAssertEqual(try mathMetrics(#"a\hspace{10pt}b"#).width, try mathMetrics(#"a\hspace{1em}b"#).width, accuracy: 0.01)
        XCTAssertEqual(try mathMetrics(#"a\hspace*{ 1 em }b"#).width, try mathMetrics(#"a\hspace{1em}b"#).width, accuracy: 0.01)
        XCTAssertFalse(MathAttachment.canTypeset(#"a\hspace{wide}b"#))
    }

    /// Patch 15. `= \quad -x` stopped Debug builds on an assert: a binary operator right after
    /// a relation has no spacing, and the space hid the relation from the rule that makes it a sign.
    func testSpacesAndStyleChangesHaveNoClass() throws {
        XCTAssertEqual(try mathMetrics(#"a \rightarrow \quad -\frac{1}{2}"#).width, try mathMetrics(#"a \rightarrow \quad {}{-}\frac{1}{2}"#).width, accuracy: 0.01)
        XCTAssertEqual(try mathMetrics(#"\begin{matrix} -1 \end{matrix}"#).width, try mathMetrics("-1").width, accuracy: 0.01, "A sign at the start of a cell has no spaces.")
        XCTAssertEqual(try mathMetrics(#"1\,000"#).width, try mathMetrics("1000").width + 3.0 / 18.0 * Self.mathFontSize, accuracy: 0.01, "Numbers on either side of a space do not merge.")
        XCTAssertEqual(try mathMetrics(#"a + \quad b"#).width, try mathMetrics(#"a+b"#).width + Self.mathFontSize, accuracy: 0.01, "An operator keeps its spaces around one.")
    }

    /// Patch 16. The vault has `\boldsymbol{\nabla}` 844 times.
    func testBoldSymbolsHaveTheirBoldForms() throws {
        for symbol in ["nabla", "partial", "epsilon", "vartheta", "phi", "varrho", "varpi"] {
            XCTAssertGreaterThan(try inkPixelCount(#"\boldsymbol{\\#(symbol)}"#), try inkPixelCount(#"\\#(symbol)"#), symbol)
            XCTAssertGreaterThan(try inkPixelCount(#"\mathbf{\\#(symbol)}"#), try inkPixelCount(#"\\#(symbol)"#), symbol)
        }
        XCTAssertGreaterThan(try inkPixelCount(#"\boldsymbol{x}"#), try inkPixelCount("x"))
        XCTAssertGreaterThan(try inkPixelCount(#"\pmb{\alpha}"#), try inkPixelCount(#"\alpha"#))
        XCTAssertGreaterThan(try inkPixelCount(#"\boldsymbol{1}"#), try inkPixelCount("1"))
    }

    /// Commands rewritten for the typesetter reach it as text it can draw.
    func testCommandsLaTeXCompatibilityRewritesAreTypeset() throws {
        for formula in [#"1, \dots, n"#, #"a + \dots + b"#, #"\lvert x \rvert \lVert y \rVert"#, #"\left\lvert x \right\rvert"#, #"\mathscr{L}"#, #"a \bmod b"#, #"\varDelta \varGamma"#,
                        #"{\sf H}_2{\bf O} {\rm d} {\it a} {\tt b} {\cal L}"#, #"\dag \ddag \thinspace \medspace \thickspace \enspace x"#, #"\sqrt{\small x}"#, #"a \: b"#,
                        #"\begin{pmatrix} \color{red} a \color{black} & b \\ c & \color{blue} d \end{pmatrix}"#, #"\left( \color{red} x \right) y"#] {
            XCTAssertTrue(MathAttachment.canTypeset(LaTeXCompatibility.normalized(formula)), formula)
        }
        XCTAssertGreaterThan(try mathMetrics(#"1,\ldots,n"#).width, try mathMetrics(#"1,...,n"#).width, "Low dots as far apart as TeX sets them.")
    }

    /// A formula wider than its column breaks between the new constructs and after them, as
    /// it breaks around a fraction (patch 2).
    func testFormulasWithTheNewCommandsBreakToFitTheirWidth() throws {
        let formulas = [
            #"\boxed{a+b+c} + \cancel{d+e+f} + \boxed{g+h+i} + \cancel{j+k+l} + \boxed{m+n+o}"#,
            #"a \overset{b}{=} cdefghijklmnop \xrightarrow{q} rstuvwxyz \underset{a}{=} bcdefghijkl \xrightarrow{m} nopqrstuvwxyz"#,
            #"\boxed{abcdefghijklmnop} qrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"#,
            #"\big(abcdefgh\big) + \big(ijklmnop\big) + \big(qrstuvwx\big) + \big(yzabcdef\big) + \big(ghijklmn\big)"#,
        ]
        for formula in formulas {
            let latex = LaTeXCompatibility.normalized(formula)
            let natural = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: Self.mathFontSize), formula)
            let width = natural.width * 0.6
            let broken = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: Self.mathFontSize, fittingWidth: width), formula)
            // An operator after a display may hang past the width, as after a fraction or a root.
            XCTAssertLessThanOrEqual(broken.width, width + Self.mathFontSize, formula)
            XCTAssertGreaterThan(broken.ascent + broken.descent, 1.5 * (natural.ascent + natural.descent), formula)
        }
    }

    /// Inline math is drawn in pieces (Textual patch 21): a piece must not cut a new construct.
    func testInlineFormulasWithTheNewCommandsStayOneFormula() throws {
        for formula in [#"\boxed{a + b} + c"#, #"\xrightarrow[a+b]{c} + d"#, #"\big( a + b \big) + c"#, #"\overset{a+b}{=} c + d"#, #"\cancel{a + b} + c"#] {
            let drawn = LaTeXCompatibility.normalized(formula)
            XCTAssertEqual(try mathAttachmentCount(inMarkdown: "before $\(drawn)$ after"), 1, formula)
        }
    }

    // MARK: Patch 21, inline math breaks after its operators

    func testInlineMathBreaksAfterOperatorsAndRelationsAtItsOuterLevelOnly() {
        func pieces(_ latex: String) -> [String]? { InlineMathLineBreaks.pieces(of: latex) }
        XCTAssertEqual(pieces("(C_{jb} \\cdot L_A + C_{jsw})W + C_j \\cdot W \\cdot L/2"),
                       ["(C_{jb} \\cdot\\>", " L_A +\\>", " C_{jsw})W +\\>", " C_j \\cdot\\>", " W \\cdot\\>", " L/2"],
                       "the owner's table cell: after each operator, inside plain brackets too")
        XCTAssertEqual(pieces("C_{ox} \\cdot W \\cdot L \\parallel C_d"),
                       ["C_{ox} \\cdot\\>", " W \\cdot\\>", " L \\parallel\\;", " C_d"], "a relation ends with a thick space")
        XCTAssertEqual(pieces("E = mc^2"), ["E =\\;", " mc^2"])
        XCTAssertEqual(pieces("x \\le y"), ["x \\le\\;", " y"], "commands take their class from the typesetter")
        XCTAssertEqual(pieces("-x + y"), ["-x +\\>", " y"], "a leading sign is not an operator")
        XCTAssertEqual(pieces("a = -b"), ["a =\\;", " -b"], "nor is a sign after a relation")
        XCTAssertEqual(pieces("a := b"), ["a :=\\;", " b"], "never between two relations")
        XCTAssertEqual(pieces("\\{a + b\\}"), ["\\{a +\\>", " b\\}"], "escaped braces are brackets")
        XCTAssertEqual(pieces("x^+ y"), nil, "a script's operator is not at the outer level")
        for whole in ["k_n", "x^{a+b}", "\\frac{a+b}{c}", "\\sqrt[n+1]{a+b}", "\\left( a + b \\right)", "\\text{a + b}",
                      "\\begin{matrix} a + b \\end{matrix}", "a + b \\over c", "\\displaystyle a + b", "a + b}", "a + \\\\ b",
                      "a +", "\\operatorname*{arg} x"] {
            XCTAssertNil(pieces(whole), whole)
        }
    }

    func testFormulaInPiecesCopiesOnceAndKeepsItsWidth() throws {
        let attachments = try mathPieces(inMarkdown: "Energy $E = mc^2$ and $k_n$.")
        XCTAssertEqual(attachments.map(\.latex), ["E =\\;", " mc^2", "k_n"])
        XCTAssertEqual(attachments.map(\.description), ["$E = mc^2$", "", "$k_n$"], "a selection over both pieces copies the formula once")
        XCTAssertEqual(attachments.map(\.continuesFormula), [false, true, false])

        // The pieces side by side are as wide as the formula drawn whole: each operator keeps
        // its spacing at the end of its piece.
        for latex in ["(C_{jb} \\cdot L_A + C_{jsw})W + C_j \\cdot W \\cdot L/2", "C_{ox} \\cdot W \\cdot L \\parallel C_d \\cdot W \\cdot L"] {
            let whole = try XCTUnwrap(InlineMathRendering.metrics(for: latex, fontSize: 17)).width
            let pieces = try XCTUnwrap(MathAttachment.inlinePieces(of: latex))
            let piecesWidth = try pieces.reduce(CGFloat(0)) { width, piece in
                width + (try XCTUnwrap(InlineMathRendering.metrics(for: piece.latex, fontSize: 17))).width
            }
            XCTAssertEqual(piecesWidth, whole, accuracy: 0.5, latex)
        }
    }

    /// The owner's "Capacitances by region": in Obsidian its formulas wrap and the table
    /// fits the note; drawn whole, each kept its column as wide as itself and the table scrolled.
    func testTableColumnOfLongFormulasShrinksToItsWidestPiece() async throws {
        let formula = "$(C_{jb} \\cdot L_A + C_{jsw})W + C_j \\cdot W \\cdot L/2$"
        let markdown = "| Capacitance | Triode region |\n| --- | --- |\n| $C_{SB}$ | \(formula) |\n"
        let unwrapped = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000, syntaxExtensions: [.math]) { layout in
            layout.numberOfRows == 2 && layout.bounds.width > 100
        }
        let narrow = unwrapped.bounds.width / 2
        let wrapped = try await tableLayout(ofMarkdown: markdown, offeredWidth: narrow, syntaxExtensions: [.math]) { layout in
            layout.numberOfRows == 2 && layout.bounds.width <= narrow
        }
        XCTAssertLessThanOrEqual(wrapped.bounds.width, narrow, "the table fits half its one-line width")
        XCTAssertGreaterThan(wrapped.rowBounds(1).height, unwrapped.rowBounds(1).height * 1.5, "the formula wraps onto more lines")
    }

    // MARK: Patch 8, empty table cells keep their place

    func testEmptyCellsAndRowsKeepTheirPlaceInATable() throws {
        let markdown = "|  | A | B |\n| --- | --- | --- |\n| x |  | z |\n|  |  |  |\n| p | q | r |\n"
        let attributed = try AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: []).attributedString(for: markdown)
        let table = try XCTUnwrap(attributed.blockRuns().first)
        let cellContents = StructuredText.Table.cellContents(in: attributed[table.range], tableIntent: table.intent, columnCount: 3)
        let cellTexts = cellContents.map { row in row.map { cell in String(cell.characters[...]) } }
        XCTAssertEqual(cellTexts, [["", "A", "B"], ["x", "", "z"], ["", "", ""], ["p", "q", "r"]])
    }

    /// The header `| | A long heading | B |` used to put the long heading over the first
    /// column, because the empty cell before it was not laid out.
    func testHeadingAfterAnEmptyCellStaysOverItsColumn() async throws {
        let markdown = "|  | A long heading over the second column | B |\n| --- | --- | --- |\n| x | y | z |\n"
        let layout = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000) { layout in layout.numberOfRows == 2 }
        XCTAssertEqual(layout.numberOfColumns, 3)
        XCTAssertGreaterThan(layout.cellBounds(row: 0, column: 1).width, layout.cellBounds(row: 0, column: 0).width * 4)
    }

    /// The layout of the table in `markdown` inside a frame `offeredWidth` wide, once it
    /// satisfies `isSettled`: images load after the first layout.
    private func tableLayout(ofMarkdown markdown: String, offeredWidth: CGFloat,
                             syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = [],
                             isSettled: (StructuredText.TableLayout) -> Bool) async throws -> StructuredText.TableLayout {
        let recorder = TableLayoutRecorder()
        let table = StructuredText(markdown: markdown, syntaxExtensions: syntaxExtensions)
            .textual.imageAttachmentLoader(ShrinkingFigureLoader())
            .textual.tableStyle(RecordingTableStyle(offeredWidth: offeredWidth, recorder: recorder))
            .textual.tableCellStyle(BareTableCellStyle())
        let hostingView = NSHostingView(rootView: table.frame(width: 3000, alignment: .leading))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 3000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        defer { window.contentView = nil }
        for _ in 0..<60 {
            hostingView.layoutSubtreeIfNeeded()
            if let layout = recorder.layout, isSettled(layout) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(recorder.layout, "the table was never laid out")
    }
}

@MainActor
private final class TableLayoutRecorder {
    var layout: StructuredText.TableLayout?
}

/// Offers the table a fixed width and records where its cells end up.
private struct RecordingTableStyle: StructuredText.TableStyle {
    let offeredWidth: CGFloat
    let recorder: TableLayoutRecorder

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: 1, vertical: 1)
            .textual.tableOverlay { layout in
                // Recorded as the overlay is built: in a window that is never shown, `onChange`
                // drops all but the first change of a frame that never ends.
                let _ = MainActor.assumeIsolated { recorder.layout = layout }
                Color.clear
            }
            .frame(width: offeredWidth, alignment: .leading)
    }
}

/// Cells without padding, so a column is as wide as its content.
private struct BareTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// A figure that fits the width it is offered, as an image does; half as tall as it is wide.
private struct ShrinkingFigureAttachment: Attachment {
    let naturalWidth: CGFloat
    var description: String { "figure" }
    var body: some View { Color.blue }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = min(proposal.width ?? naturalWidth, naturalWidth)
        return CGSize(width: width, height: width / 2)
    }
}

private struct ShrinkingFigureLoader: AttachmentLoader {
    static let naturalWidth: CGFloat = 400

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> ShrinkingFigureAttachment {
        ShrinkingFigureAttachment(naturalWidth: Self.naturalWidth)
    }
}
