/**
 * File: NoteViewModeSwitch.swift
 * ------------------------------
 * Layer: UI
 * Description: A note's view mode and where its views start after a switch between reading and writing.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// What a switch of view mode changed.
enum NoteViewModeChange: Equatable {
    case unchanged
    /// Between Live Preview and source mode.
    case changedWhileWriting
    case enteredReading
    /// From the reading view to writing, with the character at the reading view's top, where the editor starts; nil at
    /// the note's top.
    case leftReading(topLocation: Int?)
}

/// A note's view mode, with the places its views start at after a switch: the reading view at the line that was at the
/// top of the editor, the editor at the character that was at the top of the reading view. Each place is taken once.
struct NoteViewModeSwitch {
    private(set) var mode: NoteViewMode = .livePreview
    /// Whether the reading view, about to be shown, starts at the line that was at the top of the editor rather than where
    /// it was itself. The editor records that line as it goes off screen, after the switch.
    private var readingStartsWhereEditorWas = false
    /// Where the editor, about to be shown, starts: the character that was at the top of the reading view.
    private var pendingEditingLocation: Int?

    /// Switches to `newMode`; `readingTopLocation` is asked only when the switch leaves the reading view.
    mutating func switchMode(to newMode: NoteViewMode, readingTopLocation: () -> Int?) -> NoteViewModeChange {
        let oldMode = mode
        mode = newMode
        guard newMode != oldMode else { return .unchanged }
        guard (oldMode == .reading) != (newMode == .reading) else { return .changedWhileWriting }
        if newMode == .reading {
            readingStartsWhereEditorWas = true
            return .enteredReading
        }
        let topLocation = readingTopLocation()
        pendingEditingLocation = topLocation ?? 0
        return .leftReading(topLocation: topLocation)
    }

    /// Sets whether the reading view about to be shown starts where the editor was, as when a note reopens at its place.
    mutating func startsReadingWhereEditorWas(_ startsThere: Bool) {
        readingStartsWhereEditorWas = startsThere
    }

    /// Whether the reading view starts where the editor was, once, after the note switched from writing.
    mutating func takeReadingStartsWhereEditorWas() -> Bool {
        defer { readingStartsWhereEditorWas = false }
        return readingStartsWhereEditorWas
    }

    /// The character the editor starts at, once, after the note switched from reading.
    mutating func takeEditingStartLocation() -> Int? {
        defer { pendingEditingLocation = nil }
        return pendingEditingLocation
    }
}
