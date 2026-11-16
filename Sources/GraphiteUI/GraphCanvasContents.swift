/**
 * File: GraphCanvasContents.swift
 * -------------------------------
 * Layer: UI
 * Description: What the graph's canvas needs of a graph besides where its nodes are, worked out once per graph away
 *              from the main thread, with the layout that places its nodes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import GraphiteCore

/// A graph made ready for the canvas: its nodes by identifier, its links and neighbors by
/// index, each node's size and name length, its counts, and the layout that places it, from
/// the places nodes had before. Made off the main thread (`made(from:…)`): for a vault of
/// 100,000 notes it is a few hundred milliseconds of work that held the main thread.
struct GraphCanvasContents: Sendable {
    let graph: LinkGraph
    let indexByIdentifier: [String: Int]
    /// Each link as the indexes of its nodes.
    let edgeIndexes: [(source: Int, target: Int)]
    let neighborIndexes: [Set<Int>]
    /// Each node's radius in the layout: larger for well-linked notes and for a tag more notes carry.
    let radii: [Double]
    /// How many characters each node's name has, for the room the fit leaves for names.
    let nameCharacterCounts: [Int]
    let counts: LinkGraph.Counts
    let layout: GraphLayout
    /// Whether no node had a place before, so the layout is calmed before it is shown.
    let startsFromNothing: Bool

    /// A node's radius grows with the square root of its links, up to this many.
    private static let largestRadiusLinkRoot = 8.0
    private static let smallestRadius = 4.0
    private static let radiusPerLinkRoot = 1.3

    init(graph: LinkGraph, forces: GraphLayout.Forces, previousPositions: [String: SIMD2<Double>]) {
        self.graph = graph
        layout = GraphLayout(graph: graph, forces: forces, previousPositions: previousPositions)
        var indexByIdentifier: [String: Int] = [:]
        indexByIdentifier.reserveCapacity(graph.nodes.count)
        for (index, identifier) in layout.identifiers.enumerated() { indexByIdentifier[identifier] = index }
        self.indexByIdentifier = indexByIdentifier
        edgeIndexes = graph.edges.compactMap { edge in
            guard let source = indexByIdentifier[edge.source], let target = indexByIdentifier[edge.target] else { return nil }
            return (source, target)
        }
        var neighbors = Array(repeating: Set<Int>(), count: graph.nodes.count)
        var linkCounts = Array(repeating: 0, count: graph.nodes.count)
        for edge in edgeIndexes {
            neighbors[edge.source].insert(edge.target)
            neighbors[edge.target].insert(edge.source)
            linkCounts[edge.source] += 1
            linkCounts[edge.target] += 1
        }
        neighborIndexes = neighbors
        // Obsidian draws well-linked notes larger, and a tag larger the more notes carry it.
        radii = linkCounts.map { linkCount in
            Self.smallestRadius + min(Double(linkCount).squareRoot(), Self.largestRadiusLinkRoot) * Self.radiusPerLinkRoot
        }
        nameCharacterCounts = graph.nodes.map { node in node.title.count }
        counts = graph.counts
        startsFromNothing = !graph.nodes.contains { node in previousPositions[node.id] != nil }
    }

    /// The contents of `graph`, made away from the main thread. `shownPositions` are where the
    /// nodes of the graph shown until now are, by node, which win over `previousPositions`.
    static func made(from graph: LinkGraph, forces: GraphLayout.Forces, previousPositions: [String: SIMD2<Double>],
                     shownNodes: [GraphNode], shownPositions: [SIMD2<Double>]) async -> GraphCanvasContents {
        await Task.detached(priority: .userInitiated) {
            var knownPositions = previousPositions
            if shownNodes.count == shownPositions.count {
                for (node, position) in zip(shownNodes, shownPositions) { knownPositions[node.id] = position }
            }
            return GraphCanvasContents(graph: graph, forces: forces, previousPositions: knownPositions)
        }.value
    }
}
