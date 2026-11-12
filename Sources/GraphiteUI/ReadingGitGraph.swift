/**
 * File: ReadingGitGraph.swift
 * ---------------------------
 * Layer: UI
 * Description: A Git graph laid out, its shapes ready to paint.
 *
 * Authors: Félix Chevalier
 * Version: 0.2
 * Date: 01/11/2026
 */

import MermaidDiagrams

/// A Git graph laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingGitGraph: Sendable {
    let layout: GitGraphLayout
    let shapes: ReadingGitGraphShapes
    /// The diagram laid out for a narrow column, turned to run down, or nil when it is narrow enough already or runs down.
    let narrow: ReadingNarrowLayout<GitGraphLayout, ReadingGitGraphShapes>?
    /// `accTitle`, else the title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each branch with the ids written for its commits and their tags, in the order of the lanes: “main: init, v1.0”.
    let branchTexts: [String]

    init(diagram: GitGraphDiagram, layout: GitGraphLayout, narrowLayout: GitGraphLayout? = nil) {
        self.layout = layout
        shapes = ReadingGitGraphShapes(parts: GitGraphDrawingParts(layout: layout), font: layout.font)
        narrow = narrowLayout.map { narrowLayout in
            ReadingNarrowLayout(layout: narrowLayout,
                                shapes: ReadingGitGraphShapes(parts: GitGraphDrawingParts(layout: narrowLayout), font: narrowLayout.font))
        }
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        var commitTextsByBranch = diagram.branches.map { _ in [String]() }
        for commit in diagram.commits {
            commitTextsByBranch[commit.branchIndex] += (commit.hasWrittenIdentifier ? [commit.identifier] : []) + commit.tags.map(\.spokenText)
        }
        branchTexts = zip(diagram.branches, commitTextsByBranch).map { branch, commitTexts in
            commitTexts.isEmpty ? branch.label.spokenText : branch.label.spokenText + ": " + commitTexts.joined(separator: ", ")
        }
    }

    /// The reading view's diagram for a Git graph, or its source with why when it sets options of Git graphs, which are
    /// not applied (`GitGraphLayoutError.optionsNotApplied`).
    static func diagram(_ diagram: GitGraphDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        do {
            let layout = try GitGraphLayoutEngine.layout(diagram, typography: typography)
            let narrowLayout = ReadingDiagram.narrowLayout(of: diagram.turnedToRunDown, regularSize: layout.size, size: \.size) { turned in
                try GitGraphLayoutEngine.layout(turned, typography: typography)
            }
            return .gitGraph(ReadingGitGraph(diagram: diagram, layout: layout, narrowLayout: narrowLayout))
        } catch {
            return .unreadable(source: source, failure: .gitGraphLayout(error))
        }
    }
}
