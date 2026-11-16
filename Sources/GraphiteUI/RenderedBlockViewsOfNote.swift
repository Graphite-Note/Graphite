/**
 * File: RenderedBlockViewsOfNote.swift
 * ------------------------------------
 * Layer: UI
 * Description: What a note's Live Preview block views hold for the note: their drafts and the table cell whose commands
 *              the command palette and the Edit menu offer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import Observation

/// What a note's rendered blocks' views hold for the note, kept by its `MarkdownSession`.
@MainActor
@Observable
final class RenderedBlockViewsOfNote {
    /// Writes what rendered blocks' views hold back into the text, by the view that holds it:
    /// a table cell's draft waits for typing to pause, and a save right after the last key
    /// (quitting, closing the tab, leaving the app) must not go without those characters.
    @ObservationIgnored var draftCommits: [ObjectIdentifier: () -> Void] = [:]

    /// The Live Preview table cell whose commands the command palette and the Edit menu offer
    /// (`TableCellCommandTarget`); nil once the note's own text takes the keyboard.
    private(set) var tableCellCommandTarget: TableCellCommandTarget?

    /// A table's cell began editing. Only another table's editor is a change, which the Edit menu follows.
    func takeTableCellCommands(_ target: TableCellCommandTarget) {
        guard tableCellCommandTarget?.editor !== target.editor else { return }
        tableCellCommandTarget = target
    }

    /// The note's text took the keyboard: the table commands go until a cell is edited again.
    func releaseTableCellCommands() {
        guard tableCellCommandTarget != nil else { return }
        tableCellCommandTarget = nil
    }
}
