/**
 * File: ReadingEntityRelationshipDiagram.swift
 * --------------------------------------------
 * Layer: UI
 * Description: An entity relationship diagram laid out, its shapes ready to paint.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import MermaidDiagrams

/// An entity relationship diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingEntityRelationshipDiagram: Sendable {
    let layout: EntityRelationshipLayout
    let shapes: ReadingEntityRelationshipShapes
    /// The diagram laid out for a narrow column, turned to run down, or nil when it is narrow enough already or runs down.
    let narrow: ReadingNarrowLayout<EntityRelationshipLayout, ReadingEntityRelationshipShapes>?
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// What a screen reader reads without a description: each entity's text, then each relationship as its two
    /// entities around its label ("CUSTOMER places ORDER").
    let summary: [String]
    /// Statements read and not applied (`EntityRelationshipDiagram.unappliedStatementCount`): its styling is not drawn yet.
    let unappliedStatementCount: Int

    init(diagram: EntityRelationshipDiagram, layout: EntityRelationshipLayout, narrowLayout: EntityRelationshipLayout? = nil) {
        self.layout = layout
        shapes = ReadingEntityRelationshipShapes(parts: EntityRelationshipDrawingParts(layout: layout), font: layout.font)
        narrow = narrowLayout.map { narrowLayout in
            ReadingNarrowLayout(layout: narrowLayout,
                                shapes: ReadingEntityRelationshipShapes(parts: EntityRelationshipDrawingParts(layout: narrowLayout), font: narrowLayout.font))
        }
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        unappliedStatementCount = diagram.unappliedStatementCount
        let entityTexts = diagram.entities.map(\.label.spokenText)
        summary = entityTexts + diagram.relationships.map { relationship in
            [entityTexts[relationship.firstEntityIndex], relationship.label.spokenText, entityTexts[relationship.secondEntityIndex]]
                .filter { part in !part.isEmpty }.joined(separator: " ")
        }
    }
}

extension ReadingDiagram {
    /// An entity relationship diagram laid out in `typography`, or the source with why when it cannot be laid out (it has
    /// subgraphs, which are not laid out yet, or is too large).
    static func drawnEntityRelationship(_ diagram: EntityRelationshipDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        do {
            let layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            let narrowLayout = narrowLayout(of: diagram.turnedToRunDown, regularSize: layout.size, size: \.size) { turned in
                try EntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: .standard)
            }
            return .entityRelationship(ReadingEntityRelationshipDiagram(diagram: diagram, layout: layout, narrowLayout: narrowLayout))
        } catch {
            return .unreadable(source: source, failure: .entityRelationshipLayout(error))
        }
    }
}
