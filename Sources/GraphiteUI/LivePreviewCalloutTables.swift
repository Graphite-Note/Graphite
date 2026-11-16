/**
 * File: LivePreviewCalloutTables.swift
 * ------------------------------------
 * Layer: UI
 * Description: Editing the tables of a Live Preview callout's body in place: an editor per table, kept by the callout's
 *              view, and each edit run on the table's lines with their quote markers kept.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import SwiftUI
import GraphiteCore

/// The table editors of one callout's view, one per table of its body in the order they are
/// drawn (`CalloutTables.tables(in:)`). The callout's view keeps it, so an editor and the cell it
/// edits stay while the callout is drawn again after each of its edits. A reference, so what it
/// remembers during a view update changes no view state.
@MainActor
final class LivePreviewCalloutTableEditors {
    private var editors: [LivePreviewTableEditor] = []
    /// The callout's lines its tables' sources were last read from, and those sources.
    private var tableSourcesMemo: (calloutSource: String, tableSources: [Int: String?])?

    /// The editor of the table at `tableIndex`, made the first time it is asked for.
    func editor(at tableIndex: Int) -> LivePreviewTableEditor {
        while editors.count <= tableIndex { editors.append(LivePreviewTableEditor()) }
        return editors[tableIndex]
    }

    /// The table's lines without their quote markers, read once per change of the callout.
    func tableSource(at tableIndex: Int, inCallout calloutSource: String) -> String? {
        if tableSourcesMemo?.calloutSource != calloutSource { tableSourcesMemo = (calloutSource, [:]) }
        if let known = tableSourcesMemo?.tableSources[tableIndex] { return known }
        let source = CalloutTables.tableSource(at: tableIndex, inCallout: calloutSource)
        tableSourcesMemo?.tableSources[tableIndex] = source
        return source
    }

    /// What the table at `tableIndex` edits the note with: the callout's own editing, each of the
    /// table's edits run on its lines with their quote markers taken off and put back.
    static func sourceEditing(forTableAt tableIndex: Int, of calloutEditing: RenderedBlockSourceEditing) -> RenderedBlockSourceEditing {
        RenderedBlockSourceEditing(replaceSource: { editor, transform in
            calloutEditing.replaceSource(editor) { calloutSource in
                CalloutTables.editingTable(at: tableIndex, inCallout: calloutSource, using: transform)
            }
        }, setIsEditingInView: calloutEditing.setIsEditingInView, setDraftCommit: calloutEditing.setDraftCommit,
           offerCellCommands: calloutEditing.offerCellCommands)
    }

    /// The cell menu of the table under `point`, in the callout view's coordinates, or of the
    /// table whose cell is edited; nothing elsewhere in the callout, whose menu is then Edit Source.
    func menuItems(at point: CGPoint) -> [RenderedBlockMenuItem] {
        let table = editors.first { editor in editor.isOnTable(point) } ?? editors.first { editor in editor.editingCell != nil }
        return table?.menuItems(at: point) ?? []
    }
}

/// What a callout's body needs to edit its tables: given only to a callout of the note in Live
/// Preview, never to the reading view or an embedded note.
@MainActor
struct LivePreviewCalloutTableEditing {
    /// The callout's tables, found in the blocks its body is drawn from.
    let tables: [CalloutTable]
    /// The callout's lines as the note has them, which its tables' sources are read from.
    let calloutSource: String
    let sourceEditing: RenderedBlockSourceEditing
    let editors: LivePreviewCalloutTableEditors
    let textSize: Double

    /// The editor of the table whose first line starts at `lineStartOffset` in the callout,
    /// given the table's source; nil when no table of the callout starts there.
    func editor(forTableStartingAt lineStartOffset: Int) -> LivePreviewTableEditor? {
        guard let tableIndex = tables.firstIndex(where: { table in table.lineStartOffsets.first == lineStartOffset }),
              let tableSource = editors.tableSource(at: tableIndex, inCallout: calloutSource) else { return nil }
        let editor = editors.editor(at: tableIndex)
        editor.update(source: tableSource, textSize: textSize,
                      sourceEditing: LivePreviewCalloutTableEditors.sourceEditing(forTableAt: tableIndex, of: sourceEditing))
        return editor
    }
}

/// A Markdown run of a Live Preview callout's body with tables: each table drawn as a block of
/// its own, which its editor is given to, the text between drawn as before.
struct LivePreviewCalloutRun: View {
    let lines: [String]
    let located: NotePreviewDocument.LocatedBlock
    let pieces: [CalloutTables.RunPiece]
    let noteReading: RenderedBlockNoteReading?
    let environment: LivePreviewEnvironment
    let tableEditing: LivePreviewCalloutTableEditing
    var sourceTokens: [ReadAloudSourceToken]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pieces, id: \.lineRange.lowerBound) { piece in
                pieceView(piece)
            }
        }
    }

    @ViewBuilder private func pieceView(_ piece: CalloutTables.RunPiece) -> some View {
        // A table in a list item is drawn without the item's indentation, moved in by it instead,
        // so four columns or more do not make it indented code.
        let indentationLength = piece.indentationLength
        let markdown = lines[piece.lineRange].map { line in String((line as NSString).substring(from: indentationLength)) }.joined(separator: "\n")
        let lineOffsets = located.lineStartOffsets[piece.lineRange].map { offset in offset + indentationLength }
        let place = noteReading.map { reading in RenderedBlockPlace(reading: reading, lineOffsets: lineOffsets) }
        let block = RenderedMarkdownBlock(markdown: markdown, environment: environment, sourceTokens: tokens(of: piece), place: place)
            .padding(.leading, indentationLength == 0 ? 0 : Self.listItemIndentation(textSize: environment.textSize))
        if piece.isTable, let startOffset = lineOffsets.first, let editor = tableEditing.editor(forTableStartingAt: startOffset) {
            block.environment(\.livePreviewTableEditor, editor)
        } else {
            block
        }
    }

    /// How far a table in a list item is moved in: about where the item's text starts after its marker.
    private static func listItemIndentation(textSize: Double) -> CGFloat { CGFloat(textSize * 1.5) }

    /// The run's Read Aloud tokens in the piece's lines.
    private func tokens(of piece: CalloutTables.RunPiece) -> [ReadAloudSourceToken]? {
        let offsets = located.lineStartOffsets
        guard let sourceTokens, offsets.indices.contains(piece.lineRange.lowerBound) else { return sourceTokens }
        let start = offsets[piece.lineRange.lowerBound]
        let end = offsets.indices.contains(piece.lineRange.upperBound) ? offsets[piece.lineRange.upperBound] : .max
        return sourceTokens.filter { token in token.sourceRange.location >= start && token.sourceRange.location < end }
    }
}
