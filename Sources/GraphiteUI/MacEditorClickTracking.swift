/**
 * File: MacEditorClickTracking.swift
 * ----------------------------------
 * Layer: UI
 * Description: Tells a click on a link or task box in the Mac's note editor from a drag that starts there.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(macOS)
import AppKit

/// What a press on a link or a drawn task box turns out to be. A link is followed and a box
/// ticked on release, so a selection can start on either.
enum MacEditorClickOutcome: Equatable {
    case released, dragged

    /// How far the pointer moves, in points, before a press is a drag.
    private static let dragDistance: CGFloat = 3

    /// Reads the events after a press at `start` until the button is released or the pointer moves away.
    static func following(pressAt start: CGPoint, nextEvent: () -> (type: NSEvent.EventType, location: CGPoint)?) -> MacEditorClickOutcome {
        while let event = nextEvent() {
            if event.type == .leftMouseUp { return .released }
            if hypot(event.location.x - start.x, event.location.y - start.y) > dragDistance { return .dragged }
        }
        return .released
    }
}
#endif
