/**
 * File: ReadingClassDiagram.swift
 * -------------------------------
 * Layer: UI
 * Description: A class diagram laid out, its shapes ready to paint.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import MermaidDiagrams

/// A class diagram laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingClassDiagram: Sendable {
    let layout: ClassDiagramLayout
    let shapes: ReadingClassDiagramShapes
    /// The diagram laid out for a narrow column, turned to run down, or nil when it is narrow enough already or runs down.
    let narrow: ReadingNarrowLayout<ClassDiagramLayout, ReadingClassDiagramShapes>?
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The name of each class as its box shows it, in the order the diagram names them.
    let classNames: [String]
    /// Statements read and not applied (`ClassDiagram.unappliedStatementCount`): its styling is not drawn yet.
    let unappliedStatementCount: Int

    init(diagram: ClassDiagram, layout: ClassDiagramLayout, narrowLayout: ClassDiagramLayout? = nil) {
        self.layout = layout
        shapes = ReadingClassDiagramShapes(parts: ClassDiagramDrawingParts(layout: layout), font: layout.font)
        narrow = narrowLayout.map { narrowLayout in
            ReadingNarrowLayout(layout: narrowLayout,
                                shapes: ReadingClassDiagramShapes(parts: ClassDiagramDrawingParts(layout: narrowLayout), font: narrowLayout.font))
        }
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        unappliedStatementCount = diagram.unappliedStatementCount
        classNames = diagram.classes.map(\.displayedName.spokenText)
    }
}
