/**
 * File: LivePreviewCalloutBody.swift
 * ----------------------------------
 * Layer: UI
 * Description: A Live Preview callout drawn as a box, and the reading-view blocks of its body or of an embedded note.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.1
 * Date: 13/11/2026
 */

import SwiftUI
import GraphiteCore

/// A callout drawn as a box, as in Obsidian's Live Preview. Its title folds it; a tap on
/// its body shows the source.
struct LivePreviewCalloutView: View {
    let type: String
    let title: String
    let folding: CalloutFolding
    let bodyBlocks: [NotePreviewBlock]
    /// The body's blocks with where their lines are in the callout's source, and what the note
    /// around the callout says about them; nil where the callout is not part of the note.
    var bodyLocated: [NotePreviewDocument.LocatedBlock]? = nil
    var noteReading: RenderedBlockNoteReading? = nil
    /// Which of the callouts with this type and title it is, which its fold key holds.
    var foldOccurrence = 0
    let environment: LivePreviewEnvironment
    let revealSource: () -> Void
    var readingSection: LivePreviewReadingSection? = nil
    /// How the body's tables are edited in place; nil leaves them drawn as in the reading view.
    var tableEditing: LivePreviewCalloutTableEditing? = nil
    @Environment(\.readingActiveSourceRange) private var readingActiveSourceRange
    @Environment(\.readingFollowsSource) private var readingFollowsSource

    var body: some View {
        CalloutView(type: type, title: LivePreviewText.prepared(title, colorsEnabled: environment.colorsEnabled, paletteHexByName: environment.paletteHexByName),
                    folding: folding, root: environment.root, textSize: environment.textSize, navigate: environment.follow,
                    sourceTokens: readingSection?.titleTokens,
                    automaticallyExpandsForReading: readingFollowsSource && (readingActiveSourceRange.map { range in
                        readingSection?.tokens.contains { token in NSIntersectionRange(token.sourceRange, range).length > 0 } ?? false
                    } ?? false), foldKeyTitle: title, foldOccurrence: foldOccurrence) {
            // A tap on a table's cell edits it (the table's own tap), elsewhere it shows the source.
            LivePreviewBlockStack(blocks: bodyBlocks, located: bodyLocated, noteReading: noteReading, environment: environment, allowsNoteEmbeds: true,
                                  revealSource: revealSource, readingSection: readingSection, tableEditing: tableEditing)
                .contentShape(Rectangle())
                .onTapGesture(perform: revealSource)
        }
        .environment(\.calloutFoldNote, environment.calloutFoldNote)
    }
}

/// Reading-view blocks inside a Live Preview view: a callout's body or an embedded note.
struct LivePreviewBlockStack: View {
    let blocks: [NotePreviewBlock]
    /// `blocks` with where their lines are in the source of the callout they are the body of,
    /// when that callout is part of the note.
    var located: [NotePreviewDocument.LocatedBlock]? = nil
    var noteReading: RenderedBlockNoteReading? = nil
    let environment: LivePreviewEnvironment
    /// Embedded notes are shown one level deep, so notes that embed each other end.
    let allowsNoteEmbeds: Bool
    let revealSource: () -> Void
    var readingSection: LivePreviewReadingSection? = nil
    /// How the tables of a callout's body are edited in place, for every depth of its callouts.
    var tableEditing: LivePreviewCalloutTableEditing? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { blockIndex, block in
                view(for: block, at: blockIndex, readingSection: childReadingSection(at: blockIndex))
            }
        }
    }

    /// Type-erased, because a callout can contain callouts.
    private func childReadingSection(at index: Int) -> LivePreviewReadingSection? {
        guard let readingSection, readingSection.block.body.indices.contains(index) else { return nil }
        let body = readingSection.block.body
        let end = index + 1 < body.count ? body[index + 1].startOffset : readingSection.endOffset
        return LivePreviewReadingSection(snapshot: readingSection.snapshot, block: body[index], endOffset: end)
    }

    /// Where the Markdown of the body block at `index` is in the note, when the callout is part of it.
    private func place(ofBlockAt index: Int) -> RenderedBlockPlace? {
        guard let noteReading, let located, located.indices.contains(index) else { return nil }
        return RenderedBlockPlace(reading: noteReading, lineOffsets: located[index].lineStartOffsets)
    }

    /// Which of the callouts with its type and title the callout body block at `index` is.
    private func foldOccurrence(ofCalloutAt index: Int) -> Int {
        guard let noteReading, let located, located.indices.contains(index) else { return 0 }
        return noteReading.calloutOccurrence(atSourceOffset: located[index].startOffset)
    }

    /// The Markdown run at `index` cut at its tables, each table edited in place; nil when its
    /// tables are not edited here or it holds none.
    private func calloutRun(_ markdown: String, at index: Int, readingSection: LivePreviewReadingSection?) -> LivePreviewCalloutRun? {
        guard let tableEditing, let located, located.indices.contains(index) else { return nil }
        let lines = markdown.components(separatedBy: "\n")
        guard lines.count == located[index].lineStartOffsets.count else { return nil }
        let pieces = CalloutTables.pieces(ofRunLines: lines)
        guard pieces.contains(where: \.isTable) else { return nil }
        return LivePreviewCalloutRun(lines: lines, located: located[index], pieces: pieces, noteReading: noteReading, environment: environment,
                                     tableEditing: tableEditing, sourceTokens: readingSection?.tokens)
    }

    private func view(for block: NotePreviewBlock, at index: Int, readingSection: LivePreviewReadingSection?) -> AnyView {
        switch block {
        case .markdown(let markdown):
            calloutRun(markdown, at: index, readingSection: readingSection).map { run in AnyView(run) }
                ?? AnyView(RenderedMarkdownBlock(markdown: markdown, environment: environment, sourceTokens: readingSection?.tokens, place: place(ofBlockAt: index)))
        case .heading(let level, let text, _):
            AnyView(RenderedMarkdownBlock(markdown: String(repeating: "#", count: level) + " " + text, environment: environment, sourceTokens: readingSection?.tokens))
        case .callout(let type, let title, let folding, let bodyBlocks):
            AnyView(LivePreviewCalloutView(type: type, title: title, folding: folding, bodyBlocks: bodyBlocks,
                                           bodyLocated: located?.indices.contains(index) == true ? located?[index].body : nil, noteReading: noteReading,
                                           foldOccurrence: foldOccurrence(ofCalloutAt: index),
                                           environment: environment, revealSource: revealSource, readingSection: readingSection, tableEditing: tableEditing))
        case .embed(let embed):
            AnyView(LivePreviewEmbedView(embed: embed, environment: environment, allowsNoteEmbeds: allowsNoteEmbeds, revealSource: revealSource))
        case .baseDefinition(let yaml):
            AnyView(BaseCodeBlockView(yaml: yaml, context: environment.baseContext))
        case .displayMath(let markdown):
            AnyView(RenderedMarkdownBlock(markdown: markdown, environment: environment, sourceTokens: readingSection?.tokens).frame(maxWidth: .infinity))
        case .pluginCodeBlock(let language, let source):
            // Blocks here are split without plugin languages, so this does not occur; shown as code.
            AnyView(RenderedMarkdownBlock(markdown: "```" + language + "\n" + source + "\n```", environment: environment))
        case .mermaidDiagram(let source):
            AnyView(LivePreviewDiagramView(source: source, environment: environment, revealSource: revealSource))
        case .webFrame(let frame): AnyView(LivePreviewWebFrameView(frame: frame, revealSource: revealSource))
        }
    }
}
