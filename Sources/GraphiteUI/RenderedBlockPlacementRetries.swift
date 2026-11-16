/**
 * File: RenderedBlockPlacementRetries.swift
 * -----------------------------------------
 * Layer: UI
 * Description: When an editor places its rendered blocks' views again after a pass that could not place one or
 *              moved one: a few passes on the next turns of the run loop, then a few later tries, on the iPad
 *              and the Mac alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The placement passes an editor runs after one that left a block in view without its
/// view, or moved one. TextKit can finish laying out the viewport after a pass, after a
/// jump or a restyle, and a placed view can change the height it reserves, which moves the
/// text after the pass; the next passes follow. A block still missing after the quick
/// passes is tried again once the view has settled, rather than left blank until the next
/// scroll. An edit, or a new reason to place the blocks, starts a fresh set.
struct RenderedBlockPlacementRetries {
    /// What to do after a placement pass.
    enum NextPass: Equatable {
        /// Place the blocks again on the next turn of the run loop.
        case nextTurn
        /// Place them again after `delayedTryInterval`.
        case afterDelay
        /// Every block in view has its view where it belongs.
        case settled
        /// The passes are spent; the next layout of the viewport, or an edit, places them.
        case none
    }

    static let quickPassLimit = 6
    static let delayedTryLimit = 3
    static let delayedTryInterval: TimeInterval = 0.25

    private var quickPasses = 0
    private var delayedTries = 0

    mutating func nextPass(after placement: RenderedBlockPlacement) -> NextPass {
        if (placement.isMissingBlock || placement.didMoveView) && quickPasses < Self.quickPassLimit {
            quickPasses += 1
            return .nextTurn
        }
        if placement.isMissingBlock && delayedTries < Self.delayedTryLimit {
            delayedTries += 1
            quickPasses = 0
            return .afterDelay
        }
        guard !placement.isMissingBlock && !placement.didMoveView else { return .none }
        reset()
        return .settled
    }

    /// Follows a placement pass by placing the blocks again when `nextPass(after:)` says.
    /// Returns whether every block in view has its view where it belongs.
    @MainActor mutating func follow(_ placement: RenderedBlockPlacement, placeAgain: @escaping @MainActor () -> Void) -> Bool {
        switch nextPass(after: placement) {
        case .nextTurn:
            DispatchQueue.main.async { placeAgain() }
        case .afterDelay:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delayedTryInterval) { placeAgain() }
        case .settled:
            return true
        case .none:
            break
        }
        return false
    }

    /// Lays the viewport out now, for a pass that found a block's lines not laid out: a
    /// restyle gives them new fragments, and waiting for TextKit's own next layout showed the
    /// block's space empty, for a frame or two on the iPad and until the next scroll on the
    /// Mac (HUNT-364). Laying it out can scroll the view, as when a block takes its height
    /// back below a selection kept in sight, so it is laid out once more where it went.
    @MainActor static func layOutViewport(of textLayoutManager: NSTextLayoutManager, visibleOrigin: () -> CGPoint) {
        for _ in 0..<2 {
            let originBeforeLayout = visibleOrigin()
            textLayoutManager.textViewportLayoutController.layoutViewport()
            if visibleOrigin() == originBeforeLayout { return }
        }
    }

    mutating func reset() {
        quickPasses = 0
        delayedTries = 0
    }
}
