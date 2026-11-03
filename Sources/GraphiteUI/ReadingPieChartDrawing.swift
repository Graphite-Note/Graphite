/**
 * File: ReadingPieChartDrawing.swift
 * ----------------------------------
 * Layer: UI
 * Description: A laid-out pie chart in the reading view.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out pie chart, centered and as wide as it was laid out (in proportion to the text size now, if that changed
/// since the note was built), scaled down when the column is narrower.
/// One too wide to stay readable scrolls sideways (`ReadingScaledDiagram`).
struct ReadingPieChartDrawing: View {
    let chart: ReadingPieChart
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: chart.layout.size, layoutTextSize: chart.layout.font.size, textSize: textSize) {
            ReadingPieChartPainting(shapes: chart.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(chart.title ?? "Pie chart")
        .accessibilityValue(chart.description ?? chart.sliceSummaries.joined(separator: ", "))
    }
}

/// The pie chart's shapes and text at the layout's size, back to front as Pele draws them: the slices in the series
/// colors with edges of the background between them, the percentages, the legend and the title.
private struct ReadingPieChartPainting: View {
    let shapes: ReadingPieChartShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(shapes.seriesFills.indices, id: \.self) { index in
                shapes.seriesFills[index].fill(colors.series[index % colors.series.count])
            }
            shapes.sliceEdges.stroke(colors.background, style: Self.lineStyle)
            shapes.emptyPieOutline.stroke(colors.border, style: Self.lineStyle)
            lines(shapes.insidePercentageLines, color: colors.background)
            lines(shapes.textLines, color: colors.foreground)
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

    private static let lineStyle = StrokeStyle(lineWidth: PieChartDrawingParts.lineWidth, lineJoin: .round)
}
