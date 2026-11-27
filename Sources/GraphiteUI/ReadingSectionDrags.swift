/**
 * File: ReadingSectionDrags.swift
 * -------------------------------
 * Layer: UI
 * Description: A heading of a note in the reading view can be dragged: onto a PDF page it becomes the section's
 *              picture that links to it (`SectionLinkTransfer`), and into a note it is written as a link to it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// What the reading view's headings need to be dragged: the note, its text as shown, and where
/// each of its own top-level blocks starts in that text (`ReadingBlockLocation`). Headings
/// alone are dragged here, so the text of paragraphs can still be selected by dragging.
struct ReadingSectionDrags {
    let notePath: VaultPath
    let noteText: String
    let vaultRoot: URL
    /// UTF-16 offsets in the note of its own top-level blocks, by block.
    let blockOffsets: [String: Int]

    /// The drag of a block's section: the section a page turns into its picture, and
    /// `[[Note#Heading]]` as text for a note or another app. Nil for a block that is not
    /// one of the note's own, as in an embedded note.
    func itemProvider(forBlock blockIdentifier: String) -> NSItemProvider? {
        guard let offset = blockOffsets[blockIdentifier] else { return nil }
        // A heading's line has no block identifier to add; `identifierEdit` is nil for it.
        let link = SectionLink.link(startingAt: offset, in: noteText, notePath: notePath).link
        let provider = NSItemProvider(object: ("[[" + link.linkText + "]]") as NSString)
        // Nothing to prepare: the Mac's pasteboard reads the transfer while the main thread waits.
        SectionLinkTransfer.register(SectionLinkTransfer(link: link, vaultRoot: vaultRoot), on: provider)
        provider.suggestedName = link.title
        return provider
    }
}

extension EnvironmentValues {
    /// Set by the reading view of a note for its own blocks; nil elsewhere.
    @Entry var readingSectionDrags: ReadingSectionDrags? = nil
}

extension View {
    /// Lets the block be dragged as its section where the reading view gives it one.
    @ViewBuilder func sectionDrag(ofBlock blockIdentifier: String, from drags: ReadingSectionDrags?) -> some View {
        if let drags, drags.blockOffsets[blockIdentifier] != nil {
            onDrag { drags.itemProvider(forBlock: blockIdentifier) ?? NSItemProvider() }
        } else {
            self
        }
    }
}
