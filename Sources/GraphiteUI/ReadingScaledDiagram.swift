/**
 * File: ReadingScaledDiagram.swift
 * --------------------------------
 * Layer: UI
 * Description: Places a prepared diagram in the reading column: its scene for a narrow column when the column needs it, laid out
 *              again at the column's real width, scaled down to fit, or scrolling sideways once fitting would make its text too
 *              small to read (never on paper, which is always fitted).
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.10
 * Date: 27/11/2026
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
/// text stays readable on an iPhone or an iPad in portrait. The narrow scene is laid out again at the column's real
/// width, as Obsidian draws Pele at its container's width (`ReadingDiagramNarrowScenes`): until that is done, and where
/// the column rounds to the standard 280 points, the standard narrow scene is shown.
struct ReadingScaledDiagram<Painting: View>: View {
    let prepared: PreparedMermaidDiagram
    /// What the diagram was prepared from, to lay its narrow scene out again; nil to show the standard narrow scene.
    var source: ReadingDiagramSource? = nil
    /// The note's text size now.
    let textSize: Double
    /// The painting of the scene shown.
    @ViewBuilder let painting: (DiagramScene) -> Painting
    @State private var columnWidth: CGFloat = 0
    /// The narrow scene last laid out again for this view and the request it was for: setting it paints the view again
    /// once the scene is ready.
    @State private var redrawn: (request: ReadingDiagramNarrowRequest, scene: ReadingDiagramRedrawnNarrowScene)?
    /// The narrow scenes laid out again for this view's column widths, made when the column first asks for one.
    @State private var narrowScenes: ReadingDiagramNarrowScenes?
    /// On paper the diagram is always fitted: paper does not scroll, and a drawing for a PDF
    /// shows no scroll view.
    @Environment(\.readingIsPrinted) private var isPrinted
    /// When the column last changed width, in a build that measures it (`ReadingDiagramRelayoutTrace`); nil otherwise.
    @State private var columnWidthChange: ContinuousClock.Instant?
    /// The layout of a narrow scene for a column's width, given by a test that counts what is laid out.
    @Environment(\.readingDiagramNarrowLayout) private var narrowLayout

    /// The share of the laid-out size the diagram is at the text size now: both scenes are laid out in one font.
    private var scaleAtNaturalWidth: CGFloat { CGFloat(textSize) / prepared.scene.font.size }

    var body: some View {
        let narrowRequest = Self.narrowRequest(of: prepared, source: source, inColumnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth)
        let standardScene = Self.shownScene(of: prepared, inColumnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth)
        let redrawnScene = narrowRequest.flatMap { request in
            redrawn?.request == request ? redrawn?.scene : narrowScenes?.redrawnScene(for: request)
        }
        let readableRedrawnScene = Self.readableScene(redrawnScene?.scene, inColumnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth)
        let scene = readableRedrawnScene ?? standardScene
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
        #if canImport(UIKit)
        .environment(\.readingDiagramPlacement,
                     ReadingDiagramPlacement(columnWidth: columnWidth, textSize: textSize, diagramScene: prepared.scene.storageIdentifier))
        #endif
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in
            if let change = ReadingDiagramRelayoutTrace.columnDidChangeWidth(to: width) { columnWidthChange = change }
            columnWidth = width
        }
        #if DEBUG || GRAPHITE_DIAGRAM_TRACE
        .onChange(of: readableRedrawnScene == nil ? nil : narrowRequest) { _, shownRequest in
            if let shownRequest {
                ReadingDiagramRelayoutTrace.narrowSceneWasShown(forLayoutWidth: shownRequest.columnWidth, sinceColumnWidthChange: columnWidthChange)
            }
        }
        #endif
        .task(id: narrowRequest) { await layOutNarrowScene(for: narrowRequest) }
    }

    /// The narrow scene for `request` laid out again off the main actor (`ReadingDiagramNarrowScenes`), set as `redrawn`
    /// once ready unless the column moved on meanwhile. On paper the page is drawn at once: the standard narrow scene stays.
    private func layOutNarrowScene(for request: ReadingDiagramNarrowRequest?) async {
        guard let request, !isPrinted else { return }
        let scenes = narrowScenes ?? ReadingDiagramNarrowScenes()
        narrowScenes = scenes
        // A width laid out before is shown by the body already; asking for it still tells the scenes the column moved.
        let wasKept = scenes.redrawnScene(for: request) != nil
        guard let scene = await scenes.prepare(request, preparing: narrowLayout.layOut), !Task.isCancelled, !wasKept else { return }
        ReadingDiagramRelayoutTrace.narrowSceneIsReady(forLayoutWidth: request.columnWidth, sinceColumnWidthChange: columnWidthChange)
        redrawn = (request, scene)
    }

    /// A narrow scene laid out again for the column, where it fits the column without being shrunk below the readable
    /// scale; nil otherwise, and the standard narrow scene is shown. Pele draws a flowchart for a column of 640 points or
    /// more across, only tighter: for a 750-point column a long chain is laid out 2,130 points wide, which Obsidian shrinks
    /// to a third and which would scroll here, where the standard narrow scene runs down 155 points wide.
    static func readableScene(_ redrawn: DiagramScene?, inColumnWidth columnWidth: CGFloat, scaleAtNaturalWidth: CGFloat) -> DiagramScene? {
        guard let redrawn else { return nil }
        let presentation = ReadingDiagramPresentation.presentation(naturalWidth: redrawn.size.width * scaleAtNaturalWidth,
                                                                   scaleAtNaturalWidth: scaleAtNaturalWidth, columnWidth: columnWidth)
        guard case .fitted = presentation else { return nil }
        return redrawn
    }

    /// The narrow scene to lay out again for a column `columnWidth` wide: when the column shows the narrow scene
    /// (`shownScene(of:inColumnWidth:scaleAtNaturalWidth:)`) and its width in layout points, rounded
    /// (`ReadingDiagramNarrowWidth`), is not the standard 280 points; nil otherwise, or without a source.
    static func narrowRequest(of prepared: PreparedMermaidDiagram, source: ReadingDiagramSource?, inColumnWidth columnWidth: CGFloat,
                              scaleAtNaturalWidth: CGFloat) -> ReadingDiagramNarrowRequest? {
        guard let source, showsNarrowScene(of: prepared, inColumnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth),
              let layoutWidth = ReadingDiagramNarrowWidth.layoutWidth(columnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth)
        else { return nil }
        return ReadingDiagramNarrowRequest(source: source, columnWidth: layoutWidth)
    }

    /// The scene a column `columnWidth` wide shows: the narrow one where the package would show it
    /// (`PreparedMermaidDiagram.showsNarrowScene(inColumnWidth:scale:)`) and the regular one, fitted to the column, would
    /// be smaller than `ReadingDiagramPresentation.smallestReadableScale`; the regular one otherwise. The narrow scene of a
    /// chart is laid out for the narrowest column (280 points), so a regular scene a little wider than the column reads
    /// better shrunk a little than redrawn for a phone.
    static func shownScene(of prepared: PreparedMermaidDiagram, inColumnWidth columnWidth: CGFloat,
                           scaleAtNaturalWidth: CGFloat) -> DiagramScene {
        guard showsNarrowScene(of: prepared, inColumnWidth: columnWidth, scaleAtNaturalWidth: scaleAtNaturalWidth),
              let narrowScene = prepared.narrowScene else { return prepared.scene }
        return narrowScene
    }

    /// Whether a column `columnWidth` wide shows the diagram's narrow scene rather than its regular one
    /// (`shownScene(of:inColumnWidth:scaleAtNaturalWidth:)`). The regular scene's fit is asked first: since MermaidDiagrams
    /// 0.7.0 the package lays the narrow scene out the first time it is read, here on the main actor, so a diagram whose
    /// regular scene fits the column readably never lays its narrow one out.
    static func showsNarrowScene(of prepared: PreparedMermaidDiagram, inColumnWidth columnWidth: CGFloat, scaleAtNaturalWidth: CGFloat) -> Bool {
        let regular = ReadingDiagramPresentation.presentation(naturalWidth: prepared.scene.size.width * scaleAtNaturalWidth,
                                                              scaleAtNaturalWidth: scaleAtNaturalWidth, columnWidth: columnWidth)
        if case .fitted = regular { return false }
        return prepared.showsNarrowScene(inColumnWidth: columnWidth, scale: scaleAtNaturalWidth)
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

/// How a view lays a diagram's narrow scene out for a column's width: the diagram already read laid out again
/// (`ReadingDiagramNarrowRequest.narrowScene(of:)`), off the main actor; a test gives one that counts what is laid out.
struct ReadingDiagramNarrowLayout: Equatable, Sendable {
    /// Tells two layouts apart, as their work cannot be compared.
    let name: String
    let layOut: @Sendable (ReadingDiagramNarrowRequest) -> DiagramScene?

    static let package = ReadingDiagramNarrowLayout(name: "package", layOut: ReadingDiagramNarrowRequest.narrowScene(of:))

    static func == (leftLayout: ReadingDiagramNarrowLayout, rightLayout: ReadingDiagramNarrowLayout) -> Bool {
        leftLayout.name == rightLayout.name
    }
}

extension EnvironmentValues {
    @Entry var readingDiagramNarrowLayout = ReadingDiagramNarrowLayout.package
}
