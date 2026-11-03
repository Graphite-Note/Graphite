/**
 * File: ReadAloudFolding.swift
 * ----------------------------
 * Layer: Core
 * Description: What Read Aloud leaves out because it is folded, and the keys callouts are remembered by.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 01/11/2026
 */

import Foundation

/// What Read Aloud leaves out because the person folded it away: hiding something is a choice
/// not to hear it. A folded callout (`> [!note]- Title`, or any callout the person collapsed)
/// is read as its title only; its body is skipped. A folded heading's section and a folded
/// list item's children are skipped. Expanding them in the view brings them back.
public enum ReadAloudFolding {
    /// The key under which a callout's live expansion is remembered: its type and written
    /// title, the same for the reading view and Live Preview. Callouts that share a type and
    /// title are told apart by `occurrence`, the count of such callouts before it in the note
    /// (`calloutOccurrences(in:)`), so opening one does not open the others. The first has the
    /// key it always had.
    public static func calloutKey(type: String, title: String, occurrence: Int = 0) -> String {
        let key = type.lowercased() + "|" + title.trimmingCharacters(in: .whitespaces)
        return occurrence == 0 ? key : key + "|" + String(occurrence)
    }

    /// For each callout of `text`, nested ones included, how many callouts with the same type
    /// and title come before it: by the offset at which the line holding its header starts.
    /// Read Aloud, the reading view and Live Preview all number callouts from here.
    public static func calloutOccurrences(in text: String) -> [Int: Int] {
        var occurrencesByHeaderLineStart: [Int: Int] = [:]
        var countsByKey: [String: Int] = [:]
        for callout in callouts(in: text) {
            let key = calloutKey(type: callout.header.type, title: callout.header.title)
            let occurrence = countsByKey[key, default: 0]
            countsByKey[key] = occurrence + 1
            occurrencesByHeaderLineStart[callout.headerLineStart] = occurrence
        }
        return occurrencesByHeaderLineStart
    }

    /// The source ranges to leave out of narration. `calloutExpansion` holds the person's
    /// own expansions by `calloutKey`; a callout not in it starts as its marker says.
    public static func hiddenRanges(in text: String, foldedKeys: Set<String>, calloutExpansion: [String: Bool]) -> [NSRange] {
        let hidden = NoteFolding.foldedRegions(in: NoteFolding.regions(in: text), foldedKeys: foldedKeys).map(\.hiddenRange)
        var countsByKey: [String: Int] = [:]
        var hiddenByCallouts: [NSRange] = []
        for callout in callouts(in: text) {
            let baseKey = calloutKey(type: callout.header.type, title: callout.header.title)
            let occurrence = countsByKey[baseKey, default: 0]
            countsByKey[baseKey] = occurrence + 1
            let isExpanded = calloutExpansion[calloutKey(type: callout.header.type, title: callout.header.title,
                occurrence: occurrence)] ?? (callout.header.folding != .collapsed)
            // A callout inside a folded one is left out with it already.
            if !isExpanded, let bodyRange = callout.bodyRange, !hiddenByCallouts.contains(where: { range in NSIntersectionRange(range,
                bodyRange).length == bodyRange.length }) {
                hiddenByCallouts.append(bodyRange)
            }
        }
        return hidden + hiddenByCallouts
    }

    private struct FoundCallout {
        let headerLineStart: Int
        let header: (type: String, title: String, folding: CalloutFolding)
        /// The lines of the body, nil when it has none.
        let bodyRange: NSRange?
    }

    /// The callouts of `text` in document order, a callout before the ones in its body: found
    /// in quoted lines as the reading view finds them, outside `%%` comments.
    private static func callouts(in text: String) -> [FoundCallout] {
        let source = text as NSString
        var lines: [(text: String, range: NSRange)] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            lines.append((source.substring(with: lineRange), enclosingRange))
        }
        var found: [FoundCallout] = []
        findCallouts(in: lines, depth: 0, commentRanges: SortedRangeSet(ObsidianComments.commentRanges(in: text)), into: &found)
        return found
    }

    /// Finds callouts in quoted lines, as the reading view does; the callouts in the body of
    /// one are found in turn.
    private static func findCallouts(in lines: [(text: String, range: NSRange)], depth: Int, commentRanges: SortedRangeSet, into found: inout [FoundCallout]) {
        guard depth < 8 else { return }
        var index = 0
        while index < lines.count {
            guard let header = MarkdownQuoteSyntax.calloutHeader(in: lines[index].text),
                  !commentRanges.intersects(NSRange(location: lines[index].range.location, length: max(lines[index].range.length,
                      1))) else { index += 1; continue }
            let bodyLineCount = MarkdownQuoteSyntax.calloutBodyLineCount(afterHeaderAt: index, lineCount: lines.count) { bodyIndex in lines[bodyIndex].text }
            let bodyLines = (index + 1..<index + 1 + bodyLineCount).map { bodyIndex in
                (text: MarkdownQuoteSyntax.calloutBodyLine(lines[bodyIndex].text).content, range: lines[bodyIndex].range)
            }
            var bodyRange: NSRange?
            if let first = bodyLines.first, let last = bodyLines.last { bodyRange = NSUnionRange(first.range, last.range) }
            found.append(FoundCallout(headerLineStart: lines[index].range.location, header: header, bodyRange: bodyRange))
            findCallouts(in: bodyLines, depth: depth + 1, commentRanges: commentRanges, into: &found)
            index += 1 + bodyLineCount
        }
    }
}
