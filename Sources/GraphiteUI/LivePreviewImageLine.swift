/**
 * File: LivePreviewImageLine.swift
 * --------------------------------
 * Layer: UI
 * Description: Live Preview's drawing of a line that shows images among its text: the pictures side by side
 *              at their sizes, wrapping at the column's width, with the text between them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import SwiftUI
import GraphiteCore

/// A line such as `![[a.jpg|200]] ![[b.jpg|200]]` or `See ![[a.png|120]] here`, drawn as
/// Obsidian draws it: each picture at its `|width` (or `|widthxheight`), side by side
/// while they fit, then on the next row. Each picture is an ordinary Live Preview embed,
/// so it is looked up and decoded when the line comes into view, for the width it is
/// shown at, through the shared image cache; a tap on the text shows the source.
struct LivePreviewImageLineView: View {
    let pieces: [ImageLinePiece]
    let environment: LivePreviewEnvironment
    let revealSource: () -> Void

    var body: some View {
        ImageLineFlowLayout {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .text(let text):
                    RenderedMarkdownBlock(markdown: text, environment: environment)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: revealSource)
                        .layoutValue(key: ImageLinePieceSizing.self, value: .text)
                case .image(let embed):
                    LivePreviewEmbedView(embed: embed, environment: environment, revealSource: revealSource)
                        .layoutValue(key: ImageLinePieceSizing.self, value: .picture(width: embed.displayWidth.map { width in CGFloat(width) }))
                }
            }
        }
    }

    /// The line's height before its view has measured itself: its pictures at their widths,
    /// four by three where no height is given, and its text as a line of text, in rows as
    /// `ImageLineFlowLayout` places them.
    nonisolated static func estimatedHeight(of pieces: [ImageLinePiece], columnWidth: CGFloat) -> CGFloat {
        let sizes = pieces.map { piece -> CGSize in
            switch piece {
            case .text(let text):
                return CGSize(width: min(columnWidth, CGFloat(text.count) * estimatedCharacterWidth), height: estimatedTextHeight)
            case .image(let embed):
                let width = min(embed.displayWidth.map { width in CGFloat(width) } ?? columnWidth, columnWidth)
                return CGSize(width: width, height: embed.displaySize?.height.map { height in CGFloat(height) } ?? width * 3 / 4)
            }
        }
        return ImageLineFlowLayout.rows(of: sizes, availableWidth: columnWidth).size.height + 8
    }

    nonisolated private static let estimatedCharacterWidth: CGFloat = 8
    nonisolated private static let estimatedTextHeight: CGFloat = 24
}

/// How `ImageLineFlowLayout` offers a piece its width.
enum ImageLinePieceSizing: LayoutValueKey {
    /// Text takes the width it needs on one line, and wraps on a row of its own when that
    /// is more than is left.
    case text
    /// A picture is offered its given width, or the column's, never more than the column.
    case picture(width: CGFloat?)

    static let defaultValue = ImageLinePieceSizing.text
}

/// Pieces placed like words: side by side while they fit the width, then on the next row,
/// the pieces of a row standing on its bottom edge, as pictures and text share a line.
struct ImageLineFlowLayout: Layout {
    /// Between pieces in a row and between rows, about a space between two pictures.
    nonisolated static let spacing: CGFloat = 4

    struct Rows {
        /// Each piece's frame, from the layout's top-left corner.
        var frames: [CGRect]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(of: subviews, availableWidth: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = rows(of: subviews, availableWidth: bounds.width)
        for (subview, frame) in zip(subviews, placed.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func rows(of subviews: Subviews, availableWidth proposedWidth: CGFloat?) -> Rows {
        let availableWidth = proposedWidth.flatMap { width in width.isFinite ? max(width, 1) : nil }
        return Self.rows(count: subviews.count, availableWidth: availableWidth ?? .infinity) { index, remainingWidth, startsRow in
            let subview = subviews[index]
            switch subview[ImageLinePieceSizing.self] {
            case .picture(let width):
                let offeredWidth = [width, availableWidth].compactMap { width in width }.min()
                return subview.sizeThatFits(ProposedViewSize(width: offeredWidth, height: nil))
            case .text:
                let idealSize = subview.sizeThatFits(.unspecified)
                // Too long for what is left of a row: on a row of its own it wraps there.
                guard idealSize.width > remainingWidth, startsRow else { return idealSize }
                return subview.sizeThatFits(ProposedViewSize(width: remainingWidth, height: nil))
            }
        }
    }

    /// Rows of pieces of known sizes, as the height estimate places them.
    nonisolated static func rows(of sizes: [CGSize], availableWidth: CGFloat) -> Rows {
        rows(count: sizes.count, availableWidth: max(availableWidth, 1)) { index, _, _ in sizes[index] }
    }

    /// - Parameter measure: A piece's size, given the width left in the row and whether it
    ///   would start the row; a piece wider than what is left moves to the next row and is
    ///   measured again there.
    nonisolated private static func rows(count: Int, availableWidth: CGFloat, measure: (Int, CGFloat, Bool) -> CGSize) -> Rows {
        var frames: [CGRect] = []
        var rowStartIndex = 0
        var rowEndX: CGFloat = 0
        var rowTop: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0
        func endRow() {
            for index in rowStartIndex..<frames.count { frames[index].origin.y = rowTop + rowHeight - frames[index].height }
            widestRow = max(widestRow, rowEndX)
            rowTop += rowHeight + spacing
            rowStartIndex = frames.count
            rowEndX = 0
            rowHeight = 0
        }
        for index in 0..<count {
            let startsRow = frames.count == rowStartIndex
            var size = measure(index, startsRow ? availableWidth : availableWidth - rowEndX - spacing, startsRow)
            if !startsRow, rowEndX + spacing + size.width > availableWidth {
                endRow()
                size = measure(index, availableWidth, true)
            }
            let originX = frames.count == rowStartIndex ? 0 : rowEndX + spacing
            frames.append(CGRect(origin: CGPoint(x: originX, y: 0), size: size))
            rowEndX = originX + size.width
            rowHeight = max(rowHeight, size.height)
        }
        guard !frames.isEmpty else { return Rows(frames: [], size: .zero) }
        endRow()
        return Rows(frames: frames, size: CGSize(width: widestRow, height: rowTop - spacing))
    }
}
