/**
 * File: FlowchartEdge.swift
 * -------------------------
 * Layer: Core
 * Description: An edge of a flowchart and how its line is drawn.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

/// An edge of a flowchart, from one node to another as written (`A --> B` runs from A to B).
public struct FlowchartEdge: Equatable, Sendable {
    /// Index into `FlowchartDiagram.nodes` of the node the edge is written from.
    public let sourceIndex: Int
    /// Index into `FlowchartDiagram.nodes` of the node the edge is written to.
    public let targetIndex: Int
    public internal(set) var stroke: FlowchartEdgeStroke
    /// The mark at the source end: `<`, `o` or `x` before the line.
    public internal(set) var sourceArrowhead: FlowchartArrowhead
    /// The mark at the target end: `>`, `o` or `x` after the line.
    public internal(set) var targetArrowhead: FlowchartArrowhead
    /// How many ranks the edge asks to span at least: 1 for `-->`, one more for each extra `-`, `.` or `=`.
    public internal(set) var minimumRankSpan: Int
    /// The text on the edge (`-->|text|` or `-- text -->`), or nil.
    public internal(set) var label: DiagramLabel?
    /// What `linkStyle` sets for the edge's line and marks, or nil when it sets none.
    public internal(set) var style: DiagramElementStyle?

    init(sourceIndex: Int, targetIndex: Int, stroke: FlowchartEdgeStroke = .solid, sourceArrowhead: FlowchartArrowhead = .none,
         targetArrowhead: FlowchartArrowhead = .arrow, minimumRankSpan: Int = 1, label: DiagramLabel? = nil, style: DiagramElementStyle? = nil) {
        self.sourceIndex = sourceIndex
        self.targetIndex = targetIndex
        self.stroke = stroke
        self.sourceArrowhead = sourceArrowhead
        self.targetArrowhead = targetArrowhead
        self.minimumRankSpan = minimumRankSpan
        self.label = label
        self.style = style
    }
}

/// How an edge's line is drawn.
public enum FlowchartEdgeStroke: Equatable, Sendable, CaseIterable {
    /// `-->`, `---`.
    case solid
    /// `-.->`, `-.-`.
    case dotted
    /// `==>`, `===`.
    case thick
    /// `~~~`: the edge places its nodes but is not drawn.
    case invisible
}

/// The mark drawn where an edge meets a node.
public enum FlowchartArrowhead: Equatable, Sendable, CaseIterable {
    case none
    /// `>` or `<`.
    case arrow
    /// `o`.
    case circle
    /// `x`.
    case cross
}
