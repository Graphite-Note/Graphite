/**
 * File: ReadingGanttChartDrawing.swift
 * ------------------------------------
 * Layer: UI
 * Description: A laid-out Gantt chart in the reading view.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out Gantt chart, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower.
/// One too wide to stay readable scrolls sideways (`ReadingScaledDiagram`).
struct ReadingGanttChartDrawing: View {
    let chart: ReadingGanttChart
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: chart.layout.size, layoutTextSize: chart.layout.font.size, textSize: textSize) {
            ReadingGanttChartPainting(shapes: chart.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(chart.title ?? "Gantt chart")
        .accessibilityValue(chart.description ?? chart.taskNames.joined(separator: ", "))
    }
}

/// The Gantt chart's shapes and text at the layout's size, back to front as Pele draws them.
private struct ReadingGanttChartPainting: View {
    let shapes: ReadingGanttChartShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.sectionBands.fill(colors.surface)
            shapes.excludedDays.fill(colors.alternateSurface)
            shapes.gridLines.stroke(colors.border, style: StrokeStyle(lineWidth: GanttDrawingParts.lineWidth, dash: GanttDrawingParts.gridDashLengths))
            shapes.axisLines.stroke(colors.border, lineWidth: GanttDrawingParts.lineWidth)
            shapes.todayLine.stroke(colors.accent, lineWidth: GanttDrawingParts.todayLineWidth)
            shapes.todayMark.fill(colors.accent)
            ForEach(shapes.taskFills.indices, id: \.self) { index in
                shapes.taskFills[index].path.fill(color(of: shapes.taskFills[index].fill))
            }
            ForEach(shapes.taskOutlines.indices, id: \.self) { index in
                shapes.taskOutlines[index].path.stroke(color(of: shapes.taskOutlines[index].stroke),
                                                       style: StrokeStyle(lineWidth: GanttDrawingParts.lineWidth, lineJoin: .round))
            }
            lines(shapes.backgroundTextLines, color: colors.background)
            lines(shapes.foregroundTextLines, color: colors.foreground)
            lines(shapes.mutedTextLines, color: colors.muted)
        }
    }

    private func color(of fill: GanttTaskFill) -> Color {
        switch fill {
        case .accent: colors.accent
        case .faintAccent: colors.accent.opacity(GanttDrawingParts.faintFillOpacity)
        case .critical: colors.critical
        case .faintCritical: colors.critical.opacity(GanttDrawingParts.faintFillOpacity)
        case .alternateSurface: colors.alternateSurface
        }
    }

    private func color(of stroke: GanttTaskStroke) -> Color {
        switch stroke {
        case .accent: colors.accent
        case .critical: colors.critical
        case .border: colors.border
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
