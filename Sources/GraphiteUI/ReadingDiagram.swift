/**
 * File: ReadingDiagram.swift
 * --------------------------
 * Layer: UI
 * Description: A mermaid block as the reading view shows it: the diagram prepared for drawing, with what prepares it again for
 *              another column, or its source with why.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.29
 * Date: 24/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws. Whatever the diagram's type, it is one preparation of the package
/// (`MermaidDiagramPreparation`): nothing here knows the types, so a type the package adds is drawn with no change here.
enum ReadingDiagram: Sendable {
    /// A diagram read and laid out: its scene, its scene for the standard narrow column (280 points) where its type has one,
    /// and what a screen reader says of it; with its `source`, the diagram as read, which lays its narrow scene out again for
    /// a column of another width without reading it again (`ReadingDiagramNarrowScenes`), as Obsidian draws Pele again at
    /// its container's width.
    case drawn(PreparedMermaidDiagram, source: ReadingDiagramSource)
    /// A diagram whose text could not be read or laid out, of a type or holding what is not drawn yet, with nothing to
    /// draw, or too large to draw: its source is shown with why, never a bare code block that looks as if nothing was
    /// meant to be drawn, nor an empty or a giant view.
    case unreadable(source: String, failure: MermaidDiagramPreparationFailure)

    /// The diagram a block's text describes, laid out in `typography`; a Gantt chart is scheduled on the moment and in the
    /// time zone of `WallClock`.
    init(source: String, typography: DiagramTypography) {
        do {
            let diagramSource = try ReadingDiagramSource(text: source, font: typography.font, now: WallClock.currentDate(),
                                                         timeZone: WallClock.currentTimeZone())
            let prepared = try diagramSource.prepared(in: typography)
            if Self.narrowSceneMayBeShown(regularWidth: prepared.scene.size.width) { _ = prepared.narrowScene }
            self = .drawn(prepared, source: diagramSource)
        } catch {
            self = .unreadable(source: source, failure: error)
        }
    }

    /// Whether a column could show the narrow scene of a diagram whose regular scene is `regularWidth` points wide, at the
    /// text size it was laid out in: a column at least the narrowest (280 points) wide shows it only where the regular
    /// scene, fitted to the column, would be smaller than the readable scale (`ReadingScaledDiagram.showsNarrowScene`),
    /// so a diagram no wider than 280 / 0.6 points never shows it. MermaidDiagrams 0.7.0 lays the narrow scene out the
    /// first time it is read; a diagram that may show it has it read here, off the main actor where diagrams are prepared,
    /// so the view that shows it does not lay it out on the main actor, and one that never shows it is never laid out
    /// narrow. (A text size changed since the note was built, or a column narrower than 280 points, can still have a view
    /// read it first.)
    static func narrowSceneMayBeShown(regularWidth: CGFloat) -> Bool {
        regularWidth * ReadingDiagramPresentation.smallestReadableScale > PreparedMermaidDiagram.standardNarrowestColumnWidth
    }

    /// How many statements of the diagram are read and not applied (styling a diagram type does not draw yet, `click`);
    /// 0 for a source shown with why.
    var unappliedStatementCount: Int {
        guard case .drawn(let prepared, _) = self else { return 0 }
        return prepared.unappliedStatementCount
    }
}

/// What a drawn diagram was prepared from: its text and the diagram read from it, the font it was laid out in, and the
/// moment and time zone a Gantt chart was scheduled on. Kept with the prepared diagram so that its narrow scene can be
/// laid out again at a column's real width from the same diagram, font and day, without reading the text again.
struct ReadingDiagramSource: Equatable, Sendable {
    let text: String
    /// `text` read (`MermaidDiagramReader`): a layout for another width starts from it.
    let diagram: MermaidDiagram
    let font: DiagramFont
    let now: Date
    let timeZone: TimeZone

    /// `text` read in the package's standard limits, as `MermaidDiagramPreparation.prepare(source:typography:)` reads it;
    /// a text that is not read fails as that preparation fails (`MermaidDiagramPreparationFailure.reading`).
    init(text: String, font: DiagramFont, now: Date, timeZone: TimeZone) throws(MermaidDiagramPreparationFailure) {
        let diagram: MermaidDiagram
        do {
            diagram = try MermaidDiagramReader.read(text, limits: .standard)
        } catch {
            throw .reading(error)
        }
        self.init(text: text, diagram: diagram, font: font, now: now, timeZone: timeZone)
    }

    /// `diagram`, read from `text` already.
    init(text: String, diagram: MermaidDiagram, font: DiagramFont, now: Date, timeZone: TimeZone) {
        self.text = text
        self.diagram = diagram
        self.font = font
        self.now = now
        self.timeZone = timeZone
    }

    /// Two sources are the same when their text, font and day are: the diagram is read from the text, so comparing the
    /// text says whether the diagrams are the same without walking them (a view's task compares its request at each update).
    static func == (leftSource: ReadingDiagramSource, rightSource: ReadingDiagramSource) -> Bool {
        leftSource.text == rightSource.text && leftSource.font == rightSource.font && leftSource.now == rightSource.now
            && leftSource.timeZone == rightSource.timeZone
    }

    /// The diagram prepared in `typography` (whose font is `font`), its narrow scene laid out for a column
    /// `narrowestColumnWidth` wide.
    func prepared(in typography: DiagramTypography,
                  narrowestColumnWidth: CGFloat = PreparedMermaidDiagram.standardNarrowestColumnWidth)
        throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(diagram, typography: typography, limits: .standard, narrowestColumnWidth: narrowestColumnWidth,
                                              now: now, timeZone: timeZone)
    }

    /// The diagram's scene for a column `columnWidth` layout points wide, as Pele draws it for a container that wide, or
    /// nil where its type draws it no narrower there. The diagram already read is laid out again (its regular and its
    /// narrow scene, as the package's preparation makes both), in measurers made for the font; the text is not read
    /// again. Call it off the main actor.
    func narrowScene(forColumnWidth columnWidth: CGFloat) -> DiagramScene? {
        try? prepared(in: DiagramTypography(font: font), narrowestColumnWidth: columnWidth).narrowScene // A failure keeps the standard scene.
    }
}
