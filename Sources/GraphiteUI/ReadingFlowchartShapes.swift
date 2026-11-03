/**
 * File: ReadingFlowchartShapes.swift
 * ----------------------------------
 * Layer: UI
 * Description: A flowchart's shapes as SwiftUI paths and its text as placed lines.
 *
 * Authors: Félix Chevalier
 * Version: 0.3
 * Date: 01/11/2026
 */

import SwiftUI
import MermaidDiagrams

/// A flowchart's shapes as SwiftUI paths and its text as placed lines, made off the main actor from the package's
/// `FlowchartDrawingParts`, so that the view only paints them in the note's colors. Paths and text stay vector, on
/// screen and in a printed PDF, and draw without a `Canvas` and the graphics device a canvas starts.
struct ReadingFlowchartShapes: Sendable {
    /// The groups' boxes, painted first, and the titles edges cross, painted over the edges.
    let clusters: ReadingFlowchartClusterShapes
    let solidEdges: Path
    let thickEdges: Path
    let dottedEdges: Path
    let filledMarks: Path
    let strokedMarks: Path
    let edgeTextPatches: Path
    let nodeFills: Path
    let nodeOutlines: Path
    /// Edge text, drawn over the patches and under the nodes.
    let edgeTextLines: [ReadingDiagramTextLine]
    /// Node text and the title, drawn last.
    let nodeTextLines: [ReadingDiagramTextLine]
    /// The edges the diagram gave a stroke or colors of their own, painted over the others.
    let styledEdges: [ReadingFlowchartStyledEdge]
    /// The nodes the diagram gave colors of their own, painted over the others.
    let styledNodes: [ReadingFlowchartStyledNode]

    init(parts: FlowchartDrawingParts, font: DiagramFont) {
        clusters = ReadingFlowchartClusterShapes(parts: parts.clusters, font: font)
        solidEdges = Path(parts.solidEdges)
        thickEdges = Path(parts.thickEdges)
        dottedEdges = Path(parts.dottedEdges)
        filledMarks = Path(parts.filledMarks)
        strokedMarks = Path(parts.strokedMarks)
        edgeTextPatches = Path(parts.edgeTextPatches)
        nodeFills = Path(parts.nodeFills)
        nodeOutlines = Path(parts.nodeOutlines)
        edgeTextLines = parts.edgeTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
        nodeTextLines = parts.nodeTexts.flatMap { block in ReadingDiagramTextLine.lines(of: block, font: font, isBold: false) }
            + (parts.title.map { title in ReadingDiagramTextLine.lines(of: title, font: font, isBold: true) } ?? [])
        styledEdges = parts.styledEdges.map { edge in ReadingFlowchartStyledEdge(edge) }
        styledNodes = parts.styledNodes.map { node in ReadingFlowchartStyledNode(node, font: font) }
    }
}

/// An edge with a stroke or colors of its own (`linkStyle`) as paths: its line with its width and dashes, and its marks.
struct ReadingFlowchartStyledEdge: Sendable {
    let line: Path
    let filledMarks: Path
    let strokedMarks: Path
    /// The color of the line and marks, or nil for the usual line color.
    let color: DiagramColor?
    let lineWidth: CGFloat
    let dashLengths: [CGFloat]

    init(_ parts: FlowchartStyledEdgeParts) {
        line = Path(parts.line)
        filledMarks = Path(parts.filledMarks)
        strokedMarks = Path(parts.strokedMarks)
        color = parts.style.stroke
        lineWidth = parts.lineWidth
        dashLengths = parts.dashLengths
    }
}

/// A node with colors of its own (`classDef`, `class`, `:::`, `style`) as paths, with its text placed.
struct ReadingFlowchartStyledNode: Sendable {
    /// The inside to fill, or nil for a shape drawn as text alone.
    let fill: Path?
    let outline: Path
    let style: DiagramElementStyle
    let lineWidth: CGFloat
    let textLines: [ReadingDiagramTextLine]

    init(_ parts: FlowchartStyledNodeParts, font: DiagramFont) {
        fill = parts.fill.map { shape in Path(shape) }
        outline = Path(parts.outline)
        style = parts.style
        lineWidth = parts.lineWidth
        textLines = ReadingDiagramTextLine.lines(of: parts.text, font: font, isBold: false)
    }
}

extension Color {
    /// The color a diagram's statement wrote.
    init(_ color: DiagramColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

/// One line of a diagram's text: what it says, the center of its line box, and its font.
struct ReadingDiagramTextLine: Sendable {
    let text: String
    let center: CGPoint
    let font: DiagramFont
    let isBold: Bool

    static func lines(of block: DiagramTextBlock, font: DiagramFont, isBold: Bool) -> [ReadingDiagramTextLine] {
        let top = block.center.y - block.size.height / 2
        let lineFont = DiagramFont(postScriptName: font.postScriptName, size: block.fontSize)
        return block.lines.enumerated().map { index, line in
            ReadingDiagramTextLine(text: line, center: CGPoint(x: block.center.x, y: top + (CGFloat(index) + 0.5) * block.lineHeight),
                                   font: lineFont, isBold: isBold)
        }
    }

    /// The SwiftUI font the line was measured in: the system font, or the installed font by its PostScript name.
    var swiftUIFont: Font {
        let font = self.font.postScriptName.map { name in Font.custom(name, fixedSize: self.font.size) } ?? .system(size: self.font.size)
        return isBold ? font.bold() : font
    }
}
