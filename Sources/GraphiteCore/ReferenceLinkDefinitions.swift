/**
 * File: ReferenceLinkDefinitions.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reference-style link definitions found anywhere in a note and given to the blocks that use them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// Reference-style links (`[the docs][1]`) name a definition (`[1]: https://example.com`) that
/// may be anywhere in the note. The reading view and Live Preview draw a note one block at a
/// time (a paragraph run, a callout, a table), and a block can only read definitions it holds,
/// so each block that uses a label is given the definition from the rest of the note.
package enum ReferenceLinkDefinitions {
    package struct Definition: Equatable, Sendable {
        /// The label as links compare it: lowercased, with runs of spaces made one.
        package let label: String
        /// The definition's line as written.
        package let line: String
    }

    private static let definitionPattern = ReferenceLinkDefinitionsPattern.definitionPattern.compiled()

    /// The definitions of `markdown` outside code, in order. A footnote's `[^label]:` is none.
    package static func definitions(in markdown: String) -> [Definition] {
        guard markdown.contains("]:") else { return [] }
        var fenceTracker = CodeFenceTracker()
        var definitions: [Definition] = []
        for line in markdown.components(separatedBy: "\n") {
            guard !fenceTracker.isCodeLine(untrimmedLine: line), line.contains("]:") else { continue }
            let source = line as NSString
            guard let match = definitionPattern.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { continue }
            definitions.append(Definition(label: normalizedLabel(source.substring(with: match.range(at: 1))),
                line: line.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return definitions
    }

    /// `run` followed by the definitions it needs and lacks: those of `definitions` whose label
    /// it writes in brackets and does not define itself.
    package static func appendingDefinitions(_ definitions: [Definition], neededBy run: String) -> String {
        guard !definitions.isEmpty, run.contains("[") else { return run }
        let ownLabels = Set(Self.definitions(in: run).map(\.label))
        let writtenText = normalizedLabel(run)
        let missing = definitions.filter { definition in !ownLabels.contains(definition.label) && writtenText.contains("[" + definition.label + "]") }
        guard !missing.isEmpty else { return run }
        return run + "\n\n" + missing.map(\.line).joined(separator: "\n")
    }

    private static func normalizedLabel(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The constant patterns of `ReferenceLinkDefinitions`; `StaticPatternTests` compiles every case.
enum ReferenceLinkDefinitionsPattern: String, StaticPatternSet {
    /// `[label]: destination`, up to three spaces in; group 1 is the label, which does not start a footnote's `^`.
    case definitionPattern = #"^ {0,3}\[([^\]\^][^\]]*)\]:[ \t]*\S"#
}
