/**
 * File: ReadingDiagramNarrowScenes.swift
 * --------------------------------------
 * Layer: UI
 * Description: A diagram's narrow scene laid out again at the real width of the column that shows it, off the main actor, and
 *              kept per width so that a rotation or a split being resized does not lay it out on every frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
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

/// A narrow scene to lay out again: the diagram's source and the column's width in layout points.
struct ReadingDiagramNarrowRequest: Equatable, Sendable {
    let source: ReadingDiagramSource
    let columnWidth: CGFloat

    /// The work itself, on the thread that calls it: only `ReadingDiagramNarrowScenes.prepare(_:preparing:)` calls it in the app.
    static func narrowScene(of request: ReadingDiagramNarrowRequest) -> DiagramScene? {
        request.source.narrowScene(forColumnWidth: request.columnWidth)
    }
}

/// A narrow scene laid out again for a request: the scene, or nil where the diagram's type draws it no narrower at that
/// width (a column shows the standard narrow scene then).
struct ReadingDiagramRedrawnNarrowScene: Sendable {
    let scene: DiagramScene?
}

/// The narrow scenes laid out again at columns' real widths, shared by the reading view and Live Preview so that a diagram
/// scrolled back into view, or the same diagram in both, shows its scene at once instead of the standard one first, then
/// jumping in height. Bounded: at most `sceneCountLimit` scenes (a few widths of a few diagrams: a rotation, a split
/// resized, two panes), and `NSCache` lets them go when the system runs short of memory. A request is prepared only after
/// the column has kept its width for `settlingDelay`, so a split dragged across the screen lays the diagram out once,
/// where the drag ends, and never on the main actor.
final class ReadingDiagramNarrowScenes: @unchecked Sendable {
    // Sendable by hand: NSCache is thread-safe, and the class has no other mutable state.
    static let shared = ReadingDiagramNarrowScenes()

    static let sceneCountLimit = 32
    static let defaultSettlingDelay = Duration.milliseconds(150)

    private final class Entry {
        let redrawn: ReadingDiagramRedrawnNarrowScene
        init(redrawn: ReadingDiagramRedrawnNarrowScene) { self.redrawn = redrawn }
    }

    private let entries = NSCache<NSString, Entry>()
    private let settlingDelay: Duration

    init(settlingDelay: Duration = ReadingDiagramNarrowScenes.defaultSettlingDelay) {
        self.settlingDelay = settlingDelay
        entries.countLimit = Self.sceneCountLimit
    }

    /// The scene laid out for `request` already, or nil when it has not been.
    func redrawnScene(for request: ReadingDiagramNarrowRequest) -> ReadingDiagramRedrawnNarrowScene? {
        entries.object(forKey: Self.key(for: request))?.redrawn
    }

    /// The scene for `request`: the one kept, else, once the column has kept its width for the settling delay, laid out
    /// in a detached task and kept. Nil when the task is cancelled first (the column changed width again, or the view
    /// went). `preparing` is the work, given by a test that observes where it runs.
    func prepare(_ request: ReadingDiagramNarrowRequest,
                 preparing: @escaping @Sendable (ReadingDiagramNarrowRequest) -> DiagramScene? = ReadingDiagramNarrowRequest.narrowScene(of:))
        async -> ReadingDiagramRedrawnNarrowScene? {
        if let kept = redrawnScene(for: request) { return kept }
        // A cancelled wait ends early; the check below then stops the preparation.
        try? await Task.sleep(for: settlingDelay)
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
