/**
 * File: FileTreeFilter.swift
 * --------------------------
 * Layer: UI
 * Description: The Files panel's filter: the text typed, the folders and files it keeps, which of their folders show
 *              expanded, and the folder chosen while filtering that stays in sight once the filter is cleared.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import Observation
import GraphiteCore

/// The file tree's filter by name, shared by the iPad's and iPhone's list (`FileTreeRows`) and the Mac's outline
/// (`MacFileTree`). It reads only the vault's names (`FileTreeNameIndex`), loaded while the field is in use and let go
/// when it is empty and left, so a filter not in use costs nothing. Its expansion is its own: folders opened and closed
/// while filtering leave the tree's own expanded folders as they were, which the tree shows again once the filter is
/// cleared.
@MainActor @Observable final class FileTreeFilter {
    /// What the field holds.
    var text = "" {
        didSet { if text != oldValue { textChanged(from: oldValue) } }
    }
    /// The folders and files the text matches; nil while not filtering, or while the names are being read.
    private(set) var result: FileTreeNameFilterResult?
    /// The folders shown expanded while filtering: those above a match, and those the person opened.
    private(set) var expandedFolders: Set<VaultPath> = []
    /// Increases when a command asks for the field (`requestFocus`).
    private(set) var focusRequest = 0
    /// Whether the field has the keyboard, which is when the names are worth reading ahead of the first letter.
    var isFieldFocused = false
    @ObservationIgnored private(set) var nameIndex: FileTreeNameIndex?
    @ObservationIgnored private var hasPendingFocus = false
    @ObservationIgnored private var foldersOpenedByPerson: Set<VaultPath> = []
    @ObservationIgnored private var foldersClosedByPerson: Set<VaultPath> = []
    /// The folder last opened while filtering, which stays expanded and in sight once the filter is cleared.
    @ObservationIgnored private var chosenFolder: VaultPath?
    @ObservationIgnored private var rowsMemo: (result: FileTreeNameFilterResult?, expandedFolders: Set<VaultPath>, rows: [FileTreeRow])?

    /// Whether the text asks for a filter: something other than spaces.
    var isFiltering: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Whether the names should be held: while filtering or while the field has the keyboard.
    var needsNameIndex: Bool { isFiltering || isFieldFocused }

    /// The rows the list shows while filtering, made once per result and expansion.
    var rows: [FileTreeRow] {
        if let rowsMemo, rowsMemo.result == result, rowsMemo.expandedFolders == expandedFolders { return rowsMemo.rows }
        let rows = result?.rows(expandedFolders: expandedFolders) ?? []
        rowsMemo = (result, expandedFolders, rows)
        return rows
    }

    /// The vault's names arrived, or were let go (nil); the filter shown is matched against them.
    func setNameIndex(_ nameIndex: FileTreeNameIndex?) {
        self.nameIndex = nameIndex
        applyResult(nameIndex?.filter(text))
    }

    /// Reads the vault's names while the filter needs them, and lets them go otherwise. The index's file table and
    /// what the workspace has listed are all it reads: no file is opened. The names are put in order off the main
    /// thread; a newer load (the vault or its files changed) cancels this one, whose names are then not used.
    func loadNameIndex(fileEntries: @escaping @Sendable () async throws -> [VaultEntry], listedEntries: [VaultEntry],
                       sortOrder: FileSortOrder) async {
        guard needsNameIndex else { return setNameIndex(nil) }
        let indexedEntries = (try? await fileEntries()) ?? [] // An unreadable index leaves the names listed, which still filter.
        let entries = indexedEntries + listedEntries
        let nameIndex = await Task.detached(priority: .userInitiated) { FileTreeNameIndex(entries: entries, sortOrder: sortOrder) }.value
        guard !Task.isCancelled else { return }
        setNameIndex(nameIndex)
    }

    /// The person opened or closed a folder while filtering. Opening one chooses it.
    func setExpanded(_ folder: VaultPath, _ expands: Bool) {
        if expands {
            foldersOpenedByPerson.insert(folder)
            foldersClosedByPerson.remove(folder)
            chosenFolder = folder
        } else {
            foldersClosedByPerson.insert(folder)
            foldersOpenedByPerson.remove(folder)
            if chosenFolder == folder { chosenFolder = nil }
        }
        updateExpandedFolders()
    }

    /// Asks the field for the keyboard, now or as soon as it shows.
    func requestFocus() {
        hasPendingFocus = true
        focusRequest += 1
    }

    /// Whether a request for the keyboard waits; the field takes it once.
    func takePendingFocus() -> Bool {
        defer { hasPendingFocus = false }
        return hasPendingFocus
    }

    /// Empties the field: the tree shows as it was before filtering.
    func clear() {
        text = ""
    }

    /// The folder chosen while filtering, handed over once after the filter is cleared.
    func takeChosenFolder() -> VaultPath? {
        defer { chosenFolder = nil }
        return isFiltering ? nil : chosenFolder
    }

    private func textChanged(from previousText: String) {
        let wasFiltering = !previousText.trimmingCharacters(in: .whitespaces).isEmpty
        if !wasFiltering && isFiltering { chosenFolder = nil }
        if !isFiltering {
            foldersOpenedByPerson = []
            foldersClosedByPerson = []
        }
        applyResult(isFiltering ? nameIndex?.filter(text) : nil)
    }

    private func applyResult(_ newResult: FileTreeNameFilterResult?) {
        if newResult != result { result = newResult }
        updateExpandedFolders()
    }

    private func updateExpandedFolders() {
        let folders = (result?.foldersAboveMatches ?? []).union(foldersOpenedByPerson).subtracting(foldersClosedByPerson)
        if folders != expandedFolders { expandedFolders = folders }
    }
}
