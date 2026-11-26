/**
 * File: SlidePosition.swift
 * -------------------------
 * Layer: Core
 * Description: Which slide of a presentation is shown, and the moves between slides that keys, swipes, taps and
 *              clicks ask for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// A move between the slides of a presentation.
public enum SlideMove: Equatable, Sendable {
    case next, previous, first, last
}

/// The slide shown among a presentation's slides. Moving past either end stays at the end, as reveal.js does in
/// Obsidian's Slides.
public struct SlidePosition: Equatable, Sendable {
    /// The zero-based index of the slide shown; 0 when there is no slide.
    public private(set) var index: Int
    public let slideCount: Int

    public init(slideCount: Int, index: Int = 0) {
        self.slideCount = max(0, slideCount)
        self.index = min(max(0, index), max(0, slideCount - 1))
    }

    /// The index after the slide shown, or nil on the last slide.
    public var nextIndex: Int? { index + 1 < slideCount ? index + 1 : nil }

    /// Moves to the slide `move` asks for, and tells whether the slide shown changed.
    @discardableResult
    public mutating func apply(_ move: SlideMove) -> Bool {
        guard slideCount > 0 else { return false }
        let newIndex: Int
        switch move {
        case .next: newIndex = min(index + 1, slideCount - 1)
        case .previous: newIndex = max(index - 1, 0)
        case .first: newIndex = 0
        case .last: newIndex = slideCount - 1
        }
        guard newIndex != index else { return false }
        index = newIndex
        return true
    }
}
