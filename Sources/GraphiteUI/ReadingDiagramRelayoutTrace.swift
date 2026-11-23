/**
 * File: ReadingDiagramRelayoutTrace.swift
 * ---------------------------------------
 * Layer: UI
 * Description: Measures how long a diagram's column takes, from changing width, to show the diagram laid out again for it:
 *              signposts and a log line in debug builds and in builds made with GRAPHITE_DIAGRAM_TRACE, nothing otherwise.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation
import os

/// Measures a width change laid out again (`ReadingDiagramNarrowScenes`): the event "Column width" each time a diagram's
/// column changes width, the event "Narrow request" when a width to lay out is asked for (at once, or after the settling
/// wait), the interval "Narrow layout" around the layout off the main actor, a log line when the scene is back on the main
/// actor, and the event "Narrow scene shown" when the view's body shows the scene, with a log line giving the milliseconds
/// since the column last changed width. The frame that scene is drawn in is the next display refresh after that line. It
/// exists in debug builds and in builds made with the `GRAPHITE_DIAGRAM_TRACE` condition
/// (`OTHER_SWIFT_FLAGS=-DGRAPHITE_DIAGRAM_TRACE`), which measure an optimized build; in any other build every call
/// compiles to nothing. Instruments and `log show --signpost` show them under the
/// subsystem `com.graphite.study`, category `DiagramLayout`.
enum ReadingDiagramRelayoutTrace {
    #if DEBUG || GRAPHITE_DIAGRAM_TRACE
    private static let signposter = OSSignposter(subsystem: "com.graphite.study", category: "DiagramLayout")
    private static let logger = Logger(subsystem: "com.graphite.study", category: "DiagramLayout")
    private static let clock = ContinuousClock()

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
    #endif

    /// A diagram's column is now `width` points wide: the moment it changed, which the view keeps for
    /// `narrowSceneWasShown(forLayoutWidth:sinceColumnWidthChange:)`, or nil in a build that does not measure.
    @MainActor @inline(__always)
    static func columnDidChangeWidth(to width: CGFloat) -> ContinuousClock.Instant? {
        #if DEBUG || GRAPHITE_DIAGRAM_TRACE
        signposter.emitEvent("Column width", "\(Double(width), format: .fixed(precision: 1)) pt")
        return clock.now
        #else
        return nil
        #endif
    }

    /// A scene for a column `layoutWidth` layout points wide is asked for, laid out at once or after the settling wait.
    @MainActor @inline(__always)
    static func narrowSceneWasRequested(forLayoutWidth layoutWidth: CGFloat, waitsForTheColumnToSettle: Bool) {
        #if DEBUG || GRAPHITE_DIAGRAM_TRACE
        let start = waitsForTheColumnToSettle ? "after the settling wait" : "at once"
        signposter.emitEvent("Narrow request", "\(Double(layoutWidth), format: .fixed(precision: 0)) pt, \(start, privacy: .public)")
        #endif
    }

    /// Runs `work`, the layout for a column `layoutWidth` layout points wide, inside the interval "Narrow layout".
    @inline(__always)
    static func measureLayout<Outcome>(forLayoutWidth layoutWidth: CGFloat, _ work: () -> Outcome) -> Outcome {
        #if DEBUG || GRAPHITE_DIAGRAM_TRACE
        let start = clock.now
        let intervalState = signposter.beginInterval("Narrow layout", "\(Double(layoutWidth), format: .fixed(precision: 0)) pt")
        let outcome = work()
        signposter.endInterval("Narrow layout", intervalState)
        let layoutMilliseconds = milliseconds(start.duration(to: clock.now))
        logger.log("Narrow layout for \(Double(layoutWidth), format: .fixed(precision: 0)) pt took \(layoutMilliseconds, format: .fixed(precision: 2)) ms")
        return outcome
        #else
        return work()
        #endif
    }

    /// The scene laid out for a column `layoutWidth` layout points wide is back on the main actor, where the view's state
    /// takes it; the view's next update shows it.
    @MainActor @inline(__always)
    static func narrowSceneIsReady(forLayoutWidth layoutWidth: CGFloat, sinceColumnWidthChange columnWidthChange: ContinuousClock.Instant?) {
        #if DEBUG || GRAPHITE_DIAGRAM_TRACE
        let sinceWidthChange = columnWidthChange.map { change in milliseconds(change.duration(to: clock.now)) } ?? -1
        logger.log("""
            Narrow scene for \(Double(layoutWidth), format: .fixed(precision: 0)) pt back on the main actor \
            \(sinceWidthChange, format: .fixed(precision: 2)) ms after the column last changed width
            """)
        #endif
    }

    /// The view's body now shows the scene laid out for a column `layoutWidth` layout points wide; its column last changed
    /// width at `columnWidthChange`.
    @MainActor @inline(__always)
    static func narrowSceneWasShown(forLayoutWidth layoutWidth: CGFloat, sinceColumnWidthChange columnWidthChange: ContinuousClock.Instant?) {
        #if DEBUG || GRAPHITE_DIAGRAM_TRACE
        let sinceWidthChange = columnWidthChange.map { change in milliseconds(change.duration(to: clock.now)) } ?? -1
        signposter.emitEvent("Narrow scene shown", "\(Double(layoutWidth), format: .fixed(precision: 0)) pt")
        logger.log("""
            Narrow scene for \(Double(layoutWidth), format: .fixed(precision: 0)) pt shown \(sinceWidthChange, format: .fixed(precision: 2)) ms \
            after the column last changed width
            """)
        #endif
    }
}
