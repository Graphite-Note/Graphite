/**
 * File: ReadingStateDiagramDrawing.swift
 * --------------------------------------
 * Layer: UI
 * Description: A laid-out state diagram in the reading view.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out state diagram, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower.
/// One too wide to stay readable scrolls sideways (`ReadingScaledDiagram`).
struct ReadingStateDiagramDrawing: View {
    let diagram: ReadingStateDiagram
    let textSize: Double
    @Environment(\.noteTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReadingScaledDiagram(size: diagram.layout.size, narrowSize: diagram.narrow?.layout.size, layoutTextSize: diagram.layout.font.size,
                             textSize: textSize) { variant in
            ReadingStateDiagramPainting(shapes: variant == .narrow ? diagram.narrow?.shapes ?? diagram.shapes : diagram.shapes,
                                        colors: ReadingDiagramColors(theme: theme, colorScheme: colorScheme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(diagram.title ?? "State diagram")
        .accessibilityValue(diagram.description ?? diagram.stateNames.joined(separator: ", "))
    }
}

/// The state diagram's shapes and text at the layout's size, back to front as Pele draws them.
private struct ReadingStateDiagramPainting: View {
    let shapes: ReadingStateDiagramShapes
    let colors: ReadingDiagramColors

    var body: some View {
        let lineStyle = StrokeStyle(lineWidth: StateDiagramDrawingParts.lineWidth, lineCap: .round, lineJoin: .round)
        ZStack(alignment: .topLeading) {
            ReadingFlowchartClusterBoxes(clusters: shapes.composites, colors: colors)
            shapes.regionDividers.stroke(colors.border, style: StrokeStyle(lineWidth: StateDiagramDrawingParts.lineWidth, lineCap: .round,
                                                                           dash: StateDiagramDrawingParts.noteConnectorDashLengths))
            shapes.transitionLines.stroke(colors.line, style: lineStyle)
            shapes.noteConnectors.stroke(colors.border, style: StrokeStyle(lineWidth: StateDiagramDrawingParts.lineWidth, lineCap: .round, lineJoin: .round,
                                                                           dash: StateDiagramDrawingParts.noteConnectorDashLengths))
            shapes.arrows.fill(colors.line)
            ReadingFlowchartCrossedClusterTitles(clusters: shapes.composites, colors: colors)
            shapes.transitionTextPatches.fill(colors.background)
            lines(shapes.transitionTextLines, color: colors.foreground)
            shapes.stateFills.fill(colors.surface)
            shapes.stateOutlines.stroke(colors.border, style: lineStyle)
            shapes.endRings.fill(colors.background)
            shapes.endRings.stroke(colors.line, style: lineStyle)
            shapes.solidMarks.fill(colors.line)
            lines(shapes.stateTextLines, color: colors.foreground)
            shapes.noteSheets.fill(colors.background)
            shapes.noteSheets.stroke(colors.border, style: lineStyle)
            shapes.noteFolds.stroke(colors.border, style: lineStyle)
            lines(shapes.noteTextLines, color: colors.background.mix(with: colors.foreground, by: Double(DiagramPalette.noteTextShare), in: .device))
        }
    }

    private func lines(_ lines: [ReadingDiagramTextLine], color: Color) -> some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(lines[index].swiftUIFont)
                .foregroundStyle(color)
                .fixedSize()
                .position(lines[index].center)
        }
    }
}
