/**
 * File: CompactLinkLines.swift
 * ----------------------------
 * Layer: Core
 * Description: Paragraphs that each hold one link to a note, one after another, drawn as one compact list of lines, as
 *              Notion draws its links to pages; the note's text is never changed.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import Foundation

public enum CompactLinkLines {
    /// The text a run of Markdown is drawn from: every blank line between two paragraphs that each hold only one wikilink
    /// becomes a line break, so the links stand one per line. A run with code fences or tasks is left as it is, since
    /// its lines are found again by their number.
    public static func compacted(_ markdown: String) -> String {
        guard markdown.contains("[["), !markdown.contains("```"), !markdown.contains("~~~"), !markdown.contains("- [") else { return markdown }
        let lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            output.append(line)
            index += 1
            guard isLinkLine(line) else { continue }
            // Blank lines, then another link line: the blank lines go and the link is kept on the next line.
            var nextIndex = index
            while nextIndex < lines.count, lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty { nextIndex += 1 }
            if nextIndex > index, nextIndex < lines.count, isLinkLine(lines[nextIndex]) {
                output[output.count - 1] = line + hardLineBreak
                index = nextIndex
            }
        }
        return output.joined(separator: "\n")
    }

    /// CommonMark's hard line break, which keeps the lines apart whatever the vault's strict line breaks setting.
    static let hardLineBreak = "  "

    /// Whether a line holds one wikilink to a note and nothing else, an alias allowed.
    public static func isLinkLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return false }
        let inner = trimmed.dropFirst(2).dropLast(2)
        return !inner.contains("[") && !inner.contains("]")
    }
}
