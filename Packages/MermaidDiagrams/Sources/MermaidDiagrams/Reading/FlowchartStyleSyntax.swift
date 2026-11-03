/**
 * File: FlowchartStyleSyntax.swift
 * --------------------------------
 * Layer: Core
 * Description: Reads the statements that style a flowchart.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

/// A statement that styles a flowchart.
enum FlowchartStyleStatement: Equatable {
    /// `classDef name,other fill:#f9f,stroke:#333`: what the classes set.
    case classDefinition(names: [String], declarations: String)
    /// `class A,B name`: the nodes take the class.
    case classAssignment(identifiers: [String], className: String)
    /// `style A fill:#f9f,stroke:#333`: what the node sets for itself.
    case nodeStyle(identifier: String, declarations: String)
    /// `linkStyle 0,2 stroke:#f00` (the edges at those indexes, counted from 0 in the order written) or `linkStyle default stroke:#f00`
    /// (every edge, with `indices` nil).
    case linkStyle(indices: [Int]?, declarations: String)
}

/// Reads the text of the statements that style a flowchart (`classDef`, `class`, `style`, `linkStyle`), after their keyword.
enum FlowchartStyleSyntax {
    /// The statement `text` writes after `keyword`, or nil when it is not written as Mermaid writes it.
    static func statement(keyword: String, text: String) -> FlowchartStyleStatement? {
        let (head, rest) = split(text)
        guard !head.isEmpty else { return nil }
        switch keyword {
        case "classDef":
            let names = commaSeparated(head)
            return names.isEmpty ? nil : .classDefinition(names: names, declarations: rest)
        case "class":
            let identifiers = commaSeparated(head)
            let className = split(rest).head
            return identifiers.isEmpty || className.isEmpty ? nil : .classAssignment(identifiers: identifiers, className: className)
        case "style":
            return .nodeStyle(identifier: head, declarations: rest)
        case "linkStyle":
            if head == "default" { return .linkStyle(indices: nil, declarations: rest) }
            let indices = commaSeparated(head).compactMap { index in Int(index) }
            return indices.count == commaSeparated(head).count ? .linkStyle(indices: indices, declarations: rest) : nil
        default:
            return nil
        }
    }

    /// The first word of `text`, and what follows it.
    private static func split(_ text: String) -> (head: String, rest: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: { character in character == " " || character == "\t" }) else { return (trimmed, "") }
        return (String(trimmed[..<space]), trimmed[space...].trimmingCharacters(in: .whitespaces))
    }

    private static func commaSeparated(_ text: String) -> [String] {
        text.split(separator: ",").map { part in part.trimmingCharacters(in: .whitespaces) }.filter { part in !part.isEmpty }
    }
}
