/**
 * File: InlineMathPieces.swift
 * ----------------------------
 * Layer: Vendor (Textual)
 * Description: Graphite patch: where inline math may break, for text views outside SwiftUI that draw a formula
 *              in pieces among their own text, as the reading view draws it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

/// Graphite addition: inline math cut where a line may break, as ``StructuredText`` cuts it:
/// after a binary operator or a relation at the formula's outer level (`InlineMathLineBreaks`).
/// Graphite's Live Preview editor draws a long `$…$` in these pieces among its own text, so it
/// wraps where the reading view and tables wrap it.
public enum InlineMathPieces {
  /// One piece of a formula.
  public struct Piece: Equatable, Sendable {
    /// The piece's characters in the formula it was cut from.
    public let range: Range<String.Index>
    /// The space TeX puts after the operator that ends the piece (`\>` after a binary operator,
    /// `\;` after a relation), which the piece is typeset with; empty for the last piece.
    public let spaceAfterOperator: String
  }

  /// The formula cut after each operator where a line may break, in order; nil when it has no
  /// such place, or when cutting it could change how it is drawn (a style switch or an infix
  /// fraction at its outer level).
  public static func pieces(of latex: String) -> [Piece]? {
    let characters = Array(latex)
    guard let cuts = InlineMathLineBreaks.cuts(of: characters) else {
      return nil
    }
    var pieces: [Piece] = []
    var pieceStart = latex.startIndex
    var pieceStartOffset = 0
    for cut in cuts {
      let pieceEnd = latex.index(pieceStart, offsetBy: cut.offset - pieceStartOffset)
      pieces.append(Piece(range: pieceStart..<pieceEnd, spaceAfterOperator: cut.spaceAfterOperator))
      pieceStart = pieceEnd
      pieceStartOffset = cut.offset
    }
    pieces.append(Piece(range: pieceStart..<latex.endIndex, spaceAfterOperator: ""))
    return pieces
  }
}
