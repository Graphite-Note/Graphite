/**
 * File: ReadingDiagram.swift
 * --------------------------
 * Layer: UI
 * Description: A mermaid block as the reading view shows it: the diagram prepared for drawing, or its source with why.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.26
 * Date: 19/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws. Whatever the diagram's type, it is one preparation of the package
/// (`MermaidDiagramPreparation`): nothing here knows the types, so a type the package adds is drawn with no change here.
enum ReadingDiagram: Sendable {
    /// A diagram read and laid out: its scene, its scene for a narrow column where its type has one, and what a screen
    /// reader says of it.
    case drawn(PreparedMermaidDiagram)
    /// A diagram whose text could not be read or laid out, of a type or holding what is not drawn yet, with nothing to
    /// draw, or too large to draw: its source is shown with why, never a bare code block that looks as if nothing was
    /// meant to be drawn, nor an empty or a giant view.
    case unreadable(source: String, failure: MermaidDiagramPreparationFailure)

    /// The diagram a block's text describes, laid out in `typography`; a Gantt chart is scheduled on the moment and in the
    /// time zone of `WallClock`.
    init(source: String, typography: DiagramTypography) {
        do {
            self = .drawn(try MermaidDiagramPreparation.prepare(source: source, typography: typography, now: WallClock.currentDate(),
                                                                timeZone: WallClock.currentTimeZone()))
        } catch {
            self = .unreadable(source: source, failure: error)
        }
    }

    /// How many statements of the diagram are read and not applied (styling a diagram type does not draw yet, `click`);
    /// 0 for a source shown with why.
    var unappliedStatementCount: Int {
        guard case .drawn(let prepared) = self else { return 0 }
        return prepared.unappliedStatementCount
    }
}
