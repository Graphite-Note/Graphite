/**
 * File: FlowchartStyledParts.swift
 * --------------------------------
 * Layer: Core
 * Description: The nodes and edges a flowchart gave colors of their own, painted apart.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics

/// A node the diagram gave colors of its own (`classDef`, `class`, `:::`, `style`): its shape, painted apart from the nodes
/// of the usual look, in the colors it sets and the usual ones for the rest.
public struct FlowchartStyledNodeParts {
    /// The shape's outline to fill, or nil for a shape drawn as text alone.
    public let fill: CGPath?
    /// The shape's outline and inner lines to stroke.
    public let outline: CGPath
    public let text: DiagramTextBlock
    public let style: DiagramElementStyle

    init(node: FlowchartLayoutNode, style: DiagramElementStyle) {
        let outlines = CGMutablePath()
        let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame)
        if let outline { outlines.addPath(outline) }
        if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame) { outlines.addPath(innerLines) }
        fill = outline
        self.outline = outlines
        text = node.text
        self.style = style
    }

    /// The width of the outline: the diagram's usual unless the style sets one.
    public var lineWidth: CGFloat { style.strokeWidth ?? FlowchartDrawingParts.lineWidth }
}

/// An edge the diagram gave a stroke or colors of its own (`linkStyle`): its line and marks, painted apart from the other edges.
public struct FlowchartStyledEdgeParts {
    public let line: CGPath
    /// Arrows and circles at the ends, filled in the line's color.
    public let filledMarks: CGPath
    /// Crosses at the ends, stroked in the line's color.
    public let strokedMarks: CGPath
    public let style: DiagramElementStyle
    /// The width of the line its kind has (`-->`, `==>`, `-.->`), when the style sets none.
    private let usualLineWidth: CGFloat
    private let usualDashLengths: [CGFloat]

    init(edge: FlowchartLayoutEdge, style: DiagramElementStyle) {
        line = DiagramEdgeDrawing.path(edge.path)
        let filled = CGMutablePath()
        let stroked = CGMutablePath()
        for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        filledMarks = filled
        strokedMarks = stroked
        self.style = style
        usualLineWidth = edge.stroke == .thick ? FlowchartDrawingParts.thickLineWidth : FlowchartDrawingParts.lineWidth
        usualDashLengths = edge.stroke == .dotted ? FlowchartDrawingParts.dottedDashLengths : []
    }

    public var lineWidth: CGFloat { style.strokeWidth ?? usualLineWidth }
    public var dashLengths: [CGFloat] { style.strokeDashLengths ?? usualDashLengths }
}
