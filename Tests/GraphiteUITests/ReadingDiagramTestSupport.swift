/**
 * File: ReadingDiagramTestSupport.swift
 * -------------------------------------
 * Layer: Tests
 * Description: What the diagram tests read of a mermaid block: the prepared diagram of a type, or why it is shown as its source.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import MermaidDiagrams
@testable import GraphiteUI

/// A block expected drawn as one type that was shown otherwise.
struct DiagramNotDrawnAsExpected: Error, CustomStringConvertible {
    let expected: MermaidDiagramKind
    let shown: ReadingDiagram

    var description: String {
        switch shown {
        case .drawn(let prepared): "Drawn as \(prepared.kind), not \(expected)"
        case .unreadable(_, let failure): "Shown as its source (\(failure)), not drawn as \(expected)"
        }
    }
}

extension ReadingDiagram {
    /// The prepared diagram, or nil for a source shown with why.
    var prepared: PreparedMermaidDiagram? {
        guard case .drawn(let prepared) = self else { return nil }
        return prepared
    }

    /// Why the block is shown as its source, or nil for a drawn diagram.
    var failure: MermaidDiagramPreparationFailure? {
        guard case .unreadable(_, let failure) = self else { return nil }
        return failure
    }

    /// The prepared diagram, when it is drawn as `kind`.
    func drawn(as kind: MermaidDiagramKind) throws -> PreparedMermaidDiagram {
        guard let prepared, prepared.kind == kind else { throw DiagramNotDrawnAsExpected(expected: kind, shown: self) }
        return prepared
    }
}

extension DiagramScene {
    /// The text of each line painted, back to front.
    var lineTexts: [String] {
        texts.flatMap { text in text.lines.map(\.text) }
    }

    /// The placed texts that read `text` on one line.
    func texts(reading text: String) -> [DiagramSceneText] {
        texts.filter { placed in placed.block.lines == [text] }
    }
}
