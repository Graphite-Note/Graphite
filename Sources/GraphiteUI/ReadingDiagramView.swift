/**
 * File: ReadingDiagramView.swift
 * ------------------------------
 * Layer: UI
 * Description: A mermaid block in the reading view, and the flowchart's painting.
 *
 * Authors: Félix Chevalier
 * Version: 0.17
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block in the reading view: a diagram of a type drawn natively, painted in the note's colors and
/// centered, scaled down when the column is narrower; or the block's source with why it could not be drawn.
struct ReadingDiagramView: View {
    let diagram: ReadingDiagram
    let textSize: Double
    let root: URL
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void

    var body: some View {
        if diagram.unappliedStatementCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                drawing
                // The diagram has styling or click actions that are read and not applied: it may look different from Obsidian's.
                Label("Some styling or click actions in this diagram are not applied here.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            drawing
        }
    }

    @ViewBuilder private var drawing: some View {
        switch diagram {
        case .flowchart(let flowchart):
            ReadingFlowchartDrawing(flowchart: flowchart, textSize: textSize)
        case .pieChart(let chart):
            ReadingPieChartDrawing(chart: chart, textSize: textSize)
        case .ganttChart(let chart):
            ReadingGanttChartDrawing(chart: chart, textSize: textSize)
        case .unreadable(let source, let failure):
            VStack(alignment: .leading, spacing: 6) {
                ObsidianMarkdownText(markdown: "```mermaid\n" + source + "\n```", root: root, textSize: textSize, navigate: navigate,
                                     scrollToHeading: scrollToHeading)
                Label(failure.explanation, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .stateDiagram(let stateDiagram):
            ReadingStateDiagramDrawing(diagram: stateDiagram, textSize: textSize)
        case .classDiagram(let classDiagram):
            ReadingClassDiagramDrawing(diagram: classDiagram, textSize: textSize)
        case .sequence(let sequence):
            ReadingSequenceDrawing(sequence: sequence, textSize: textSize)
        case .entityRelationship(let entityRelationship):
            ReadingEntityRelationshipDrawing(diagram: entityRelationship, textSize: textSize)
        case .mindmap(let mindmap):
            ReadingMindmapDrawing(mindmap: mindmap, textSize: textSize)
        case .timeline(let timeline):
            ReadingTimelineDrawing(timeline: timeline, textSize: textSize)
        case .gitGraph(let gitGraph):
            ReadingGitGraphDrawing(gitGraph: gitGraph, textSize: textSize)
        case .userJourney(let journey):
            ReadingUserJourneyDrawing(journey: journey, textSize: textSize)
        case .quadrantChart(let chart):
            ReadingQuadrantChartDrawing(chart: chart, textSize: textSize)
        case .xyChart(let chart):
            ReadingXYChartDrawing(chart: chart, textSize: textSize)
        case .sankey(let diagram):
            ReadingSankeyDrawing(diagram: diagram, textSize: textSize)
        }
    }
}

/// A laid-out flowchart, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower. One too wide to stay readable scrolls
/// sideways (`ReadingScaledDiagram`).
private struct ReadingFlowchartDrawing: View {
    let flowchart: ReadingFlowchart
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: flowchart.layout.size, layoutTextSize: flowchart.layout.font.size, textSize: textSize) {
            ReadingFlowchartPainting(shapes: flowchart.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(flowchart.title ?? "Flowchart")
        .accessibilityValue(flowchart.description ?? flowchart.nodeTexts.joined(separator: ", "))
    }
}

/// The flowchart's shapes and text at the layout's size, back to front as Pele draws them.
private struct ReadingFlowchartPainting: View {
    let shapes: ReadingFlowchartShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ReadingFlowchartClusterBoxes(clusters: shapes.clusters, colors: colors)
            shapes.solidEdges.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            shapes.thickEdges.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.thickLineWidth))
            shapes.dottedEdges.stroke(colors.foreground,
                                      style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth, dash: FlowchartDrawingParts.dottedDashLengths))
            shapes.filledMarks.fill(colors.foreground)
            shapes.strokedMarks.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            ForEach(shapes.styledEdges.indices, id: \.self) { index in styledEdge(shapes.styledEdges[index]) }
            ReadingFlowchartCrossedClusterTitles(clusters: shapes.clusters, colors: colors)
            shapes.edgeTextPatches.fill(colors.background)
            lines(shapes.edgeTextLines)
            shapes.nodeFills.fill(colors.surface)
            shapes.nodeOutlines.stroke(colors.border, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            ForEach(shapes.styledNodes.indices, id: \.self) { index in styledNode(shapes.styledNodes[index]) }
            lines(shapes.nodeTextLines)
            ForEach(shapes.styledNodes.indices, id: \.self) { index in
                let node = shapes.styledNodes[index]
                ReadingDiagramTextLines(lines: node.textLines, color: node.style.textColor.map { color in Color(color) } ?? colors.foreground)
            }
        }
    }

    /// An edge with its own stroke or colors: the line, then its marks, in its color or the usual line color.
    private func styledEdge(_ edge: ReadingFlowchartStyledEdge) -> some View {
        let color = edge.color.map { color in Color(color) } ?? colors.foreground
        return ZStack(alignment: .topLeading) {
            edge.line.stroke(color, style: Self.lineStyle(width: edge.lineWidth, dash: edge.dashLengths))
            edge.filledMarks.fill(color)
            edge.strokedMarks.stroke(color, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
        }
    }

    /// A node with colors of its own: the inside in its fill, the outline in its stroke, the usual colors for what it leaves out.
    private func styledNode(_ node: ReadingFlowchartStyledNode) -> some View {
        ZStack(alignment: .topLeading) {
            if let shape = node.fill { shape.fill(node.style.fill.map { color in Color(color) } ?? colors.surface) }
            node.outline.stroke(node.style.stroke.map { color in Color(color) } ?? colors.border,
                                style: Self.lineStyle(width: node.lineWidth, dash: node.style.strokeDashLengths ?? []))
        }
    }

    private func lines(_ lines: [ReadingDiagramTextLine]) -> some View {
        ReadingDiagramTextLines(lines: lines, color: colors.foreground)
    }

    private static func lineStyle(width: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
    }
}

/// The groups' boxes behind everything, as Pele paints them: the fills depth by depth, each half of the alternate
/// surface over what is behind, the outlines, and the titles no edge crosses.
private struct ReadingFlowchartClusterBoxes: View {
    let clusters: ReadingFlowchartClusterShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(clusters.fillsByDepth.indices, id: \.self) { depth in
                clusters.fillsByDepth[depth].fill(colors.alternateSurface.opacity(FlowchartClusterDrawingParts.fillOpacity))
            }
            clusters.outlines.stroke(colors.border, lineWidth: FlowchartDrawingParts.lineWidth)
            ReadingDiagramTextLines(lines: clusters.titleLines, color: colors.muted)
        }
    }
}

/// The titles edges run through, over the edges, each on a patch painted as its box is where it sits: the background,
/// then the alternate surface at half its opacity once for each box around it and its own.
private struct ReadingFlowchartCrossedClusterTitles: View {
    let clusters: ReadingFlowchartClusterShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(clusters.crossedTitlePatchesByDepth.indices, id: \.self) { depth in
                ZStack(alignment: .topLeading) {
                    clusters.crossedTitlePatchesByDepth[depth].fill(colors.background)
                    ForEach(0...depth, id: \.self) { _ in
                        clusters.crossedTitlePatchesByDepth[depth].fill(colors.alternateSurface.opacity(FlowchartClusterDrawingParts.fillOpacity))
                    }
                }
            }
            ReadingDiagramTextLines(lines: clusters.crossedTitleLines, color: colors.muted)
        }
    }
}

/// Lines of a diagram's text, each centered where the layout put it, in one color.
private struct ReadingDiagramTextLines: View {
    let lines: [ReadingDiagramTextLine]
    let color: Color

    var body: some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(lines[index].swiftUIFont)
                .foregroundStyle(color)
                .fixedSize()
                .position(lines[index].center)
        }
    }
}
