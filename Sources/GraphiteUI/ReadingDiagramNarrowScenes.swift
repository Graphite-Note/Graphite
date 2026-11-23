/**
 * File: ReadingDiagramNarrowScenes.swift
 * --------------------------------------
 * Layer: UI
 * Description: A diagram's narrow scene laid out again at the real width of the column that shows it, off the main actor, from
 *              the diagram already read: at once when the column jumps to a width, once it settles when it keeps changing,
 *              and kept per width so that a split being resized does not lay it out on every frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation
import MermaidDiagrams

/// The width a diagram's narrow scene is laid out again for: Obsidian draws Pele at its container's width, and the
/// prepared diagram's narrow scene is laid out for the standard 280 points (`PreparedMermaidDiagram.standardNarrowestColumnWidth`).
enum ReadingDiagramNarrowWidth {
    /// Column widths are rounded down to a multiple of this many layout points, so a split dragged a few points or the
    /// width a scroll bar takes lays nothing out again, and the scene laid out still fits the column.
    static let step: CGFloat = 8
    /// Below this width the standard narrow scene is shown scaled, as it was: no column of a reading view is narrower
    /// (an iPhone SE's is about 290 points), and Pele's narrowest plots stop near it (a treemap at 200 points).
    static let narrowest: CGFloat = 200

    /// The layout width to lay a narrow scene out for in a column `columnWidth` points wide, the diagram shown at
    /// `scaleAtNaturalWidth` times its laid-out size; nil when the column is not measured yet, narrower than `narrowest`,
    /// or rounds to the width the standard narrow scene was laid out for.
    static func layoutWidth(columnWidth: CGFloat, scaleAtNaturalWidth: CGFloat) -> CGFloat? {
        guard columnWidth > 0, scaleAtNaturalWidth > 0, columnWidth.isFinite, scaleAtNaturalWidth.isFinite else { return nil }
        let rounded = (columnWidth / scaleAtNaturalWidth / step).rounded(.down) * step
        guard rounded >= narrowest, rounded != PreparedMermaidDiagram.standardNarrowestColumnWidth else { return nil }
        return rounded
    }
}

/// A narrow scene to lay out again: the diagram's source (with the diagram read) and the column's width in layout points.
struct ReadingDiagramNarrowRequest: Equatable, Sendable {
    let source: ReadingDiagramSource
    let columnWidth: CGFloat

    /// The work itself, on the thread that calls it: only `ReadingDiagramNarrowScenes.prepare(_:preparing:)` calls it in the app.
    static func narrowScene(of request: ReadingDiagramNarrowRequest) -> DiagramScene? {
        ReadingDiagramRelayoutTrace.measureLayout(forLayoutWidth: request.columnWidth) {
            request.source.narrowScene(forColumnWidth: request.columnWidth)
        }
    }
}

/// A narrow scene laid out again for a request: the scene, or nil where the diagram's type draws it no narrower at that
/// width (a column shows the standard narrow scene then).
struct ReadingDiagramRedrawnNarrowScene: Sendable {
    let scene: DiagramScene?
}

/// The narrow scenes of one diagram's view laid out again at its column's real widths, so that a rotation back, a split
/// resized and back, or the view drawn again shows a width laid out before at once. Bounded: at most
/// `sceneCountLimit` widths, and `NSCache` lets them go when the system runs short of memory. Owned by the view
/// (`ReadingScaledDiagram`), which a lazy stack and Live Preview's pool keep while the diagram is scrolled away.
///
/// When a request is laid out: a column that jumps to a width after keeping its last one for `settlingDelay` (a rotation,
/// a sidebar shown or hidden, a split snapped to a size, the view first measured) has it laid out at once, so the scene
/// is shown within a frame or two of the jump; a request that comes within `settlingDelay` of the one before (a split
/// being dragged, whose rounded width changes every few frames) waits until the column has kept its width for
/// `settlingDelay` on `clock`, so a drag lays the diagram out where it starts and where it ends, never on every frame.
/// The layout is never on the main actor.
@MainActor
final class ReadingDiagramNarrowScenes {
    /// A few widths: the column's in each orientation and in a split, and one more.
    static let sceneCountLimit = 4
    /// Longer than the gaps between a dragged split's widths, rounded to 8 points (one to a few frames), so that a drag
    /// waits; short enough that its end is laid out soon after the finger stops.
    static let defaultSettlingDelay = Duration.milliseconds(100)

    private final class Entry {
        let redrawn: ReadingDiagramRedrawnNarrowScene
        init(redrawn: ReadingDiagramRedrawnNarrowScene) { self.redrawn = redrawn }
    }

    private let entries = NSCache<NSString, Entry>()
    private let settlingDelay: Duration
    /// The time on the settling clock since this object was made.
    private let elapsedTime: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    /// When the last request came, on `elapsedTime`; nil before the first.
    private var lastRequestTime: Duration?

    init<SettlingClock: Clock<Duration>>(settlingDelay: Duration = ReadingDiagramNarrowScenes.defaultSettlingDelay,
                                         clock: SettlingClock = ContinuousClock()) {
        self.settlingDelay = settlingDelay
        let origin = clock.now
        elapsedTime = { origin.duration(to: clock.now) }
        sleep = { duration in try await clock.sleep(for: duration) }
        entries.countLimit = Self.sceneCountLimit
    }

    /// The scene laid out for `request` already, or nil when it has not been.
    func redrawnScene(for request: ReadingDiagramNarrowRequest) -> ReadingDiagramRedrawnNarrowScene? {
        entries.object(forKey: Self.key(for: request))?.redrawn
    }

    /// The scene for `request`: the one kept, else laid out in a detached task and kept, at once when the column had
    /// kept its width for the settling delay before this request, after the delay when it had not. Nil when the task is
    /// cancelled while it waits (the column changed width again, or the view went). `preparing` is the work, given by a
    /// test that observes where it runs.
    func prepare(_ request: ReadingDiagramNarrowRequest,
                 preparing: @escaping @Sendable (ReadingDiagramNarrowRequest) -> DiagramScene? = ReadingDiagramNarrowRequest.narrowScene(of:))
        async -> ReadingDiagramRedrawnNarrowScene? {
        let requestTime = elapsedTime()
        let columnIsMoving = lastRequestTime.map { lastTime in requestTime - lastTime < settlingDelay } ?? false
        lastRequestTime = requestTime
        if let kept = redrawnScene(for: request) { return kept }
        ReadingDiagramRelayoutTrace.narrowSceneWasRequested(forLayoutWidth: request.columnWidth, waitsForTheColumnToSettle: columnIsMoving)
        if columnIsMoving {
            try? await sleep(settlingDelay) // A cancelled wait ends early, and the check below stops the work.
        }
        guard !Task.isCancelled else { return nil }
        let redrawn = await Task.detached(priority: .userInitiated) {
            ReadingDiagramRedrawnNarrowScene(scene: preparing(request))
        }.value
        entries.setObject(Entry(redrawn: redrawn), forKey: Self.key(for: request))
        return redrawn
    }

    /// The seconds a kept scene stands for the moment it was laid out on: only a Gantt chart's today marker depends on
    /// it, and a note built again a moment later (each edit in Live Preview) finds the scene kept.
    static let momentGranularitySeconds: TimeInterval = 3600

    /// The key of a request: its width, the font, the hour and time zone it was laid out in, and its text.
    private static func key(for request: ReadingDiagramNarrowRequest) -> NSString {
        let source = request.source
        let font = "\(source.font.postScriptName ?? "")|\(source.font.size)"
        let hour = (source.now.timeIntervalSinceReferenceDate / momentGranularitySeconds).rounded(.down)
        let day = "\(hour)|\(source.timeZone.identifier)"
        return "\(request.columnWidth)|\(font)|\(day)|\(source.text)" as NSString
    }
}
