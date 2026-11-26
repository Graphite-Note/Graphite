/**
 * File: PresentationControls.swift
 * --------------------------------
 * Layer: UI
 * Description: What a key, a tap, a swipe or a click does while a note is presented: Obsidian's Slides keys
 *              (reveal.js's), the tap zones and the swipe directions, decided from plain values.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// What the person asks of a presentation.
enum PresentationRequest: Equatable {
    case move(SlideMove)
    case end
}

/// The keys of a presentation, those of Obsidian's Slides (reveal.js): right, down, space, Page Down, Return and
/// `N` forward, left, up, Page Up, Delete, Shift-space and `P` back, Home and End to the ends, Escape to end.
enum PresentationKeys {
    static func request(for key: KeyEquivalent, modifiers: EventModifiers) -> PresentationRequest? {
        switch key {
        case .rightArrow, .downArrow, .pageDown, .return: return .move(.next)
        case .leftArrow, .upArrow, .pageUp, .delete, .deleteForward: return .move(.previous)
        case .home: return .move(.first)
        case .end: return .move(.last)
        case .escape: return .end
        case .space: return .move(modifiers.contains(.shift) ? .previous : .next)
        default: break
        }
        switch key.character.lowercased() {
        case "n": return .move(.next)
        case "p": return .move(.previous)
        default: return nil
        }
    }
}

/// Taps, swipes and clicks on a slide (decision 6). A finger's tap on the left quarter goes back, elsewhere
/// forward; a swipe to the left goes forward, to the right back. Apple Pencil is never one of them.
enum PresentationTouches {
    /// The share of the slide's width, from its left edge, where a tap goes back.
    static let backZoneShare: CGFloat = 0.25

    static func move(forTapAtX tapX: CGFloat, width: CGFloat) -> SlideMove {
        width > 0 && tapX < width * backZoneShare ? .previous : .next
    }

    /// The move of a horizontal swipe that went `horizontalDistance` points, to the right when positive.
    static func move(forSwipeDistance horizontalDistance: CGFloat) -> SlideMove {
        horizontalDistance < 0 ? .next : .previous
    }
}

/// The time since a presentation started, as the presenter's view shows it: minutes and seconds, with hours
/// once it runs past an hour.
enum PresentationElapsedTime {
    static func text(for elapsed: Duration) -> String {
        let totalSeconds = max(0, Int(elapsed.components.seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let minutesAndSeconds = String(format: "%02d:%02d", minutes, seconds)
        return hours > 0 ? "\(hours):\(minutesAndSeconds)" : minutesAndSeconds
    }
}
