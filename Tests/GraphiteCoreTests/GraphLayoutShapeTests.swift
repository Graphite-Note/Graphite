/**
 * File: GraphLayoutShapeTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The shape of a settled layout on a made-up vault of the owner's size: the notes without links keep to a
 *              thin ring, the pass of repulsion gives the same pushes shared between cores as on one, and a step
 *              with pushes worked out apart is the same step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// The layout's shape on a vault of the owner's size (`GeneratedCourseVault`, 4,700 notes),
/// tags hidden, where the notes without links are most: 2,070 of them.
final class GraphLayoutShapeTests: XCTestCase {
    func testTheNotesWithoutLinksKeepToAThinRingAroundTheLinkedOnes() async throws {
        let graph = GeneratedCourseVault(noteCount: 4_700).linkGraph.filtered(by: GraphFilterOptions(showsTags: false))
        var layout = GraphLayout(graph: graph)
        // Settled as the graph view settles it, its repulsion shared between the cores.
        while !layout.isSettled { layout.step(repulsionPushes: await layout.repulsionPushesSharingWork()) }

        var linkedIndexes = Set<Int>()
        let indexByIdentifier = Dictionary(uniqueKeysWithValues: layout.identifiers.enumerated().map { index, identifier in (identifier, index) })
        for edge in graph.edges {
            linkedIndexes.insert(try XCTUnwrap(indexByIdentifier[edge.source]))
            linkedIndexes.insert(try XCTUnwrap(indexByIdentifier[edge.target]))
        }
        let center = layout.positions.reduce(SIMD2<Double>.zero, +) / Double(layout.positions.count)
        func distanceFromCenter(_ index: Int) -> Double {
            let delta = layout.positions[index] - center
            return (delta * delta).sum().squareRoot()
        }
        let graphReach = Self.percentile(99, of: layout.positions.indices.map(distanceFromCenter))
        let linkedReach = Self.percentile(99, of: linkedIndexes.map(distanceFromCenter))
        // Pushing as hard as linked notes, the unlinked ones took the outer tenth of the radius
        // (0.90), a fifth of the view's area; at a quarter of the push, the outer 4 percent.
        XCTAssertGreaterThan(linkedReach / graphReach, 0.94, "The ring of notes without links is a thin band.")
    }

    func testRepulsionSharedBetweenCoresPushesAsOnOne() async {
        var generator = SeededRandomNumberGenerator(seed: 11)
        let positions = (0..<(RepulsionTree.sharedPassNodeCount + 300)).map { _ in
            SIMD2(Double.random(in: -2_000...2_000, using: &generator), Double.random(in: -2_000...2_000, using: &generator))
        }
        let charges = positions.indices.map { index in index % 3 == 0 ? GraphLayout.unlinkedRepelRatio : 1 }
        let tree = RepulsionTree(positions: positions, charges: charges)
        let shared = await tree.forcesSharingWork(positions: positions, strength: -120, threshold: 0.9)
        XCTAssertEqual(shared.count, positions.count)
        for index in [0, 1, 511, 512, 1_999, positions.count - 1] {
            XCTAssertEqual(shared[index], tree.force(on: index, positions: positions, strength: -120, threshold: 0.9), "Node \(index) in node order.")
        }
    }

    func testAStepWithItsPushesWorkedOutApartIsTheSameStep() async {
        let graph = GeneratedCourseVault(noteCount: 2_500).linkGraph
        var onOneCore = GraphLayout(graph: graph)
        var sharedBetweenCores = onOneCore
        for _ in 0..<3 {
            onOneCore.step()
            sharedBetweenCores.step(repulsionPushes: await sharedBetweenCores.repulsionPushesSharingWork())
        }
        XCTAssertEqual(onOneCore.positions, sharedBetweenCores.positions)
        XCTAssertEqual(onOneCore.alpha, sharedBetweenCores.alpha)
    }

    func testANodeThatPushesLessPushesInProportion() {
        let positions: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(100, 0), SIMD2(0, 50)]
        let full = RepulsionTree(positions: positions).force(on: 0, positions: positions, strength: -120, threshold: 0)
        let lighter = RepulsionTree(positions: positions, charges: [1, 0.25, 1]).force(on: 0, positions: positions, strength: -120, threshold: 0)
        // The node at (100, 0) pushes along x only: a quarter as hard; the one at (0, 50) as hard as before.
        XCTAssertEqual(lighter.x, full.x / 4, accuracy: 1e-12)
        XCTAssertEqual(lighter.y, full.y, accuracy: 1e-12)
    }

    private static func percentile(_ percent: Int, of values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, (sorted.count - 1) * percent / 100)]
    }
}
