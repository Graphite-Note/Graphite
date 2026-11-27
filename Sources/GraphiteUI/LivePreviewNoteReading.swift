/**
 * File: LivePreviewNoteReading.swift
 * ----------------------------------
 * Layer: UI
 * Description: What a rendered callout or table reads from the rest of its note (footnote numbers, reference links,
 *              tasks, callout fold keys), and the pane's last reading a new block's view starts with.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.1
 * Date: 27/11/2026
 */

import SwiftUI
import GraphiteCore

/// What a callout or table reads from the rest of its note: the note's text is read once the block
/// is on screen and again when the block changes or moves, never in a body, so typing does not draw it again.
/// A new block's view starts with the pane's last reading (`readingAtHand`), which this confirms.
struct LivePreviewNoteReadingModifier: ViewModifier {
    let block: LivePreviewBlock
    let environment: LivePreviewEnvironment
    let currentLocation: (@MainActor () -> Int?)?
    @Binding var noteReading: RenderedBlockNoteReading?

    /// Changes when the block, or where it is in the note, does; nil for blocks that read nothing from the note.
    private var key: String? {
        guard environment.noteText != nil, block.kind == .table || block.kind == .callout else { return nil }
        return "\(block.range.location)|\(block.sourceLines)"
    }

    /// What the pane's last reading of the note says about the block, when the text it read still
    /// holds the block's lines where the block is now; nil otherwise, or for blocks that read
    /// nothing from the note. The note's text itself is not read: it is observed, and a view
    /// made in an update would then be drawn again at every keystroke.
    static func readingAtHand(of block: LivePreviewBlock, environment: LivePreviewEnvironment,
                              currentLocation: (@MainActor () -> Int?)?) -> RenderedBlockNoteReading? {
        guard environment.noteText != nil, block.kind == .table || block.kind == .callout else { return nil }
        let sourceRange = NSRange(location: currentLocation?() ?? block.range.location, length: block.range.length)
        guard let snapshot = environment.noteSnapshots?.latestSnapshot(holding: block.sourceLines, at: sourceRange) else { return nil }
        return RenderedBlockNoteReading(snapshot: snapshot, sourceMarkdown: block.markdown, sourceLines: block.sourceLines, sourceRange: sourceRange)
    }

    func body(content: Content) -> some View {
        let block = block
        let blockStart: @MainActor () -> Int? = currentLocation ?? { block.range.location }
        return content
            .environment(\.readingTaskContext, ReadingTaskContext.ofRenderedBlock(environment: environment, blockStart: blockStart))
            .environment(\.readingTagSearch, environment.tagSearch)
            .task(id: key) {
                guard key != nil, let noteText = environment.noteText?() else { noteReading = nil; return }
                let snapshot = environment.noteSnapshots?.snapshot(for: noteText) ?? NoteReadingSnapshot(noteText: noteText)
                // The note's text is as it is now, so the block is looked for where it is now.
                noteReading = RenderedBlockNoteReading(snapshot: snapshot, sourceMarkdown: block.markdown, sourceLines: block.sourceLines,
                                                       sourceRange: NSRange(location: blockStart() ?? block.range.location, length: block.range.length))
            }
    }
}
