/**
 * File: StateDiagramClusterGraph.swift
 * ------------------------------------
 * Layer: Core
 * Description: A state diagram with composite states as nested boxes to lay out, as a flowchart's subgraphs are.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import CoreGraphics

/// A state diagram with composite states as a graph of nested boxes to lay out (`LayeredClusterLayout`), as a flowchart's
/// subgraphs are: each composite state a box with a flowchart group's room inside it and its name in a band along its
/// top, running in its own direction or in that of the box around it; each concurrent region of a body that has several
/// a box of its own inside it, without a title; every other state in the box of the composite or region it was last
/// named in; and each transition between two different states or boxes, a transition to or from a composite state
/// meeting its box.
struct StateDiagramClusterGraph {
    /// The room inside a region's box around its states: less than a composite's, as the region's box is not drawn.
    static let regionPadding: CGFloat = 12

    let graph: LayeredClusterGraph
    /// For each state, its node in `graph`, or nil for a composite state, which is its box.
    let layoutNodeIndices: [Int?]
    /// For each state, the composite it is (its index in `StateDiagram.composites`, which is its box's in
    /// `graph.clusters`), or nil.
    let compositeOfState: [Int?]
    /// The transitions laid out, in the order of `graph.edges`; a transition from a state to itself loops beside it.
    let layoutTransitionIndices: [Int]
    /// Each composite's name, measured, or nil for an empty one.
    let titles: [DiagramTextBlock?]
    /// How many composite boxes each composite's box is inside.
    let depths: [Int]
    /// For each composite whose states sit in several regions, its regions' boxes in `graph.clusters`, in region order.
    let regionClusterIndices: [[Int]]

    /// Fails with `StateDiagramLayoutError.compositeStatesNotLaidOut` for what is not laid out: a transition from a
    /// composite state to itself, a note beside a composite state, a composite inside itself through its states.
    init<Measurer: DiagramTextMeasuring>(diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings,
                                         flowIsVertical: Bool, titleText: Measurer) throws(StateDiagramLayoutError) {
        var compositeOfState = [Int?](repeating: nil, count: diagram.states.count)
        for (compositeIndex, composite) in diagram.composites.enumerated() { compositeOfState[composite.stateIndex] = compositeIndex }
        guard !diagram.notes.contains(where: { note in compositeOfState[note.stateIndex] != nil }) else { throw .compositeStatesNotLaidOut }
        self.compositeOfState = compositeOfState
        let measuredTitles = diagram.composites.map { composite in
            let title = DiagramTextBlock(label: diagram.states[composite.stateIndex].name, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lines.isEmpty ? nil : title
        }
        titles = measuredTitles
        var clusters = diagram.composites.indices.map { compositeIndex in
            Self.compositeCluster(direction: diagram.composites[compositeIndex].direction, title: measuredTitles[compositeIndex])
        }
        let regions = Self.regionClusters(of: diagram, startingAt: clusters.count)
        regionClusterIndices = regions.indicesByComposite
        for (compositeIndex, regionIndices) in regions.indicesByComposite.enumerated() {
            for _ in regionIndices {
                clusters.append(LayeredCluster(parent: compositeIndex, direction: nil,
                                               padding: LayeredClusterPadding(side: Self.regionPadding, top: Self.regionPadding, bottom: Self.regionPadding),
                                               minimumWidth: 0))
            }
        }
        for (compositeIndex, composite) in diagram.composites.enumerated() {
            clusters[compositeIndex].parent = regions.container(of: composite.stateIndex, in: diagram)
        }
        depths = try Self.depths(of: diagram)
        let nodes = Self.nodes(of: diagram, compositeOfState: compositeOfState, surroundings: surroundings, flowIsVertical: flowIsVertical, regions: regions)
        layoutNodeIndices = nodes.layoutNodeIndices
        let edges = try Self.edges(of: diagram, measured: measured, layoutNodeIndices: nodes.layoutNodeIndices, compositeOfState: compositeOfState)
        layoutTransitionIndices = edges.transitionIndices
        graph = LayeredClusterGraph(nodeSizes: nodes.sizes, nodeClusters: nodes.clusters, clusters: clusters, edges: edges.layout,
                                    direction: diagram.direction.layeredDirection)
    }

    /// The states that are not composites as nodes, in the layout's order: each one's place with its notes and loops on
    /// the page, and the box it sits directly in.
    private static func nodes(of diagram: StateDiagram, compositeOfState: [Int?], surroundings: StateDiagramSurroundings, flowIsVertical: Bool,
                              regions: RegionClusters) -> (layoutNodeIndices: [Int?], sizes: [CGSize], clusters: [Int?]) {
        var layoutNodeIndices = [Int?](repeating: nil, count: diagram.states.count)
        var sizes: [CGSize] = []
        var clusters: [Int?] = []
        for state in StateDiagramLayoutEngine.flowOrder(of: diagram) where compositeOfState[state] == nil {
            layoutNodeIndices[state] = sizes.count
            let place = surroundings.placeSizes[state]
            sizes.append(flowIsVertical ? CGSize(width: place.across, height: place.along) : CGSize(width: place.along, height: place.across))
            clusters.append(regions.container(of: state, in: diagram))
        }
        return (layoutNodeIndices, sizes, clusters)
    }

    /// A composite's box: a flowchart group's padding, its name's band along the top, at least as wide as its name.
    private static func compositeCluster(direction: FlowchartDirection?, title: DiagramTextBlock?) -> LayeredCluster {
        let padding = FlowchartClusterGraph.clusterPadding
        let titleSize = title?.size ?? .zero
        let top = title == nil ? padding : titleSize.height + 2 * FlowchartClusterGraph.titleMargin
        return LayeredCluster(parent: nil, direction: direction?.layeredDirection, padding: LayeredClusterPadding(side: padding, top: top, bottom: padding),
                              minimumWidth: titleSize.width + 2 * padding - FlowchartClusterGraph.titleWidthAllowance)
    }

    /// The regions' boxes: for each composite whose states (composite ones included) sit in more than one region, one box per
    /// region that holds a state, numbered from `firstClusterIndex` in region order. A body with one region has none.
    private static func regionClusters(of diagram: StateDiagram, startingAt firstClusterIndex: Int) -> RegionClusters {
        var usedRegions = [Set<Int>](repeating: [], count: diagram.composites.count)
        for state in diagram.states {
            guard let compositeIndex = state.compositeIndex, compositeIndex < diagram.composites.count else { continue }
            usedRegions[compositeIndex].insert(state.regionIndex)
        }
        var nextClusterIndex = firstClusterIndex
        var clusterByRegion: [RegionKey: Int] = [:]
        let indicesByComposite = usedRegions.enumerated().map { compositeIndex, regions -> [Int] in
            guard regions.count > 1 else { return [] }
            return regions.sorted().map { region in
                defer { nextClusterIndex += 1 }
                clusterByRegion[RegionKey(compositeIndex: compositeIndex, regionIndex: region)] = nextClusterIndex
                return nextClusterIndex
            }
        }
        return RegionClusters(indicesByComposite: indicesByComposite, clusterByRegion: clusterByRegion)
    }

    private struct RegionKey: Hashable {
        let compositeIndex: Int
        let regionIndex: Int
    }

    private struct RegionClusters {
        let indicesByComposite: [[Int]]
        let clusterByRegion: [RegionKey: Int]

        /// The box a state sits directly in: its region's, when its composite's body has several, else its composite's;
        /// nil at the top level.
        func container(of state: Int, in diagram: StateDiagram) -> Int? {
            guard let compositeIndex = diagram.states[state].compositeIndex else { return nil }
            return clusterByRegion[RegionKey(compositeIndex: compositeIndex, regionIndex: diagram.states[state].regionIndex)] ?? compositeIndex
        }
    }

    /// How many composites each composite is inside, through the composites its state was last named in. A composite
    /// found inside itself fails: the chain of its parents never reaches the top level.
    private static func depths(of diagram: StateDiagram) throws(StateDiagramLayoutError) -> [Int] {
        try diagram.composites.map { composite throws(StateDiagramLayoutError) in
            var depth = 0
            var parent = diagram.states[composite.stateIndex].compositeIndex
            while let parentIndex = parent {
                depth += 1
                guard depth <= diagram.composites.count else { throw .compositeStatesNotLaidOut }
                parent = diagram.states[diagram.composites[parentIndex].stateIndex].compositeIndex
            }
            return depth
        }
    }

    /// The transitions between two different ends, with their texts' room; a transition from a composite state to
    /// itself fails, and one from another state to itself loops beside it.
    private static func edges(of diagram: StateDiagram, measured: StateDiagramMeasurement, layoutNodeIndices: [Int?],
                              compositeOfState: [Int?]) throws(StateDiagramLayoutError) -> (layout: [LayeredClusterEdge], transitionIndices: [Int]) {
        func end(of state: Int) -> LayeredClusterEnd {
            if let compositeIndex = compositeOfState[state] { return .cluster(compositeIndex) }
            return .node(layoutNodeIndices[state] ?? 0)
        }
        let room = StateDiagramLayoutEngine.transitionTextRoom
        var layout: [LayeredClusterEdge] = []
        var transitionIndices: [Int] = []
        for (transitionIndex, transition) in diagram.transitions.enumerated() {
            let source = end(of: transition.sourceIndex)
            let target = end(of: transition.targetIndex)
            if source == target {
                if case .cluster = source { throw .compositeStatesNotLaidOut }
                continue
            }
            let labelSize = measured.transitionTexts[transitionIndex].map { text in
                CGSize(width: text.size.width + room.width, height: text.size.height + room.height)
            }
            layout.append(LayeredClusterEdge(source: source, target: target, minimumRankSpan: 1, labelSize: labelSize))
            transitionIndices.append(transitionIndex)
        }
        return (layout, transitionIndices)
    }
}
