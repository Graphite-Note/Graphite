/**
 * File: PDFMarkupOverlap.swift
 * ----------------------------
 * Layer: Apple
 * Description: What marking text does where a mark of the same kind is already on it: nothing, a change of that
 *              mark's colour, one mark joining the marks it overlaps, or a new mark. Plain rectangles in, a plain
 *              outcome out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import CoreGraphics

/// What marking text on one page does with the marks of the same kind already there, so a
/// highlight made again never stacks on itself and gets darker (multiply blending).
///
/// - No mark of the kind overlaps the text: a new mark.
/// - One mark covers all of the text: that mark takes the new colour, or stays as it is.
/// - Otherwise the text and every mark it overlaps become one mark in the new colour, one
///   line rectangle per run of text.
///
/// A highlight and an underline on the same text are two kinds; the caller passes only the
/// marks of the kind being made.
public enum PDFMarkupOverlap {
    public enum Outcome: Equatable, Sendable {
        /// A new mark with these lines.
        case add(lineBounds: [CGRect])
        /// The mark at this index already covers the text in this colour.
        case unchanged(markIndex: Int)
        /// The mark at this index covers the text and takes the new colour.
        case recolor(markIndex: Int)
        /// The marks at these indices are replaced by one mark with these lines.
        case join(markIndices: [Int], lineBounds: [CGRect])
    }

    /// One mark of the kind on the page: the rectangle of each of its lines, in page space,
    /// and whether it already has the colour being marked with.
    public struct ExistingMark: Equatable, Sendable {
        public let lineBounds: [CGRect]
        public let hasMarkingColor: Bool

        public init(lineBounds: [CGRect], hasMarkingColor: Bool) {
            self.lineBounds = lineBounds
            self.hasMarkingColor = hasMarkingColor
        }
    }

    /// Two line rectangles closer than this along their line, in points, touch: marking
    /// "width" right after "band" joins them. The space between two words is wider.
    static let touchingDistance: CGFloat = 1
    /// Two rectangles are on the same line when they share at least this part of the
    /// shorter one's height; lines above and below share at most a sliver.
    static let sameLineOverlapFraction: CGFloat = 0.5

    /// The outcome of marking `lineBounds` over `existingMarks`. `runsVertically` is true for
    /// text turned a quarter (`PDFMarkupLineDirection.bottomToTop` or `.topToBottom`), whose
    /// lines run up or down the page.
    public static func outcome(ofMarking lineBounds: [CGRect], over existingMarks: [ExistingMark], runsVertically: Bool = false) -> Outcome {
        guard runsVertically else { return horizontalOutcome(ofMarking: lineBounds, over: existingMarks) }
        let transposedMarks = existingMarks.map { mark in
            ExistingMark(lineBounds: mark.lineBounds.map(transposed), hasMarkingColor: mark.hasMarkingColor)
        }
        switch horizontalOutcome(ofMarking: lineBounds.map(transposed), over: transposedMarks) {
        case .add(let joinedLines): return .add(lineBounds: joinedLines.map(transposed))
        case .join(let markIndices, let joinedLines): return .join(markIndices: markIndices, lineBounds: joinedLines.map(transposed))
        case .unchanged(let markIndex): return .unchanged(markIndex: markIndex)
        case .recolor(let markIndex): return .recolor(markIndex: markIndex)
        }
    }

    private static func horizontalOutcome(ofMarking lineBounds: [CGRect], over existingMarks: [ExistingMark]) -> Outcome {
        let overlappedIndices = indicesOfMarksOverlapping(lineBounds, in: existingMarks)
        guard !overlappedIndices.isEmpty else { return .add(lineBounds: lineBounds) }
        if overlappedIndices.count == 1, let markIndex = overlappedIndices.first,
           lineBounds.allSatisfy({ line in existingMarks[markIndex].lineBounds.contains { markLine in covers(markLine, line) } }) {
            return existingMarks[markIndex].hasMarkingColor ? .unchanged(markIndex: markIndex) : .recolor(markIndex: markIndex)
        }
        let allLines = lineBounds + overlappedIndices.flatMap { markIndex in existingMarks[markIndex].lineBounds }
        return .join(markIndices: overlappedIndices, lineBounds: joinedLines(allLines))
    }

    /// The marks that overlap the lines, in index order. A mark that only overlaps one of
    /// them is left as it is: recolouring a word never changes a mark elsewhere.
    private static func indicesOfMarksOverlapping(_ lineBounds: [CGRect], in existingMarks: [ExistingMark]) -> [Int] {
        existingMarks.indices.filter { markIndex in
            existingMarks[markIndex].lineBounds.contains { markLine in lineBounds.contains { line in overlaps(markLine, line) } }
        }
    }

    /// Whether two line rectangles are on the same line of text.
    static func areOnTheSameLine(_ firstLine: CGRect, _ secondLine: CGRect) -> Bool {
        let sharedHeight = min(firstLine.maxY, secondLine.maxY) - max(firstLine.minY, secondLine.minY)
        return sharedHeight >= sameLineOverlapFraction * min(firstLine.height, secondLine.height)
    }

    /// Whether two line rectangles are on the same line and overlap or touch along it.
    static func overlaps(_ firstLine: CGRect, _ secondLine: CGRect) -> Bool {
        areOnTheSameLine(firstLine, secondLine)
            && firstLine.minX <= secondLine.maxX + touchingDistance && secondLine.minX <= firstLine.maxX + touchingDistance
    }

    /// Whether `markLine` takes in all of `line` along their shared line.
    static func covers(_ markLine: CGRect, _ line: CGRect) -> Bool {
        areOnTheSameLine(markLine, line) && markLine.minX - touchingDistance <= line.minX && line.maxX <= markLine.maxX + touchingDistance
    }

    /// One rectangle per run of text: rectangles on one line that overlap or touch become
    /// their union. Lines come top to bottom, each line's runs left to right.
    static func joinedLines(_ lines: [CGRect]) -> [CGRect] {
        var joined: [CGRect] = []
        for line in lines {
            var grownLine = line
            // A grown line can reach a run it did not reach before, so it is matched again.
            while let touchedIndex = joined.firstIndex(where: { joinedLine in overlaps(joinedLine, grownLine) }) {
                grownLine = grownLine.union(joined.remove(at: touchedIndex))
            }
            joined.append(grownLine)
        }
        return joined.sorted { firstLine, secondLine in
            areOnTheSameLine(firstLine, secondLine) ? firstLine.minX < secondLine.minX : firstLine.midY > secondLine.midY
        }
    }

    private static func transposed(_ rectangle: CGRect) -> CGRect {
        CGRect(x: rectangle.minY, y: rectangle.minX, width: rectangle.height, height: rectangle.width)
    }
}
