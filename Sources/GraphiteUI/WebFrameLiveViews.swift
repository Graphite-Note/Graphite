/**
 * File: WebFrameLiveViews.swift
 * -----------------------------
 * Layer: UI
 * Description: Where a note's web frames may show their page live, and which frames of a scrolling reading view hold one.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import SwiftUI
import GraphiteCore

/// Where a web frame is shown, which decides whether it may hold a live page.
enum WebFramePresentation: Equatable, Sendable {
    /// A note being read or written: the page loads when the frame comes near the screen.
    case live
    /// A link's preview card, a canvas card or anywhere a live page does not fit: the frame's box with its address.
    case placeholder
    /// A note printed to PDF: the box, cut to a printable height, with the page's name and address.
    case printed
}

/// The web frames of one reading view and which of them hold a live page (`WebFrameLiveSelection`). Each frame reports
/// how far it is from the screen as the note scrolls, and forgets itself when the view lets it go, so a long note holds
/// only the few pages near the screen. The reading view keeps one; a note without frames never asks it anything.
@MainActor @Observable
final class WebFrameLiveViews {
    private(set) var liveFrames: Set<UUID> = []
    @ObservationIgnored private var distancesByFrame: [UUID: Double] = [:]

    func isLive(_ frame: UUID) -> Bool { liveFrames.contains(frame) }

    /// Records how many screens away a frame is now, nil when not known (not laid out in a scroll view).
    func report(distance: Double?, of frame: UUID) {
        distancesByFrame[frame] = distance
        decide()
    }

    func forget(_ frame: UUID) {
        guard distancesByFrame.removeValue(forKey: frame) != nil || liveFrames.contains(frame) else { return }
        decide()
    }

    private func decide() {
        let decided = WebFrameLiveSelection.liveFrames(distances: distancesByFrame, currentlyLive: liveFrames)
        // Only a change is written, so frames that move without changing the decision draw nothing again.
        if decided != liveFrames { liveFrames = decided }
    }
}

extension EnvironmentValues {
    /// Placeholder unless a view that shows a note to read or write says otherwise, so a new place that shows a
    /// note's blocks makes no web view until it decides to.
    @Entry var webFramePresentation: WebFramePresentation = .placeholder
    /// The reading view's frames; nil where each frame is live while it is shown, as in Live Preview, which shows a
    /// block's view only while its lines are near the screen.
    @Entry var webFrameLiveViews: WebFrameLiveViews? = nil
}
