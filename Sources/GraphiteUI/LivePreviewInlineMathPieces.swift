/**
 * File: LivePreviewInlineMathPieces.swift
 * ---------------------------------------
 * Layer: UI
 * Description: Live Preview draws a long `$…$` formula of its own text in pieces a line can break between, after
 *              its top-level operators and relations, where the reading view and tables break it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore

/// A formula's source cut into the pieces Live Preview draws it in: each piece's part of the
/// `$…$` in the note, and the LaTeX it is typeset from. The reading view draws inline math in
/// the same pieces (Textual's `InlineMathPieces`, patch 26 over patch 21), so a long formula in
/// a paragraph wraps after `+`, `\cdot` or `=` instead of running past the column's edge.
///
/// Each piece is drawn as a formula is (`MarkdownTextStyler.drawInlineMath`): its source hidden,
/// its room kept after the character before its last, which never breaks from the last. A piece
/// that is not the last ends after its operator and the one space written after it, so the line
/// may break there as after any space; a formula written without that space (`a+b`) breaks
/// between its pieces only when it is wider than the line. The note's text is unchanged, so
/// the cursor shows the whole formula's source, copying gives `$…$` once, and Read Aloud reads
/// the formula from the source as one equation.
enum LivePreviewInlineMathPieces {
    struct Piece: Equatable {
        /// The piece's part of the formula's source, the first with the opening `$`, the last with the closing one.
        let range: NSRange
        /// The LaTeX the piece is typeset from: its characters, readable by the typesetter, and the space TeX puts
        /// after the operator that ends it.
        let latex: String
    }

    /// The pieces of the formula `$…$` at `formulaRange` of `source`; nil when it is drawn whole: it has no place to
    /// break, making it readable by the typesetter would change where it breaks, or a piece would have no character
    /// to keep its room on.
    static func pieces(ofFormulaAt formulaRange: NSRange, in source: NSString) -> [Piece]? {
        // Inline math only, `$…$`: display math (`$$…$$`) stays its source in the editor's text.
        let dollar: unichar = 0x24
        guard formulaRange.length > 2, NSMaxRange(formulaRange) <= source.length, source.character(at: formulaRange.location) == dollar,
              source.character(at: formulaRange.location + 1) != dollar, source.character(at: NSMaxRange(formulaRange) - 1) == dollar else { return nil }
        let latexRange = NSRange(location: formulaRange.location + 1, length: formulaRange.length - 2)
        let latex = source.substring(with: latexRange)
        guard let cuts = MarkdownTextStyler.inlineMathCuts(of: latex), cuts.count > 1 else { return nil }
        // Declarations such as `\bf` become groups once readable; a formula whose places to break that changes is drawn whole.
        // Most formulas are readable as written, and so is each of their pieces, which then need no rewriting of their own.
        let readableLatex = LaTeXCompatibility.normalized(latex)
        let isReadableAsWritten = readableLatex == latex
        if !isReadableAsWritten, MarkdownTextStyler.inlineMathCuts(of: readableLatex)?.count != cuts.count { return nil }
        let latexCharacters = latex as NSString
        var pieces: [Piece] = []
        var pieceStart = formulaRange.location
        var pendingLatex = ""
        for (index, cut) in cuts.enumerated() {
            let cutRange = NSRange(cut.range, in: latex)
            pendingLatex += latex[cut.range]
            let isLast = index == cuts.count - 1
            var pieceEnd = isLast ? NSMaxRange(formulaRange) : latexRange.location + NSMaxRange(cutRange)
            // The space after the operator ends this piece, so the line may break right after it.
            if !isLast, NSMaxRange(cutRange) < latexCharacters.length, isSpaceOrTab(latexCharacters.character(at: NSMaxRange(cutRange))) {
                pieceEnd += 1
            }
            // The room is kept after the character before the piece's last: never a space, after which a line may
            // break, leaving the room at its end. Such a piece (`a +b`) is drawn with the next.
            guard isLast || (pieceEnd - pieceStart >= 2 && !isSpaceOrTab(source.character(at: pieceEnd - 2))) else { continue }
            pieces.append(Piece(range: NSRange(location: pieceStart, length: pieceEnd - pieceStart),
                                latex: (isReadableAsWritten ? pendingLatex : LaTeXCompatibility.normalized(pendingLatex)) + cut.spaceAfterOperator))
            pieceStart = pieceEnd
            pendingLatex = ""
        }
        guard pieces.count > 1, pieces.allSatisfy({ piece in piece.range.length >= 2 }) else { return nil }
        return pieces
    }

    private static func isSpaceOrTab(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }
}

extension MarkdownTextStyler {
    /// Draws the formula `$…$` at `range` in place of its source: in pieces a line can break between when it has
    /// them and each typesets, else whole. False when it cannot be typeset at all, and its source stays.
    func drawsInlineMath(over range: NSRange, source: NSString, baseFont: PlatformFont, in textStorage: NSTextStorage) -> Bool {
        if let pieces = LivePreviewInlineMathPieces.pieces(ofFormulaAt: range, in: source) {
            let lastIndex = pieces.count - 1
            let layouts = pieces.enumerated().compactMap { index, piece in
                inlineMathLayout(forLaTeX: piece.latex, baseFont: baseFont, leadingPadding: index == 0 ? InlineMathLayout.horizontalPadding : 0,
                                 trailingPadding: index == lastIndex ? InlineMathLayout.horizontalPadding : 0)
            }
            if layouts.count == pieces.count {
                for (piece, layout) in zip(pieces, layouts) { drawInlineMath(layout, over: piece.range, in: textStorage) }
                return true
            }
        }
        guard let layout = inlineMathLayout(for: source.substring(with: range), baseFont: baseFont) else { return false }
        drawInlineMath(layout, over: range, in: textStorage)
        return true
    }
}
