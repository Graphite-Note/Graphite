/**
 * File: ReadingStateDiagram.swift
 * -------------------------------
 * Layer: UI
 * Description: A state diagram laid out, its shapes ready to paint.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import MermaidDiagrams

/// A state diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingStateDiagram: Sendable {
    let layout: StateDiagramLayout
    let shapes: ReadingStateDiagramShapes
    /// The diagram laid out for a narrow column, turned to run down, or nil when it is narrow enough already or runs down.
    let narrow: ReadingNarrowLayout<StateDiagramLayout, ReadingStateDiagramShapes>?
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The names of the composite states, then of the states drawn as boxes, in the order the diagram names them.
    let stateNames: [String]
    /// Statements read and not applied (`StateDiagram.unappliedStatementCount`): its styling is not drawn yet.
    let unappliedStatementCount: Int

    init(diagram: StateDiagram, layout: StateDiagramLayout, narrowLayout: StateDiagramLayout? = nil) {
        self.layout = layout
        shapes = ReadingStateDiagramShapes(parts: StateDiagramDrawingParts(layout: layout), font: layout.font)
        narrow = narrowLayout.map { narrowLayout in
            ReadingNarrowLayout(layout: narrowLayout,
                                shapes: ReadingStateDiagramShapes(parts: StateDiagramDrawingParts(layout: narrowLayout), font: narrowLayout.font))
        }
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        unappliedStatementCount = diagram.unappliedStatementCount
        // A composite state is named by its box's title, before the states it holds.
        stateNames = layout.composites.compactMap { composite in composite.title?.lines.joined(separator: " ") }
            + layout.states.compactMap { state in state.name?.lines.joined(separator: " ") }
    }
}
