/**
 * File: ReadingScaledDiagram.swift
 * --------------------------------
 * Layer: UI
 * Description: Places a laid-out diagram in the reading column: scaled down to fit, or scrolling sideways once fitting would make its text too small to read.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI

/// How a laid-out diagram is shown in a column of some width.
enum ReadingDiagramPresentation: Equatable {
    /// The whole diagram, at `scale` times its laid-out size.
    case fitted(scale: CGFloat)
    /// The diagram at `scale` times its laid-out size, wider than the column, which scrolls sideways.
    case scrolling(scale: CGFloat)

    /// The smallest share of its natural size a diagram is squeezed to: 60 % of text laid out at 17 points is about 10
    /// points, the smallest text that stays readable. A wider diagram keeps this size and scrolls instead.
    static let smallestReadableScale: CGFloat = 0.6

    /// How a diagram `naturalWidth` wide (in proportion to the text size now) is shown in a column `columnWidth` wide.
    /// `scaleAtNaturalWidth` is the share of the laid-out size that natural width is, 1 unless the text size changed since
    /// the note was built. A column not measured yet (0) shows the diagram fitted, as it was before it scrolled.
    static func presentation(naturalWidth: CGFloat, scaleAtNaturalWidth: CGFloat, columnWidth: CGFloat) -> ReadingDiagramPresentation {
        guard naturalWidth > 0, columnWidth > 0 else { return .fitted(scale: scaleAtNaturalWidth) }
        let fittedScale = scaleAtNaturalWidth * min(1, columnWidth / naturalWidth)
        let smallestScale = scaleAtNaturalWidth * smallestReadableScale
        return fittedScale < smallestScale ? .scrolling(scale: smallestScale) : .fitted(scale: fittedScale)
    }
}

/// A laid-out diagram's painting, centered and as wide as it was laid out (in proportion to the text size now, if
/// that changed since the note was built), scaled down when the column is narrower. A diagram that would have to be
/// shrunk below `ReadingDiagramPresentation.smallestReadableScale` keeps that size instead and scrolls sideways, so its
/// text stays readable on an iPhone or an iPad in portrait.
struct ReadingScaledDiagram<Painting: View>: View {
    /// The size the diagram was laid out at.
    let size: CGSize
    /// The text size the diagram was laid out in.
    let layoutTextSize: CGFloat
    /// The note's text size now.
    let textSize: Double
    let painting: Painting
    @State private var columnWidth: CGFloat = 0

    init(size: CGSize, layoutTextSize: CGFloat, textSize: Double, @ViewBuilder painting: () -> Painting) {
        self.size = size
        self.layoutTextSize = layoutTextSize
        self.textSize = textSize
        self.painting = painting()
    }

    private var scaleAtNaturalWidth: CGFloat { CGFloat(textSize) / layoutTextSize }

    var body: some View {
        let naturalWidth = size.width * scaleAtNaturalWidth
        let presentation = ReadingDiagramPresentation.presentation(naturalWidth: naturalWidth, scaleAtNaturalWidth: scaleAtNaturalWidth,
                                                                   columnWidth: columnWidth)
        Group {
            switch presentation {
            case .fitted:
                fitted(naturalWidth: naturalWidth)
            case .scrolling(let scale):
                scrolling(at: scale)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in columnWidth = width }
    }

    /// As wide as it was laid out, and no wider than the column, scaled to the width it is given.
    private func fitted(naturalWidth: CGFloat) -> some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: naturalWidth)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    painting
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
    }

    /// At a size that stays readable, wider than the column, which scrolls sideways.
    private func scrolling(at scale: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            painting
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
