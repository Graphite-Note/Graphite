/**
 * File: LivePreviewImageLine.swift
 * --------------------------------
 * Layer: UI
 * Description: Live Preview's drawing of a line or list item that shows images among its text: the pictures
 *              side by side at their sizes, wrapping at the column's width, with the text between them and the
 *              item's bullet or number before them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// A line such as `![[a.jpg|200]] ![[b.jpg|200]]` or `See ![[a.png|120]] here`, drawn as
/// Obsidian draws it: each picture at its `|width` (or `|widthxheight`), side by side
/// while they fit, then on the next row. Each picture is an ordinary Live Preview embed,
/// so it is looked up and decoded when the line comes into view, for the width it is
/// shown at, through the shared image cache; a tap on the text shows the source.
///
/// A list item (`- ![[a.jpg|200]] ![[b.jpg|200]]`) has its bullet or number before the
/// pictures, as wide as the editor draws its marker and indentation, so it lines up with the
/// list's other items; the rows the pictures wrap onto start under the first picture.
struct LivePreviewImageLineView: View {
    let pieces: [ImageLinePiece]
    let environment: LivePreviewEnvironment
    let revealSource: () -> Void

    var body: some View {
        if case .listMarker(let marker)? = pieces.first {
            HStack(alignment: .imageLineFirstRowBottom, spacing: 0) {
                ImageLineListMarkerView(marker: marker, environment: environment)
                    .alignmentGuide(.imageLineFirstRowBottom) { dimensions in dimensions[.bottom] }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: revealSource)
                flow(of: Array(pieces.dropFirst()))
            }
        } else {
            flow(of: pieces)
        }
    }

    private func flow(of pieces: [ImageLinePiece]) -> some View {
        ImageLineFlowLayout {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                // Only ever the first piece, drawn before the flow.
                case .listMarker:
                    EmptyView()
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
        let markerWidth: CGFloat = pieces.contains { piece in if case .listMarker = piece { true } else { false } } ? estimatedMarkerWidth : 0
        let columnWidth = max(columnWidth - markerWidth, 1)
        let sizes = pieces.compactMap { piece -> CGSize? in
            switch piece {
            case .listMarker:
                return nil
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
    /// A bullet and its space, about three characters.
    nonisolated private static let estimatedMarkerWidth: CGFloat = 24
}

extension VerticalAlignment {
    private enum ImageLineFirstRowBottom: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[.bottom] }
    }

    /// The bottom of an image line's first row, which a list item's marker stands on, as text
    /// stands on the bottom of the pictures beside it.
    static let imageLineFirstRowBottom = VerticalAlignment(ImageLineFirstRowBottom.self)
}

/// A list item's bullet or number, drawn where the editor draws it on the item's other lines:
/// after the item's indentation, followed by the space before its text, all as wide as that
/// text is in the note's font. A bullet is a dot centered on the lowercase letters, as the
/// editor draws one (`ConcealedReplacementLayoutFragment`); a number is shown as written.
struct ImageLineListMarkerView: View {
    let marker: ImageLineListMarker
    let environment: LivePreviewEnvironment

    var body: some View {
        let font = environment.typography.textFont(ofSize: environment.textSize)
        let widths = Self.widths(of: marker, in: font)
        let color = environment.theme?.listMarkerColor.map { color in Color(color) } ?? .secondary
        ZStack(alignment: .leading) {
            Text(marker.isBullet ? "-" : marker.marker)
                .font(environment.typography.textSwiftUIFont(size: environment.textSize))
                .foregroundStyle(marker.isBullet ? AnyShapeStyle(.clear) : AnyShapeStyle(color))
                .fixedSize()
                .overlay {
                    if marker.isBullet {
                        let diameter = max(5, font.pointSize * 0.3)
                        GeometryReader { proxy in
                            Circle().fill(color).frame(width: diameter, height: diameter)
                                .position(x: proxy.size.width / 2, y: font.ascender - font.xHeight / 2 + Self.lineTopPadding(of: font, height: proxy.size.height))
                        }
                    }
                }
                .padding(.leading, widths.indentation)
        }
        .frame(width: widths.total, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Where the bullet's line starts in the text's frame: SwiftUI centers the font's line in it.
    private static func lineTopPadding(of font: PlatformFont, height: CGFloat) -> CGFloat {
        max(0, (height - (font.ascender - font.descender)) / 2)
    }

    /// The indentation's width and the whole marker's, the indentation, marker and spacing as
    /// they are written, measured in the note's font as the editor lays them out. A tab is as
    /// wide as four spaces, where the editor's tab stops put the item's first tab.
    static func widths(of marker: ImageLineListMarker, in font: PlatformFont) -> (indentation: CGFloat, total: CGFloat) {
        func width(_ text: String) -> CGFloat {
            NSAttributedString(string: text.replacingOccurrences(of: "\t", with: "    "), attributes: [.font: font]).size().width
        }
        return (width(marker.indentation), width(marker.indentation + marker.marker + marker.spacing))
    }
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

    /// The bottom of the first row, for `imageLineFirstRowBottom`; the other guides are the
    /// layout's own edges.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .imageLineFirstRowBottom, let firstFrame = rows(of: subviews, availableWidth: bounds.width).frames.first else { return nil }
        return bounds.minY + firstFrame.maxY
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
