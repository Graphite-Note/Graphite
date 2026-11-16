/**
 * File: GraphRepulsionTree.swift
 * ------------------------------
 * Layer: Core
 * Description: The quadtree with which every node of the graph's layout pushes the others away (Barnes–Hut), and the
 *              pass that works out each node's push, over several processor cores for a large graph.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation

/// A quadtree over the nodes, each cell knowing how many nodes it holds and their center,
/// so a far group of nodes can push as one (Barnes–Hut).
///
/// Its cells are plain values, and the nodes that share a place once cells are too small to
/// split are chained by node rather than kept in a list per cell: reading a cell copies no
/// reference, which made each visit of the pass retain and release one.
struct RepulsionTree: Sendable {
    private struct Cell: Sendable {
        var origin: SIMD2<Double>
        var size: Double
        /// The sum of the nodes' positions while the tree is built; their center once it is.
        var center = SIMD2<Double>.zero
        /// How hard the cell's nodes push together: the sum of their charges.
        var charge = 0.0
        /// The first of four children, or -1 for a leaf.
        var firstChild = -1
        /// The first node in a leaf, or -1.
        var body = -1
    }

    private var cells: [Cell] = []
    /// How hard each node pushes the others, as a share of the repel force; nil when every
    /// node pushes as hard.
    private let charges: [Double]?
    /// For each node, the next node in the same leaf, kept together once cells are too small
    /// to split; -1 ends the chain.
    private var nextBodyInLeaf: [Int]
    private static let maximumDepth = 40
    /// How deep a pass over the tree goes at most: four children a level.
    private static let pendingCellsCapacity = maximumDepth * 4

    init(positions: [SIMD2<Double>], charges: [Double]? = nil) {
        self.charges = charges.flatMap { charges in charges.count == positions.count ? charges : nil }
        nextBodyInLeaf = Array(repeating: -1, count: positions.count)
        guard var lower = positions.first else { return }
        var upper = lower
        for position in positions {
            lower = pointwiseMin(lower, position)
            upper = pointwiseMax(upper, position)
        }
        let size = max((upper - lower).max(), 1) * 1.000_001
        cells.reserveCapacity(positions.count * 2)
        cells.append(Cell(origin: lower, size: size))
        for index in positions.indices { insert(index, at: positions[index], positions: positions) }
        for cellIndex in cells.indices where cells[cellIndex].charge > 0 {
            cells[cellIndex].center /= cells[cellIndex].charge
        }
    }

    private static func quadrant(of position: SIMD2<Double>, origin: SIMD2<Double>, size: Double) -> Int {
        let half = size / 2
        return (position.x >= origin.x + half ? 1 : 0) + (position.y >= origin.y + half ? 2 : 0)
    }

    private func charge(of index: Int) -> Double { charges?[index] ?? 1 }

    private mutating func insert(_ index: Int, at position: SIMD2<Double>, positions: [SIMD2<Double>]) {
        let nodeCharge = charge(of: index)
        var cellIndex = 0
        var depth = 0
        while true {
            cells[cellIndex].charge += nodeCharge
            cells[cellIndex].center += position * nodeCharge
            if cells[cellIndex].firstChild >= 0 {
                cellIndex = cells[cellIndex].firstChild + Self.quadrant(of: position, origin: cells[cellIndex].origin, size: cells[cellIndex].size)
                depth += 1
                continue
            }
            let existing = cells[cellIndex].body
            if existing < 0 {
                cells[cellIndex].body = index
                return
            }
            if depth >= Self.maximumDepth {
                nextBodyInLeaf[index] = nextBodyInLeaf[existing]
                nextBodyInLeaf[existing] = index
                return
            }
            // Split the leaf and move its node down.
            let origin = cells[cellIndex].origin, half = cells[cellIndex].size / 2
            let firstChild = cells.count
            for quadrantIndex in 0..<4 {
                cells.append(Cell(origin: origin + SIMD2(quadrantIndex & 1 == 1 ? half : 0, quadrantIndex & 2 == 2 ? half : 0), size: half))
            }
            cells[cellIndex].body = -1
            cells[cellIndex].firstChild = firstChild
            let existingCell = firstChild + Self.quadrant(of: positions[existing], origin: origin, size: half * 2)
            cells[existingCell].body = existing
            cells[existingCell].charge = charge(of: existing)
            cells[existingCell].center = positions[existing] * charge(of: existing)
            cellIndex = firstChild + Self.quadrant(of: position, origin: origin, size: half * 2)
            depth += 1
        }
    }

    /// The push on node `index` from all others: `strength` over the squared distance,
    /// negative to repel. With `threshold` 0 every node counts on its own.
    func force(on index: Int, positions: [SIMD2<Double>], strength: Double, threshold: Double) -> SIMD2<Double> {
        var pendingCells: [Int] = []
        pendingCells.reserveCapacity(Self.pendingCellsCapacity)
        return positions.withUnsafeBufferPointer { positionBuffer in
            force(on: index, positions: positionBuffer, strength: strength, threshold: threshold, pendingCells: &pendingCells)
        }
    }

    /// `force(on:positions:strength:threshold:)` with the list of cells still to visit kept by
    /// the caller, so a pass over every node makes it once.
    private func force(on index: Int, positions: UnsafeBufferPointer<SIMD2<Double>>, strength: Double, threshold: Double,
                       pendingCells: inout [Int]) -> SIMD2<Double> {
        guard !cells.isEmpty else { return .zero }
        let position = positions[index]
        let thresholdSquared = threshold * threshold
        var total = SIMD2<Double>.zero
        pendingCells.removeAll(keepingCapacity: true)
        pendingCells.append(0)
        cells.withUnsafeBufferPointer { cellBuffer in
            while let cellIndex = pendingCells.popLast() {
                let cell = cellBuffer[cellIndex]
                guard cell.charge > 0 else { continue }
                if cell.firstChild >= 0 {
                    let delta = cell.center - position
                    let distanceSquared = (delta * delta).sum()
                    if distanceSquared > 0, cell.size * cell.size < thresholdSquared * distanceSquared {
                        total += delta * (strength * cell.charge / max(distanceSquared, 1))
                    } else {
                        for child in cell.firstChild..<(cell.firstChild + 4) { pendingCells.append(child) }
                    }
                    continue
                }
                var body = cell.body
                while body >= 0 {
                    if body != index {
                        var delta = positions[body] - position
                        if delta == .zero { delta = GraphLayout.offset(for: body &+ index) * 1e-3 }
                        total += delta * (strength * charge(of: body) / max((delta * delta).sum(), 1))
                    }
                    body = nextBodyInLeaf[body]
                }
            }
        }
        return total
    }

    /// From this many nodes the pass over them is shared between the processor's cores: below
    /// it, a step is shorter than handing the work out.
    static let sharedPassNodeCount = 2_000
    /// The pass is cut into this many tasks for each core, so faster cores take more of them.
    static let sharedChunksPerCore = 2

    /// The push on every node, in node order, on the caller's thread.
    func forces(positions: [SIMD2<Double>], strength: Double, threshold: Double) -> [SIMD2<Double>] {
        forces(on: positions.indices, positions: positions, strength: strength, threshold: threshold)
    }

    /// The push on every node, in node order, shared between the processor's cores for a large
    /// graph: the same numbers as `forces(positions:strength:threshold:)`.
    func forcesSharingWork(positions: [SIMD2<Double>], strength: Double, threshold: Double) async -> [SIMD2<Double>] {
        guard positions.count >= Self.sharedPassNodeCount else { return forces(positions: positions, strength: strength, threshold: threshold) }
        let chunkCount = max(ProcessInfo.processInfo.activeProcessorCount * Self.sharedChunksPerCore, 1)
        let nodesPerChunk = (positions.count + chunkCount - 1) / chunkCount
        return await withTaskGroup(of: (chunk: Int, forces: [SIMD2<Double>]).self) { group in
            for chunk in 0..<chunkCount {
                let start = min(chunk * nodesPerChunk, positions.count)
                let indexes = start..<min(start + nodesPerChunk, positions.count)
                group.addTask { (chunk, forces(on: indexes, positions: positions, strength: strength, threshold: threshold)) }
            }
            var forcesByChunk = [[SIMD2<Double>]](repeating: [], count: chunkCount)
            for await chunkForces in group { forcesByChunk[chunkForces.chunk] = chunkForces.forces }
            return forcesByChunk.flatMap { chunkForces in chunkForces }
        }
    }

    private func forces(on indexes: Range<Int>, positions: [SIMD2<Double>], strength: Double, threshold: Double) -> [SIMD2<Double>] {
        var pendingCells: [Int] = []
        pendingCells.reserveCapacity(Self.pendingCellsCapacity)
        var forces: [SIMD2<Double>] = []
        forces.reserveCapacity(indexes.count)
        positions.withUnsafeBufferPointer { positionBuffer in
            for index in indexes {
                forces.append(force(on: index, positions: positionBuffer, strength: strength, threshold: threshold, pendingCells: &pendingCells))
            }
        }
        return forces
    }
}
