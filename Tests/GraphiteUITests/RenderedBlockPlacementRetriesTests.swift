/**
 * File: RenderedBlockPlacementRetriesTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The placement passes the iPad and the Mac run after a pass that left a rendered block without its
 *              view or moved one: quick passes, then later tries, then none until a fresh set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
@testable import GraphiteUI

final class RenderedBlockPlacementRetriesTests: XCTestCase {
    private func placement(isMissingBlock: Bool = false, didMoveView: Bool = false) -> RenderedBlockPlacement {
        var placement = RenderedBlockPlacement()
        placement.isMissingBlock = isMissingBlock
        placement.didMoveView = didMoveView
        return placement
    }

    func testAMissingBlockGetsQuickPassesThenLaterTriesThenNone() {
        var retries = RenderedBlockPlacementRetries()
        var passes: [RenderedBlockPlacementRetries.NextPass] = []
        for _ in 0..<(RenderedBlockPlacementRetries.delayedTryLimit * (RenderedBlockPlacementRetries.quickPassLimit + 1) + 1) {
            passes.append(retries.nextPass(after: placement(isMissingBlock: true)))
        }
        let quickPasses = [RenderedBlockPlacementRetries.NextPass](repeating: .nextTurn, count: RenderedBlockPlacementRetries.quickPassLimit)
        let oneRound = quickPasses + [.afterDelay]
        XCTAssertEqual(passes, oneRound + oneRound + oneRound + [.nextTurn])
        for _ in 0..<RenderedBlockPlacementRetries.quickPassLimit - 1 { _ = retries.nextPass(after: placement(isMissingBlock: true)) }
        XCTAssertEqual(retries.nextPass(after: placement(isMissingBlock: true)), .none, "Spent: the next layout or an edit places the block")
    }

    func testAMovedViewGetsQuickPassesOnly() {
        var retries = RenderedBlockPlacementRetries()
        for _ in 0..<RenderedBlockPlacementRetries.quickPassLimit {
            XCTAssertEqual(retries.nextPass(after: placement(didMoveView: true)), .nextTurn)
        }
        XCTAssertEqual(retries.nextPass(after: placement(didMoveView: true)), .none)
    }

    func testASettledPassAndAResetStartAFreshSet() {
        var retries = RenderedBlockPlacementRetries()
        for _ in 0..<RenderedBlockPlacementRetries.quickPassLimit { _ = retries.nextPass(after: placement(isMissingBlock: true)) }
        XCTAssertEqual(retries.nextPass(after: placement()), .settled)
        XCTAssertEqual(retries.nextPass(after: placement(isMissingBlock: true)), .nextTurn)
        for _ in 0..<RenderedBlockPlacementRetries.quickPassLimit { _ = retries.nextPass(after: placement(didMoveView: true)) }
        retries.reset()
        XCTAssertEqual(retries.nextPass(after: placement(didMoveView: true)), .nextTurn)
    }
}
