/**
 * File: ReadingScaledDiagram.swift
 * --------------------------------
 * Layer: UI
 * Description: Places a prepared diagram in the reading column: its scene for a narrow column when the column needs it, scaled down to
 *              fit, or scrolling sideways once fitting would make its text too small to read (never on paper, which is always fitted).
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

import SwiftUI
import MermaidDiagrams

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

/// A prepared diagram's painting, centered and as wide as it was laid out (in proportion to the text size now, if
/// that changed since the note was built), scaled down when the column is narrower. The column shows the diagram's
/// scene for a narrow column only where the regular one could not be shrunk to fit and stay readable and the narrow one is
/// narrower (`shownScene(of:inColumnWidth:scaleAtNaturalWidth:)`): a chart configured 900 points wide in a 750-point column
/// is the regular one at 83 %, not the one laid out for a phone's 280 points. A diagram that would have to be
/// shrunk below `ReadingDiagramPresentation.smallestReadableScale` keeps that size instead and scrolls sideways, so its
/// text stays readable on an iPhone or an iPad in portrait.
struct ReadingScaledDiagram<Painting: View>: View {
    let prepared: PreparedMermaidDiagram
    /// The note's text size now.
    let textSize: Double
    /// The painting of the scene shown.
    @ViewBuilder let painting: (DiagramScene) -> Painting
    @State private var columnWidth: CGFloat = 0
    /// On paper the diagram is always fitted: paper does not scroll, and a drawing for a PDF
    /// shows no scroll view.
    @Environment(\.readingIsPrinted) private var isPrinted

    /// The share of the laid-out size the diagram is at the text size now: both scenes are laid out in one font.
    private var scaleAtNaturalWidth: CGFloat { CGFloat(textSize) / prepared.scene.font.size }

    var body: some View {
        let scene = Self.shownScene(of: prepared, inColumnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth)
        let naturalWidth = scene.size.width * scaleAtNaturalWidth
        let presentation = ReadingDiagramPresentation.presentation(naturalWidth: naturalWidth, scaleAtNaturalWidth: scaleAtNaturalWidth,
                                                                   columnWidth: columnWidth)
        Group {
            switch presentation {
            case .fitted:
                fitted(painting(scene), size: scene.size, naturalWidth: naturalWidth)
            case .scrolling where isPrinted:
                fitted(painting(scene), size: scene.size, naturalWidth: naturalWidth)
            case .scrolling(let scale):
                scrolling(painting(scene), size: scene.size, at: scale)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in columnWidth = width }
    }

    /// The scene a column `columnWidth` wide shows: the narrow one where the package would show it
    /// (`PreparedMermaidDiagram.showsNarrowScene(inColumnWidth:scale:)`) and the regular one, fitted to the column, would
    /// be smaller than `ReadingDiagramPresentation.smallestReadableScale`; the regular one otherwise. The narrow scene of a
    /// chart is laid out for the narrowest column (280 points), so a regular scene a little wider than the column reads
    /// better shrunk a little than redrawn for a phone.
    static func shownScene(of prepared: PreparedMermaidDiagram, inColumnWidth columnWidth: CGFloat,
                           scaleAtNaturalWidth: CGFloat) -> DiagramScene {
        guard let narrowScene = prepared.narrowScene,
              prepared.showsNarrowScene(inColumnWidth: columnWidth, scale: scaleAtNaturalWidth) else { return prepared.scene }
        let regular = ReadingDiagramPresentation.presentation(naturalWidth: prepared.scene.size.width * scaleAtNaturalWidth,
                                                              scaleAtNaturalWidth: scaleAtNaturalWidth, columnWidth: columnWidth)
        if case .fitted = regular { return prepared.scene }
        return narrowScene
    }

    /// As wide as it was laid out, and no wider than the column, scaled to the width it is given.
    private func fitted(_ painting: Painting, size: CGSize, naturalWidth: CGFloat) -> some View {
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
    private func scrolling(_ painting: Painting, size: CGSize, at scale: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            painting
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
