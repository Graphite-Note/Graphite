/**
 * File: WebFramePageScrollEdges.swift
 * -----------------------------------
 * Layer: UI
 * Description: Where a frame's page is scrolled, and whether a wheel step goes to the note around it instead.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

/// Where a frame's page is scrolled, as far as the wheel cares: at its top, at its bottom, or both when it does not scroll.
struct WebFramePageScrollEdges: Equatable {
    var isAtTop = true
    var isAtBottom = false

    /// How far from an end still counts as at it, in points: a page's last scroll stops on a fraction of a point.
    static let tolerance: Double = 1

    init(isAtTop: Bool = true, isAtBottom: Bool = false) {
        self.isAtTop = isAtTop
        self.isAtBottom = isAtBottom
    }

    /// The edges of a page scrolled `scrollTop` points into a document `scrollHeight` tall, seen `viewportHeight` at a time.
    init(scrollTop: Double, viewportHeight: Double, scrollHeight: Double) {
        isAtTop = scrollTop <= Self.tolerance
        isAtBottom = scrollTop + viewportHeight >= scrollHeight - Self.tolerance
    }

    /// Whether a wheel step goes to the note rather than the page: the page has no more to show that way. A positive
    /// `deltaY` scrolls toward the page's top, as `NSEvent.scrollingDeltaY` reports it.
    func passesToNote(deltaY: Double) -> Bool {
        if deltaY < 0 { return isAtBottom }
        if deltaY > 0 { return isAtTop }
        return false
    }
}
