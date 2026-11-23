/**
 * File: ReadingDiagram.swift
 * --------------------------
 * Layer: UI
 * Description: A mermaid block as the reading view shows it: the diagram prepared for drawing, with what prepares it again for
 *              another column, or its source with why.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.27
 * Date: 23/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws. Whatever the diagram's type, it is one preparation of the package
/// (`MermaidDiagramPreparation`): nothing here knows the types, so a type the package adds is drawn with no change here.
enum ReadingDiagram: Sendable {
    /// A diagram read and laid out: its scene, its scene for the standard narrow column (280 points) where its type has one,
    /// and what a screen reader says of it; with its `source`, which lays its narrow scene out again for a column of
    /// another width (`ReadingDiagramNarrowScenes`), as Obsidian draws Pele again at its container's width.
    case drawn(PreparedMermaidDiagram, source: ReadingDiagramSource)
    /// A diagram whose text could not be read or laid out, of a type or holding what is not drawn yet, with nothing to
    /// draw, or too large to draw: its source is shown with why, never a bare code block that looks as if nothing was
    /// meant to be drawn, nor an empty or a giant view.
    case unreadable(source: String, failure: MermaidDiagramPreparationFailure)

    /// The diagram a block's text describes, laid out in `typography`; a Gantt chart is scheduled on the moment and in the
    /// time zone of `WallClock`.
    init(source: String, typography: DiagramTypography) {
        let diagramSource = ReadingDiagramSource(text: source, font: typography.font, now: WallClock.currentDate(),
                                                 timeZone: WallClock.currentTimeZone())
        do {
            self = .drawn(try diagramSource.prepared(in: typography), source: diagramSource)
        } catch {
            self = .unreadable(source: source, failure: error)
        }
    }

    /// How many statements of the diagram are read and not applied (styling a diagram type does not draw yet, `click`);
    /// 0 for a source shown with why.
    var unappliedStatementCount: Int {
        guard case .drawn(let prepared, _) = self else { return 0 }
        return prepared.unappliedStatementCount
    }
}

/// What a drawn diagram was prepared from: its text, the font it was laid out in, and the moment and time zone a Gantt
/// chart was scheduled on. Kept with the prepared diagram so that its narrow scene can be laid out again at a column's
/// real width with the same text, font and day.
struct ReadingDiagramSource: Equatable, Sendable {
    let text: String
    let font: DiagramFont
    let now: Date
    let timeZone: TimeZone

    /// The diagram prepared in `typography` (whose font is `font`), its narrow scene laid out for a column
    /// `narrowestColumnWidth` wide.
    func prepared(in typography: DiagramTypography,
                  narrowestColumnWidth: CGFloat = PreparedMermaidDiagram.standardNarrowestColumnWidth)
        throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: text, typography: typography, narrowestColumnWidth: narrowestColumnWidth, now: now,
                                              timeZone: timeZone)
    }

    /// The diagram's scene for a column `columnWidth` layout points wide, as Pele draws it for a container that wide, or
    /// nil where its type draws it no narrower there. The whole diagram is read and laid out again, in measurers made
    /// for the font (about 40 µs): call it off the main actor.
    func narrowScene(forColumnWidth columnWidth: CGFloat) -> DiagramScene? {
        try? prepared(in: DiagramTypography(font: font), narrowestColumnWidth: columnWidth).narrowScene
    }
}
