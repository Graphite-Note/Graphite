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
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The names of the states drawn as boxes, in the order the diagram names them.
    let stateNames: [String]
    /// Statements read and not applied (`StateDiagram.unappliedStatementCount`): its styling is not drawn yet.
    let unappliedStatementCount: Int

    init(diagram: StateDiagram, layout: StateDiagramLayout) {
        self.layout = layout
        shapes = ReadingStateDiagramShapes(parts: StateDiagramDrawingParts(layout: layout), font: layout.font)
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        unappliedStatementCount = diagram.unappliedStatementCount
        stateNames = layout.states.compactMap { state in state.name?.lines.joined(separator: " ") }
    }
}
