/**
 * File: WebFrameLiveSelection.swift
 * ---------------------------------
 * Layer: Core
 * Description: Which of a note's web frames show their page live, from how far each is from the screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// Decides which web frames of a scrolling note hold a live page. A page costs a web view and a web process, so only
/// the frames near the screen hold one: a frame loads its page once it is within `loadingDistance` screens of being
/// seen, keeps it until it is more than `releaseDistance` screens away (so a small scroll back and forth does not load
/// it again), and never more than `maximumLiveCount` frames hold one at once, the nearest first.
public enum WebFrameLiveSelection {
    /// Distances are in screen heights: 0 for a frame on screen, 1 for one a whole screen above or below it.
    public static let loadingDistance = 1.0
    public static let releaseDistance = 3.0
    public static let maximumLiveCount = 4

    /// The frames that hold a live page, from each frame's distance to the screen and the frames live now.
    public static func liveFrames<Frame: Hashable>(distances: [Frame: Double], currentlyLive: Set<Frame>,
                                                   loadingDistance: Double = loadingDistance, releaseDistance: Double = releaseDistance,
                                                   maximumLiveCount: Int = maximumLiveCount) -> Set<Frame> {
        let candidates = distances.filter { frame, distance in
            distance <= loadingDistance || (currentlyLive.contains(frame) && distance <= releaseDistance)
        }
        // The nearest win; between two as near, the one already live keeps its page.
        let ranked = candidates.sorted { leftEntry, rightEntry in
            if leftEntry.value != rightEntry.value { return leftEntry.value < rightEntry.value }
            return currentlyLive.contains(leftEntry.key) && !currentlyLive.contains(rightEntry.key)
        }
        return Set(ranked.prefix(max(0, maximumLiveCount)).map(\.key))
    }

    /// How many screen heights a frame spanning `frameTop` to `frameBottom` is from a screen spanning `visibleTop` to
    /// `visibleBottom`, all in one vertical coordinate space; 0 when they overlap.
    public static func distance(frameTop: Double, frameBottom: Double, visibleTop: Double, visibleBottom: Double) -> Double {
        let screenHeight = max(1, visibleBottom - visibleTop)
        if frameBottom < visibleTop { return (visibleTop - frameBottom) / screenHeight }
        if frameTop > visibleBottom { return (frameTop - visibleBottom) / screenHeight }
        return 0
    }
}
