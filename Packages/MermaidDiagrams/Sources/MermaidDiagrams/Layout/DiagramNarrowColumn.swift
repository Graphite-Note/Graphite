/**
 * File: DiagramNarrowColumn.swift
 * -------------------------------
 * Layer: Core
 * Description: Diagrams that run across turned to run down, for a column too narrow for them, as Pele turns them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

/// How tightly a flowchart is laid out: Pele's gaps, or the tighter ones it takes when the diagram does not fit its
/// container's width.
public enum DiagramSpacing: Equatable, Sendable {
    case standard
    /// Gaps between nodes, edges and ranks about two thirds of the standard ones, and text wrapped sooner.
    case compact
}

extension FlowchartDirection {
    /// The direction a diagram takes in a narrow column: down for one that runs right, up for one that runs left, so
    /// that its ranks follow each other down the page instead of past the column's edge. The others stay.
    public var turnedToRunDown: FlowchartDirection {
        switch self {
        case .leftToRight: .topToBottom
        case .rightToLeft: .bottomToTop
        case .topToBottom, .bottomToTop: self
        }
    }
}

extension FlowchartDiagram {
    /// The flowchart with its direction and every group's turned to run down, or nil when nothing in it runs across.
    public var turnedToRunDown: FlowchartDiagram? {
        let runsAcrossSomewhere = direction.runsAcross || subgraphs.contains { subgraph in subgraph.direction?.runsAcross ?? false }
        guard runsAcrossSomewhere else { return nil }
        var turned = self
        turned.direction = direction.turnedToRunDown
        for index in turned.subgraphs.indices { turned.subgraphs[index].direction = subgraphs[index].direction?.turnedToRunDown }
        return turned
    }
}

extension StateDiagram {
    /// The state diagram with its direction and every composite's turned to run down, or nil when nothing runs across.
    public var turnedToRunDown: StateDiagram? {
        let runsAcrossSomewhere = direction.runsAcross || composites.contains { composite in composite.direction?.runsAcross ?? false }
        guard runsAcrossSomewhere else { return nil }
        var turned = self
        turned.direction = direction.turnedToRunDown
        for index in turned.composites.indices { turned.composites[index].direction = composites[index].direction?.turnedToRunDown }
        return turned
    }
}

extension ClassDiagram {
    /// The class diagram turned to run down, or nil when it does not run across.
    public var turnedToRunDown: ClassDiagram? {
        guard direction.runsAcross else { return nil }
        var turned = self
        turned.direction = direction.turnedToRunDown
        return turned
    }
}

extension EntityRelationshipDiagram {
    /// The entity relationship diagram turned to run down, or nil when it does not run across.
    public var turnedToRunDown: EntityRelationshipDiagram? {
        guard direction.runsAcross else { return nil }
        var turned = self
        turned.direction = direction.turnedToRunDown
        return turned
    }
}

extension GitGraphDiagram {
    /// The Git graph with its commits from the top down and a lane per branch from left to right, or nil when it already
    /// runs down or up.
    public var turnedToRunDown: GitGraphDiagram? {
        switch direction {
        case .leftToRight:
            var turned = self
            turned.direction = .topToBottom
            return turned
        case .topToBottom, .bottomToTop:
            return nil
        }
    }
}

extension TimelineDiagram {
    /// The timeline with its periods one below the other, or nil when it already runs down.
    public var turnedToRunDown: TimelineDiagram? {
        switch direction {
        case .leftToRight:
            var turned = self
            turned.direction = .topToBottom
            return turned
        case .topToBottom:
            return nil
        }
    }
}
