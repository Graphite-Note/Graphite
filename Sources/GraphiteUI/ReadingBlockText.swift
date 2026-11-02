/**
 * File: ReadingBlockText.swift
 * ----------------------------
 * Layer: UI
 * Description: The text steps that make one block of a note's Markdown read as the reading view
 *              reads it, shared with Live Preview's rendered blocks (a callout, a table): line
 *              breaks, links to notes, footnote numbers, reference links, tasks and callout fold keys.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

/// The reading-view steps that need no index, in one place so a block in Live Preview and a
/// block in the reading view of the same note read alike.
enum ReadingBlockText {
    /// Where the task on a line of a block's text, given by its index, is in the note.
    typealias TaskLocation = (_ lineIndex: Int, _ status: Unicode.Scalar) -> ReadingTasks.Location?

    /// Obsidian's inline syntax rewritten for the renderer, and a single line break made a
    /// line break unless the vault keeps strict line breaks.
    static func readingText(_ markdown: String, colorsEnabled: Bool, paletteHexByName: [String: String], usesStrictLineBreaks: Bool,
                            taskLocation: TaskLocation? = nil) -> String {
        var text = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: colorsEnabled, paletteHexByName: paletteHexByName,
            taskLocation: taskLocation)
        if !usesStrictLineBreaks { text = ObsidianPreviewText.applyingSoftLineBreaks(to: text) }
        return text
    }

    /// Where a Markdown link's destination is written, when it is a path in the vault such
    /// as `../Syllabus.md` or `#Heading` rather than a web address. The renderer would
    /// resolve such a path against the vault folder instead of the note's own folder. A
    /// reference link, or a destination written with escapes, is left to the renderer.
    static func notePathDestinationRange(of link: NoteLink, in text: NSString, linkRange: NSRange) -> NSRange? {
        let destination = link.target
        guard !destination.isEmpty, destination.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil,
              // The destination follows `](`, possibly inside `<>`; the same text in the label
              // or in a title after the destination is not it.
              let destinationPattern = try? NSRegularExpression(pattern: "\\]\\([ \\t]*\\n?[ \\t]*<?(" + NSRegularExpression.escapedPattern(for: destination) + ")"), // Escaped note text; malformed: link left as is.
              let match = destinationPattern.matches(in: text as String, range: linkRange).last else { return nil }
        return match.range(at: 1)
    }

    /// `markdown` with each Markdown link to a path or heading of the note's own vault written
    /// as the link the renderer follows (`GraphiteOpenLink`). Only the destinations change,
    /// so the lines stay as they were.
    static func rewritingNoteLinks(in markdown: String) -> String {
        guard markdown.contains("](") else { return markdown }
        // As in the reading view: a block that starts with `---` has no frontmatter.
        let leadingPadding = FrontmatterLocator.length(in: markdown as NSString) > 0 ? "\n" : ""
        let paddingLength = (leadingPadding as NSString).length
        guard let semantics = try? MarkdownSemantics.parse(leadingPadding + markdown) else { return markdown } // Unparsable text keeps its links as written.
        let projected = NSMutableString(string: markdown)
        var earliestReplacedLocation = Int.max
        for link in semantics.links.reversed() where link.length > 0 && !link.isWiki && !link.isEmbed {
            let linkRange = NSRange(location: link.location - paddingLength, length: link.length)
            guard NSMaxRange(linkRange) <= earliestReplacedLocation, linkRange.location >= 0, NSMaxRange(linkRange) <= projected.length,
                  let destinationRange = notePathDestinationRange(of: link, in: projected, linkRange: linkRange) else { continue }
            let target = GraphiteOpenLink.markdownLinkTarget(destination: link.target)
            projected.replaceCharacters(in: destinationRange, with: GraphiteOpenLink.markdownDestination(target: target, isWiki: false))
            earliestReplacedLocation = linkRange.location
        }
        return projected as String
    }
}

/// What a rendered Live Preview block takes from the rest of its note to read as the reading
/// view reads the note: the numbers of its footnotes, the reference links defined elsewhere,
/// the order of its callouts among those of the same title, and where it is for its tasks.
struct RenderedBlockNoteReading: Equatable {
    struct FootnoteReference: Equatable {
        /// Where the reference is in `sourceMarkdown`.
        let range: NSRange
        let number: Int
    }

    /// The Markdown the block is drawn from, as the editor found it in the note.
    let sourceMarkdown: String
    /// The block's lines as the note has them (`LivePreviewBlock.sourceLines`), which a task's
    /// place and checksum are of.
    let sourceLines: String
    let lineOffsets: RenderedBlockLineOffsets
    let footnoteReferences: [FootnoteReference]
    let referenceDefinitions: [ReferenceLinkDefinitions.Definition]
    /// The position among callouts of the same type and title (`ReadAloudFolding.calloutOccurrences`)
    /// of the callout whose header line starts at an offset of `sourceMarkdown`.
    let calloutOccurrencesByLineStart: [Int: Int]

    /// Reads the parts of `noteText` that the block at `sourceRange` needs.
    init(noteText: String, sourceMarkdown: String, sourceLines: String? = nil, sourceRange: NSRange) {
        self.init(snapshot: NoteReadingSnapshot(noteText: noteText), sourceMarkdown: sourceMarkdown, sourceLines: sourceLines, sourceRange: sourceRange)
    }

    /// The same from what the note's text was already read for.
    init(snapshot: NoteReadingSnapshot, sourceMarkdown: String, sourceLines: String? = nil, sourceRange: NSRange) {
        self.sourceMarkdown = sourceMarkdown
        let sourceLines = sourceLines ?? sourceMarkdown
        self.sourceLines = sourceLines
        let lineOffsets = RenderedBlockLineOffsets(markdown: sourceMarkdown, sourceLines: sourceLines)
        self.lineOffsets = lineOffsets
        func isInBlock(_ range: NSRange) -> Bool { range.location >= sourceRange.location && NSMaxRange(range) <= NSMaxRange(sourceRange) }
        footnoteReferences = snapshot.footnoteReferences.filter { reference in isInBlock(reference.range) }.map { reference in
            let location = lineOffsets.markdownOffset(ofSourceOffset: reference.range.location - sourceRange.location)
            return FootnoteReference(range: NSRange(location: location, length: reference.range.length), number: reference.number)
        }
        referenceDefinitions = snapshot.referenceDefinitions
        var occurrences: [Int: Int] = [:]
        for (lineStart, occurrence) in snapshot.calloutOccurrencesByLineStart where lineStart >= sourceRange.location && lineStart < NSMaxRange(sourceRange) {
            occurrences[lineOffsets.markdownOffset(ofSourceOffset: lineStart - sourceRange.location)] = occurrence
        }
        calloutOccurrencesByLineStart = occurrences
    }

    /// The position among same-titled callouts of the callout whose header is on the line
    /// holding `sourceOffset`.
    func calloutOccurrence(atSourceOffset offset: Int) -> Int {
        let source = sourceMarkdown as NSString
        guard offset >= 0, offset <= source.length else { return 0 }
        return calloutOccurrencesByLineStart[source.lineRange(for: NSRange(location: offset, length: 0)).location] ?? 0
    }

    /// A short text that changes when anything a block reads from its note does.
    var key: String {
        let numbers = footnoteReferences.map { reference in "\(reference.range.location):\(reference.number)" }.joined(separator: ",")
        return "\(numbers)|\(referenceDefinitions.map(\.line).joined(separator: "\n"))"
    }
}

/// Offsets of a rendered block's Markdown, whose lines end at a line feed, and of its lines as
/// the note has them, where a Windows note's end at "\r\n". They are the same lines, so only
/// what each such line break adds differs.
struct RenderedBlockLineOffsets: Equatable {
    /// Where in the Markdown each line after a "\r\n" starts; empty for most notes.
    private let markdownStartsAfterWindowsBreaks: [Int]

    init(markdown: String, sourceLines: String) {
        guard markdown.utf16.count != sourceLines.utf16.count else {
            markdownStartsAfterWindowsBreaks = []
            return
        }
        var starts: [Int] = []
        var markdownOffset = 0
        var previousUnit: UInt16?
        for unit in sourceLines.utf16 {
            if unit == 0x0A, previousUnit == 0x0D {
                starts.append(markdownOffset)
            } else {
                markdownOffset += 1
            }
            previousUnit = unit
        }
        markdownStartsAfterWindowsBreaks = starts
    }

    func sourceOffset(ofMarkdownOffset offset: Int) -> Int {
        offset + markdownStartsAfterWindowsBreaks.prefix { start in start <= offset }.count
    }

    func markdownOffset(ofSourceOffset offset: Int) -> Int {
        // A line's start is later in the source by the "\r\n" breaks up to and including the one before it.
        var breaksBefore = 0
        for (position, start) in markdownStartsAfterWindowsBreaks.enumerated() where start + position + 1 <= offset { breaksBefore = position + 1 }
        return offset - breaksBefore
    }
}

/// A run of Markdown in a rendered block, and where its lines are in the block's source.
struct RenderedBlockPlace: Equatable {
    let reading: RenderedBlockNoteReading
    /// The offset in `reading.sourceMarkdown` at which each line of the run starts.
    let lineOffsets: [Int]

    var key: String { reading.key + "|" + (lineOffsets.first.map(String.init) ?? "") }

    /// The offset at which each line of `markdown` starts, lines ending at a line feed.
    static func lineOffsets(of markdown: String) -> [Int] {
        var offsets = [0]
        var offset = 0
        for codeUnit in markdown.utf16 {
            offset += 1
            if codeUnit == 0x0A { offsets.append(offset) }
        }
        return offsets
    }

    /// Where the task on a line of the run is, as the reading view finds it, counted from the
    /// start of the block's lines as the note has them, with the checksum of its line there. The
    /// block moves with edits above it while its view stays, so the note's offset is worked out
    /// when the checkbox is tapped (`ReadingTasks.Location.inNote(blockStart:)`).
    func taskLocation(lineIndex: Int, status: Unicode.Scalar) -> ReadingTasks.Location? {
        guard lineOffsets.indices.contains(lineIndex),
              let location = ReadingTasks.location(ofTaskStartingAt: lineOffsets[lineIndex], status: status, in: reading.sourceMarkdown) else { return nil }
        return ReadingTasks.location(ofStatusAt: reading.lineOffsets.sourceOffset(ofMarkdownOffset: location.statusOffset), in: reading.sourceLines)
    }

    /// `markdown` with each footnote reference in it written as the raised number that
    /// links to the footnote, as the reading view writes it. A reference that is not where
    /// the block's source has it is left as written.
    func substitutingFootnoteReferences(in markdown: String) -> String {
        guard !reading.footnoteReferences.isEmpty else { return markdown }
        let text = markdown as NSString
        let source = reading.sourceMarkdown as NSString
        var lineStarts = [0]
        for index in 0..<text.length where text.character(at: index) == 0x0A { lineStarts.append(index + 1) }
        var replacements: [(range: NSRange, text: String)] = []
        for reference in reading.footnoteReferences {
            guard let lineIndex = lineOffsets.lastIndex(where: { offset in offset <= reference.range.location }),
                lineStarts.indices.contains(lineIndex) else { continue }
            let range = NSRange(location: lineStarts[lineIndex] + reference.range.location - lineOffsets[lineIndex], length: reference.range.length)
            guard NSMaxRange(range) <= text.length, NSMaxRange(reference.range) <= source.length,
                  text.substring(with: range) == source.substring(with: reference.range) else { continue }
            replacements.append((range, "[\(reference.number)](\(GraphiteOpenLink.footnoteDestination(number: reference.number)))"))
        }
        let output = NSMutableString(string: markdown)
        for replacement in replacements.sorted(by: { first, second in first.range.location > second.range.location }) {
            output.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return output as String
    }
}

/// What a note's text says about footnotes, reference links and callouts, read once for the
/// text however many rendered blocks ask: the note is read again only when its text changes.
struct NoteReadingSnapshot {
    let footnoteReferences: [(range: NSRange, number: Int)]
    let referenceDefinitions: [ReferenceLinkDefinitions.Definition]
    let calloutOccurrencesByLineStart: [Int: Int]

    init(noteText: String) {
        footnoteReferences = noteText.contains("[^") || noteText.contains("^[") ? Footnotes.referenceNumbers(in: noteText) : []
        referenceDefinitions = ReferenceLinkDefinitions.definitions(in: noteText)
        calloutOccurrencesByLineStart = noteText.contains("[!") ? ReadAloudFolding.calloutOccurrences(in: noteText) : [:]
    }
}

/// The last two notes asked about (two panes side by side), kept so a note with many callouts and tables is read once.
@MainActor
final class NoteReadingSnapshots {
    private var recent: [(text: String, snapshot: NoteReadingSnapshot)] = []

    func snapshot(for noteText: String) -> NoteReadingSnapshot {
        if let known = recent.first(where: { entry in entry.text == noteText }) { return known.snapshot }
        let snapshot = NoteReadingSnapshot(noteText: noteText)
        recent.insert((noteText, snapshot), at: 0)
        if recent.count > 2 { recent.removeLast() }
        return snapshot
    }
}

extension ReadingTasks.Location {
    /// A rendered block's task, whose offset is counted from the block's start
    /// (`RenderedBlockPlace.taskLocation`), in the note, where the block now starts at `blockStart`.
    func inNote(blockStart: Int) -> ReadingTasks.Location {
        ReadingTasks.Location(statusOffset: statusOffset + blockStart, lineChecksum: lineChecksum)
    }
}

extension ReadingTaskContext {
    /// What ticks the tasks of a rendered Live Preview block. Its view stays while its block moves
    /// with edits above it, so where the block starts is asked when the tap comes; nil, when the
    /// block is no longer in the note, ticks nothing. Nil without a way to tick.
    @MainActor
    static func ofRenderedBlock(environment: LivePreviewEnvironment, blockStart: @escaping @MainActor () -> Int?) -> ReadingTaskContext? {
        environment.toggleTask.map { toggleTask in
            ReadingTaskContext(note: environment.notePath ?? VaultPath.root) { _, location in
                guard let blockStart = blockStart() else { return false }
                return await toggleTask(location.inNote(blockStart: blockStart))
            }
        }
    }
}
