import Foundation

/// Places a graph's nodes as Obsidian's graph view does: links pull their ends together,
/// every node pushes the others away, and a weak pull keeps the graph centered. It is the
/// force simulation of d3 (which Obsidian uses), stepped until it settles. Repulsion is
/// approximated with a Barnes–Hut quadtree (`RepulsionTree`), which the graph view shares
/// between the processor's cores for a large graph (`repulsionPushesSharingWork()`), so a large
/// vault stays fast. Unlike Obsidian's, a note without links pushes
/// less (`unlinkedRepelRatio`), so such notes keep to a thin ring around the linked ones.
public struct GraphLayout: Sendable {
    /// Obsidian's graph "Forces" settings.
    public struct Forces: Equatable, Sendable {
        /// How long links try to be, in points.
        public var linkDistance = 60.0
        /// How strongly links pull, as a multiple of d3's default.
        public var linkStrength = 1.0
        /// How strongly nodes push each other away.
        public var repelStrength = 120.0
        /// How strongly nodes are pulled toward the middle.
        public var centerStrength = 0.06

        public init(linkDistance: Double = 60, linkStrength: Double = 1, repelStrength: Double = 120, centerStrength: Double = 0.06) {
            self.linkDistance = linkDistance
            self.linkStrength = linkStrength
            self.repelStrength = repelStrength
            self.centerStrength = centerStrength
        }
    }

    private struct Link: Sendable {
        let source: Int
        let target: Int
        /// How much of the correction moves the target rather than the source.
        let bias: Double
        let strength: Double
    }

    public let identifiers: [String]
    public private(set) var positions: [SIMD2<Double>]
    private var velocities: [SIMD2<Double>]
    private let links: [Link]
    /// How hard each node pushes the others, as a share of the repel force: less for a node
    /// without links (`unlinkedRepelRatio`); nil when every node has links.
    private let repelCharges: [Double]?
    private var pinnedPositions: [Int: SIMD2<Double>] = [:]
    public var forces: Forces
    /// How much the simulation still moves; it stops below `minimumAlpha`.
    public private(set) var alpha = 1.0
    private let indexByIdentifier: [String: Int]

    static let minimumAlpha = 0.001
    /// d3's decay: from 1 to the minimum in 300 steps.
    static let alphaDecay = 1 - pow(minimumAlpha, 1.0 / 300)
    /// The share of velocity lost at each step.
    static let velocityDecay = 0.4
    /// Barnes–Hut accuracy: cells seen smaller than this, relative to their distance,
    /// count as one body.
    static let approximationThreshold = 0.9
    /// A note without links pushes the others with this share of the repel force. The notes
    /// with links hold together and push the unlinked ones out to a ring around them; pushing
    /// each other as hard as linked notes do, the unlinked notes of a vault of thousands spread
    /// that ring over the outer quarter or third of the view (the owner's photo of 2026-10-21).
    /// At a quarter they stand closer, and the ring is a thin band (`GraphLayoutShapeTests`).
    static let unlinkedRepelRatio = 0.25
    /// Below this the simulation only adjusts: nodes move little from one step to the next.
    public static let calmAlpha = 0.1
    /// How much calming a graph laid out from nothing may cost before it is shown: steps
    /// times nodes. A vault of some thousands of notes is calm within it (about 100 steps);
    /// a far larger one is shown partly calm rather than kept from view.
    public static let calmingNodeStepBudget = 2_000_000

    /// - Parameter previousPositions: Where nodes were in an earlier layout, so a graph
    ///   that changes keeps its shape. New nodes start beside a placed neighbor.
    public init(graph: LinkGraph, forces: Forces = Forces(), previousPositions: [String: SIMD2<Double>] = [:]) {
        self.forces = forces
        identifiers = graph.nodes.map(\.id)
        var indexByIdentifier: [String: Int] = [:]
        for (index, identifier) in identifiers.enumerated() { indexByIdentifier[identifier] = index }
        self.indexByIdentifier = indexByIdentifier
        let linkCounts = graph.linkCounts
        links = graph.edges.compactMap { edge in
            guard let source = indexByIdentifier[edge.source], let target = indexByIdentifier[edge.target] else { return nil }
            let sourceCount = Double(linkCounts[edge.source] ?? 1), targetCount = Double(linkCounts[edge.target] ?? 1)
            return Link(source: source, target: target, bias: sourceCount / (sourceCount + targetCount), strength: 1 / min(sourceCount, targetCount))
        }
        var isUnlinked = Array(repeating: true, count: identifiers.count)
        for link in links {
            isUnlinked[link.source] = false
            isUnlinked[link.target] = false
        }
        repelCharges = isUnlinked.contains(true) ? isUnlinked.map { unlinked in unlinked ? Self.unlinkedRepelRatio : 1 } : nil
        var neighbors: [Int: [Int]] = [:]
        for link in links {
            neighbors[link.source, default: []].append(link.target)
            neighbors[link.target, default: []].append(link.source)
        }
        var positions: [SIMD2<Double>?] = identifiers.map { identifier in previousPositions[identifier] }
        let hasPreviousLayout = positions.contains { position in position != nil }
        for index in positions.indices where positions[index] == nil {
            if hasPreviousLayout, let placedNeighbor = neighbors[index]?.lazy.compactMap({ neighbor in positions[neighbor] }).first {
                positions[index] = placedNeighbor + Self.offset(for: index) * forces.linkDistance / 3
            } else {
                // d3's phyllotaxis: an even spiral, the same for the same graph every time.
                let radius = 10 * (0.5 + Double(index)).squareRoot()
                let angle = Double(index) * Double.pi * (3 - 5.0.squareRoot())
                positions[index] = SIMD2(radius * cos(angle), radius * sin(angle))
            }
        }
        self.positions = positions.map { position in position ?? .zero }
        velocities = Array(repeating: .zero, count: identifiers.count)
        // A graph laid out before only needs to adjust.
        if hasPreviousLayout { alpha = 0.3 }
    }

    public var isSettled: Bool { alpha < Self.minimumAlpha }

    public func position(of identifier: String) -> SIMD2<Double>? {
        indexByIdentifier[identifier].map { index in positions[index] }
    }

    public var positionsByIdentifier: [String: SIMD2<Double>] {
        Dictionary(uniqueKeysWithValues: zip(identifiers, positions))
    }

    /// Holds a node where it is dragged; the others move around it.
    public mutating func pin(_ identifier: String, at position: SIMD2<Double>) {
        guard let index = indexByIdentifier[identifier] else { return }
        pinnedPositions[index] = position
        positions[index] = position
        velocities[index] = .zero
    }

    public mutating func unpin(_ identifier: String) {
        guard let index = indexByIdentifier[identifier] else { return }
        pinnedPositions[index] = nil
    }

    /// Wakes the simulation, as when a node is dragged or a setting changes.
    public mutating func reheat(to targetAlpha: Double = 0.3) {
        alpha = max(alpha, targetAlpha)
    }

    /// Advances the simulation by one step, on the caller's thread.
    public mutating func step() {
        step(repulsionPushes: repulsionTree().forces(positions: positions, strength: -1, threshold: Self.approximationThreshold))
    }

    /// The push of every node on each, at a repel force of 1, worked out on several cores for a
    /// large graph (`RepulsionTree.sharedPassNodeCount`), for `step(repulsionPushes:)`.
    public func repulsionPushesSharingWork() async -> [SIMD2<Double>] {
        await repulsionTree().forcesSharingWork(positions: positions, strength: -1, threshold: Self.approximationThreshold)
    }

    /// Advances the simulation by one step with the pushes `repulsionPushesSharingWork()` worked
    /// out for the positions the nodes are at; the same step as `step()`.
    public mutating func step(repulsionPushes: [SIMD2<Double>]) {
        guard !positions.isEmpty else { alpha = 0; return }
        alpha += (0 - alpha) * Self.alphaDecay
        applyLinkForce()
        // The pushes grow with the repel force and the cooling, which they were worked out without.
        if repulsionPushes.count == positions.count, forces.repelStrength > 0 {
            let strength = forces.repelStrength * alpha
            for index in positions.indices { velocities[index] += repulsionPushes[index] * strength }
        }
        for index in positions.indices {
            // Centering, as d3's x and y forces toward the origin.
            velocities[index] -= positions[index] * forces.centerStrength * alpha
        }
        for index in positions.indices {
            velocities[index] *= 1 - Self.velocityDecay
            positions[index] += velocities[index]
        }
        for (index, pinned) in pinnedPositions {
            positions[index] = pinned
            velocities[index] = .zero
        }
    }

    /// Whether the simulation only adjusts now (`calmAlpha`).
    public var isCalm: Bool { alpha <= Self.calmAlpha }

    /// Steps until the simulation is calm, within `calmingNodeStepBudget`, as before the
    /// first drawing of a graph laid out from nothing, so that it does not appear mid-flight.
    public mutating func calm() {
        let maximumSteps = Self.calmingStepLimit(nodeCount: positions.count)
        var steps = 0
        while !isCalm, steps < maximumSteps {
            step()
            steps += 1
        }
    }

    /// How many steps calming a graph of this many nodes may take.
    public static func calmingStepLimit(nodeCount: Int) -> Int {
        calmingNodeStepBudget / max(nodeCount, 1)
    }

    /// Steps until settled, or at most `maximumSteps` times.
    public mutating func settle(maximumSteps: Int = 1_000) {
        var steps = 0
        while !isSettled, steps < maximumSteps {
            step()
            steps += 1
        }
    }

    /// The smallest rectangle around every node, as origin and size; nil without nodes.
    public var bounds: (origin: SIMD2<Double>, size: SIMD2<Double>)? {
        guard var lower = positions.first else { return nil }
        var upper = lower
        for position in positions {
            lower = pointwiseMin(lower, position)
            upper = pointwiseMax(upper, position)
        }
        return (lower, upper - lower)
    }

    // MARK: Forces

    private mutating func applyLinkForce() {
        let strengthScale = forces.linkStrength
        for link in links {
            var delta = positions[link.target] + velocities[link.target] - positions[link.source] - velocities[link.source]
            if delta == .zero { delta = Self.offset(for: link.target) * 1e-6 }
            let length = (delta * delta).sum().squareRoot()
            let correction = (length - forces.linkDistance) / length * alpha * link.strength * strengthScale
            delta *= correction
            velocities[link.target] -= delta * link.bias
            velocities[link.source] += delta * (1 - link.bias)
        }
    }

    private func repulsionTree() -> RepulsionTree {
        RepulsionTree(positions: positions, charges: repelCharges)
    }

    /// A small offset that differs from node to node but not from run to run, to separate
    /// nodes in the same place.
    static func offset(for index: Int) -> SIMD2<Double> {
        let angle = Double((index &* 2_654_435_761) % 360) * Double.pi / 180
        return SIMD2(cos(angle), sin(angle))
    }
}
