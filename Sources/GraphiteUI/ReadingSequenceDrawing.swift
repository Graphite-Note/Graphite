/**
 * File: ReadingSequenceDrawing.swift
 * ----------------------------------
 * Layer: UI
 * Description: A laid-out sequence diagram in the reading view.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import MermaidDiagrams

/// A laid-out sequence diagram, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower, as a flowchart is.
struct ReadingSequenceDrawing: View {
    let sequence: ReadingSequence
    let textSize: Double
    @Environment(\.noteTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReadingScaledDiagram(size: sequence.layout.size, layoutTextSize: sequence.layout.font.size, textSize: textSize) {
            ReadingSequencePainting(shapes: sequence.shapes, colors: ReadingDiagramColors(theme: theme, colorScheme: colorScheme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(sequence.title ?? "Sequence diagram")
        .accessibilityValue(sequence.accessibilityValue)
    }
}

/// The sequence diagram's shapes and text at the layout's size, back to front as Pele draws them, in the note's
/// colors and, between its background and text, Pele's muted text and second surface.
private struct ReadingSequencePainting: View {
    let shapes: ReadingSequenceShapes
    let colors: ReadingDiagramColors

    private var muted: Color {
        colors.background.mix(with: colors.foreground, by: SequenceDrawingParts.mutedShare, in: .device)
    }

    private var surfaceAlternate: Color {
        colors.background.mix(with: colors.foreground, by: SequenceDrawingParts.surfaceAlternateShare, in: .device)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(shapes.highlights.indices, id: \.self) { index in
                shapes.highlights[index].path.fill(highlightColor(shapes.highlights[index].color))
            }
            shapes.lifelines.stroke(colors.border, style: Self.lineStyle)
            ForEach(shapes.activations.indices, id: \.self) { index in
                shapes.activations[index].fill(colors.surface)
                shapes.activations[index].stroke(colors.border, style: Self.lineStyle)
            }
            blocks
            shapes.solidMessageLines.stroke(colors.line, style: Self.lineStyle)
            shapes.dottedMessageLines.stroke(colors.line, style: Self.dashedLineStyle)
            shapes.filledHeads.fill(colors.line)
            shapes.strokedHeads.stroke(colors.line, style: Self.lineStyle)
            shapes.numberBadges.fill(colors.foreground)
            lines(shapes.numberTextLines, color: colors.background)
            shapes.messageTextPatches.fill(colors.background)
            lines(shapes.messageTextLines, color: colors.foreground)
            shapes.notes.fill(surfaceAlternate)
            shapes.notes.stroke(colors.border, style: Self.lineStyle)
            shapes.participantShapes.fill(colors.surface)
            shapes.participantShapes.stroke(colors.border, style: Self.lineStyle)
            shapes.participantFigureLines.stroke(colors.border, style: Self.lineStyle)
            lines(shapes.topTextLines, color: colors.foreground)
        }
    }

    /// The frames, their dashed section lines, the texts in them on their patches, and the tabs with their keywords.
    private var blocks: some View {
        ZStack(alignment: .topLeading) {
            shapes.blockOutlines.stroke(colors.border, style: Self.lineStyle)
            shapes.blockSectionLines.stroke(colors.border, style: Self.dashedLineStyle)
            shapes.blockTextPatches.fill(colors.background)
            lines(shapes.blockTextLines, color: muted)
            shapes.blockTabs.fill(colors.surface)
            shapes.blockTabs.stroke(colors.border, style: Self.lineStyle)
            lines(shapes.blockKeywordLines, color: muted)
        }
    }

    private func highlightColor(_ color: SequenceHighlightColor?) -> Color {
        guard let color else { return surfaceAlternate.opacity(SequenceDrawingParts.defaultHighlightOpacity) }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
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

    private static let lineStyle = StrokeStyle(lineWidth: SequenceDrawingParts.lineWidth, lineCap: .round, lineJoin: .round)
    private static let dashedLineStyle = StrokeStyle(lineWidth: SequenceDrawingParts.lineWidth, lineCap: .round, lineJoin: .round,
                                                     dash: SequenceDrawingParts.dashLengths)
}
