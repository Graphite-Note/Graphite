/**
 * File: NoteTextIndex.swift
 * -------------------------
 * Layer: UI
 * Description: Where the lines of a note start, and which of the callouts with the same type and title
 *              each is, found once for the note however many blocks of the reading view ask.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// A note's text read once and asked about many times, as the reading view builds each of the
/// note's blocks: the line of an offset used to copy and count the note up to it, which made
/// building a long note quadratic in its size.
final class NoteTextIndex {
    private let text: String
    /// How many times the text was scanned, which a test counts.
    private(set) var lineScanCount = 0
    private lazy var lineStartOffsets: [Int] = {
        lineScanCount += 1
        var starts = [0]
        var offset = 0
        for codeUnit in text.utf16 {
            offset += 1
            if codeUnit == 0x0A { starts.append(offset) }
        }
        return starts
    }()
    private lazy var calloutOccurrencesByLineStart: [Int: Int] = text.contains("[!") ? ReadAloudFolding.calloutOccurrences(in: text) : [:]

    init(text: String) { self.text = text }

    /// The offset at which the line holding `offset` starts.
    func lineStart(containingOffset offset: Int) -> Int {
        lineStartOffsets[lineIndex(containingOffset: offset)]
    }

    /// The zero-based line holding `offset`, counting lines that end at a line feed.
    func lineIndex(containingOffset offset: Int) -> Int {
        var lowerBound = 0
        var upperBound = lineStartOffsets.count
        // The number of line starts at or before the offset, less the first.
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if lineStartOffsets[middleIndex] <= offset { lowerBound = middleIndex + 1 } else { upperBound = middleIndex }
        }
        return max(lowerBound - 1, 0)
    }

    /// Which of the callouts with the type and title of the one whose header is on the line
    /// holding `offset` it is, from zero.
    func calloutOccurrence(atOffset offset: Int) -> Int {
        calloutOccurrencesByLineStart[lineStart(containingOffset: offset)] ?? 0
    }
}

/// The text of the note a run of blocks was split from, in which their tasks are found.
struct ReadingTaskSource {
    /// The whole note, frontmatter included, which a tap on a checkbox changes.
    let noteText: String
    /// Where a place in the body the blocks were split from is in `noteText`; nil for
    /// text the note does not have, such as a footnote's number.
    let noteOffset: (_ bodyOffset: Int) -> Int?
    /// Leads the title of each callout in its fold key, so the callouts of an embedded
    /// note do not open or close the note's own callouts of the same title.
    let foldKeyPrefix: String
    /// The definitions of reference-style links in the note, which a block that uses one is
    /// given even when the definition is in another block.
    let referenceDefinitions: [ReferenceLinkDefinitions.Definition]
    private let index: NoteTextIndex

    init(noteText: String, foldKeyPrefix: String = "", noteOffset: @escaping (_ bodyOffset: Int) -> Int?) {
        self.noteText = noteText
        self.foldKeyPrefix = foldKeyPrefix
        self.noteOffset = noteOffset
        referenceDefinitions = ReferenceLinkDefinitions.definitions(in: noteText)
        index = NoteTextIndex(text: noteText)
    }

    /// The zero-based line of the note on which a place in the body is.
    func noteLine(ofBodyOffset bodyOffset: Int) -> Int? {
        noteOffset(bodyOffset).map { offset in index.lineIndex(containingOffset: offset) }
    }

    /// Which of the note's callouts with the type and title of the one starting at a place
    /// in the body this is.
    func calloutOccurrence(ofCalloutAtBodyOffset bodyOffset: Int) -> Int {
        noteOffset(bodyOffset).map { offset in index.calloutOccurrence(atOffset: offset) } ?? 0
    }
}
