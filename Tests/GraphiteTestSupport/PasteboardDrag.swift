/**
 * File: PasteboardDrag.swift
 * --------------------------
 * Layer: Tests
 * Description: A drag over a Mac window told to its views as AppKit tells a drag destination: the dragging info of a
 *              real pasteboard, the view under each point that registered for its types or a SwiftUI drop destination
 *              named, entered, updated, exited, held there, and the drop handed over only after an operation that is
 *              not none.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

#if os(macOS)
import AppKit

/// What a drag destination reads while a drag is over it: the pasteboard the drag carries and the pointer's place in
/// the window. AppKit's own dragging info comes only from the window server following a hand on the hardware, so a test
/// gives this one in its place, with a pasteboard written as the dragging app writes it.
/// AppKit declares the protocol without an actor but calls it only on the main thread, as the test does
/// (`@preconcurrency`).
@MainActor
public final class PasteboardDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    public let draggingPasteboard: NSPasteboard
    public let draggingDestinationWindow: NSWindow?
    public let draggingSourceOperationMask: NSDragOperation
    public let draggingSequenceNumber: Int
    /// The pointer, in the window's coordinates.
    public var draggingLocation: NSPoint
    public var draggingFormation: NSDraggingFormation = .default
    public var animatesToDestination = false
    public var numberOfValidItemsForDrop = 1

    private static var lastSequenceNumber = 0

    /// - Parameter sourceOperationMask: What the dragging app allows; the Finder allows every operation for its files.
    public init(pasteboard: NSPasteboard, window: NSWindow, location: NSPoint, sourceOperationMask: NSDragOperation = .every) {
        draggingPasteboard = pasteboard
        draggingDestinationWindow = window
        draggingLocation = location
        draggingSourceOperationMask = sourceOperationMask
        Self.lastSequenceNumber += 1
        draggingSequenceNumber = Self.lastSequenceNumber
    }

    public var draggedImageLocation: NSPoint { draggingLocation }
    public var draggedImage: NSImage? { nil }
    /// Another application's drag has no source in this one.
    public var draggingSource: Any? { nil }
    public var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    public func slideDraggedImage(to screenPoint: NSPoint) {}
    public func resetSpringLoading() {}

    public func enumerateDraggingItems(options enumerationOptions: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                       classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                       using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let objects = draggingPasteboard.readObjects(forClasses: classArray, options: searchOptions) ?? []
        var stop = ObjCBool(false)
        for (index, object) in objects.enumerated() {
            guard let writing = object as? any NSPasteboardWriting else { continue }
            block(NSDraggingItem(pasteboardWriter: writing), index, &stop)
            if stop.boolValue { return }
        }
    }
}

/// A drag through points of a window, its views told what AppKit tells a drag destination.
@MainActor
public struct PasteboardDrag {
    /// What one drag did: each destination's answer along the way, and whether the drop was handed over and taken.
    public struct Outcome {
        public var operations: [NSDragOperation] = []
        public var destinations: [NSView] = []
        public var wasHandedOver = false
        public var wasTaken = false
    }

    public let pasteboard: NSPasteboard
    public let window: NSWindow
    /// The view the drag is told to wherever it is under the pointer, or nil to find it as AppKit finds an AppKit view.
    public let namedDestination: NSView?

    public init(pasteboard: NSPasteboard, window: NSWindow, destination namedDestination: NSView? = nil) {
        self.pasteboard = pasteboard
        self.window = window
        self.namedDestination = namedDestination
    }

    /// The view a drag at `windowPoint` goes to: the one the drag was made for, when it is under the point, else the
    /// deepest view under the point that registered for one of the pasteboard's types, as AppKit finds an AppKit view.
    /// SwiftUI's drop destinations are views of their own laid over the content (`_PlatformDraggingDestinationView`),
    /// registered for `public.data` and `public.item`, which a hit test does not find: a drag to one names it.
    public func destination(at windowPoint: NSPoint) -> NSView? {
        if let namedDestination {
            return namedDestination.visibleRect.contains(namedDestination.convert(windowPoint, from: nil)) ? namedDestination : nil
        }
        let carriedTypes = Set(pasteboard.types ?? [])
        var view = window.contentView?.superview?.hitTest(windowPoint) ?? window.contentView?.hitTest(windowPoint)
        while let candidate = view {
            if !carriedTypes.isDisjoint(with: candidate.registeredDraggedTypes) { return candidate }
            view = candidate.superview
        }
        return nil
    }

    /// A view as a drag destination, whose methods it may leave out.
    private static func told(_ view: NSView) -> any NSDraggingDestination { view }

    /// A drag held over the window, not let go yet.
    public struct Hover {
        fileprivate let info: PasteboardDraggingInfo
        fileprivate var current: NSView?
        fileprivate var lastOperation: NSDragOperation = []
        public fileprivate(set) var outcome = Outcome()
    }

    /// Moves the drag through the points and lets go at the last (`hover(through:)`, then `letGo(_:)`).
    @discardableResult
    public func move(through windowPoints: [NSPoint]) -> Outcome {
        letGo(hover(through: windowPoints))
    }

    /// Moves the drag through the points, holding it at the last: `draggingEntered` when it comes over a destination,
    /// `draggingUpdated` while it stays, `draggingExited` when it leaves.
    public func hover(through windowPoints: [NSPoint]) -> Hover {
        var hover = Hover(info: PasteboardDraggingInfo(pasteboard: pasteboard, window: window, location: windowPoints.first ?? .zero))
        for point in windowPoints {
            hover.info.draggingLocation = point
            let underPointer = destination(at: point)
            if underPointer !== hover.current {
                hover.current.map { view in Self.told(view).draggingExited?(hover.info) }
                hover.current = underPointer
                hover.lastOperation = underPointer.flatMap { view in Self.told(view).draggingEntered?(hover.info) } ?? []
            } else {
                hover.lastOperation = hover.current.flatMap { view in Self.told(view).draggingUpdated?(hover.info) } ?? []
            }
            hover.outcome.operations.append(hover.lastOperation)
            if let underPointer { hover.outcome.destinations.append(underPointer) }
        }
        return hover
    }

    /// Lets go where the drag is held: the drop is handed over only when the destination's last answer was not none
    /// (`prepareForDragOperation`, `performDragOperation`, `concludeDragOperation`), else the destination is told the
    /// drag left; `draggingEnded` last.
    public func letGo(_ hover: Hover) -> Outcome {
        var outcome = hover.outcome
        guard let current = hover.current else { return outcome }
        let destination = Self.told(current)
        if !hover.lastOperation.isEmpty, destination.prepareForDragOperation?(hover.info) ?? true {
            outcome.wasHandedOver = true
            outcome.wasTaken = destination.performDragOperation?(hover.info) ?? false
            if outcome.wasTaken { destination.concludeDragOperation?(hover.info) }
        } else {
            destination.draggingExited?(hover.info)
        }
        destination.draggingEnded?(hover.info)
        return outcome
    }
}
#endif
