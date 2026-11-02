/**
 * File: FileTreeContents.swift
 * ----------------------------
 * Layer: UI
 * Description: The file list's rows as one flat list, kept up to date row by row, so tapping a folder or
 *              a folder's listing arriving does not rebuild the whole tree.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import Observation
import SwiftUI
import GraphiteCore

/// A file or folder of the tree, at its depth in the vault.
struct FileTreeRow: Identifiable, Equatable {
    let entry: VaultEntry
    let depth: Int
    var id: String { entry.path.rawValue }
}

/// The tree's rows as one flat list, an expanded folder's contents following it, kept up to date
/// row by row: folding a folder in a root of 24,712 files rebuilds nothing but its own rows.
struct FlattenedFileTree {
    private(set) var rows: [FileTreeRow] = []
    /// Rows made so far, which a test counts.
    private(set) var rowsBuiltCount = 0
    private(set) var rootEntries: [VaultEntry] = []
    private(set) var expandedFolders: Set<VaultPath> = []
    /// Each folder's contents as last listed, kept so a folder opened again draws at once.
    private(set) var childrenByFolder: [VaultPath: [VaultEntry]] = [:]

    /// The root's listing changed, so every row's place may have.
    mutating func setRootEntries(_ entries: [VaultEntry]) {
        guard entries != rootEntries else { return }
        rootEntries = entries
        var rebuiltRows: [FileTreeRow] = []
        rebuiltRows.reserveCapacity(entries.count)
        appendRows(for: entries, depth: 0, to: &rebuiltRows)
        rows = rebuiltRows
    }

    /// Folders opened and closed: only their own rows are added or removed.
    mutating func setExpandedFolders(_ folders: Set<VaultPath>) {
        guard folders != expandedFolders else { return }
        let foldedFolders = expandedFolders.subtracting(folders), openedFolders = folders.subtracting(expandedFolders)
        expandedFolders = folders
        for folder in foldedFolders { removeRows(inside: folder) }
        for folder in openedFolders { insertRows(inside: folder) }
    }

    /// A folder's listing arrived. An unchanged one touches nothing.
    mutating func setChildren(_ children: [VaultEntry], of folder: VaultPath) {
        guard children != childrenByFolder[folder] else { return }
        removeRows(inside: folder)
        childrenByFolder[folder] = children
        insertRows(inside: folder)
    }

    /// The position of a folder's row when its contents show: every folder above it is expanded.
    private func rowPosition(of folder: VaultPath) -> Int? {
        guard expandedFolders.contains(folder) else { return nil }
        return rows.firstIndex { row in row.entry.path == folder }
    }

    private mutating func removeRows(inside folder: VaultPath) {
        guard let position = rows.firstIndex(where: { row in row.entry.path == folder }) else { return }
        let depth = rows[position].depth
        let firstRowInside = position + 1
        var endOfRowsInside = firstRowInside
        while endOfRowsInside < rows.count, rows[endOfRowsInside].depth > depth { endOfRowsInside += 1 }
        if endOfRowsInside > firstRowInside { rows.removeSubrange(firstRowInside..<endOfRowsInside) }
    }

    private mutating func insertRows(inside folder: VaultPath) {
        guard let position = rowPosition(of: folder), let children = childrenByFolder[folder] else { return }
        // Rows may already follow it, as when a folder inside opened at the same moment.
        removeRows(inside: folder)
        var insertedRows: [FileTreeRow] = []
        appendRows(for: children, depth: rows[position].depth + 1, to: &insertedRows)
        rows.insert(contentsOf: insertedRows, at: position + 1)
    }

    private mutating func appendRows(for entries: [VaultEntry], depth: Int, to builtRows: inout [FileTreeRow]) {
        rowsBuiltCount += entries.count
        for entry in entries {
            builtRows.append(FileTreeRow(entry: entry, depth: depth))
            guard entry.isDirectory, expandedFolders.contains(entry.path), let children = childrenByFolder[entry.path] else { continue }
            appendRows(for: children, depth: depth + 1, to: &builtRows)
        }
    }
}

/// What the file tree's rows share: the flat list of rows and the folder a drag is over. A
/// folder's listing and a tap on a folder reach the tree only through `rows`, and only when it
/// changes, so one folder's listing does not invalidate the whole tree.
@MainActor @Observable final class FileTreeContents {
    private(set) var rows: [FileTreeRow] = []
    var dropTargetFolder: VaultPath?
    @ObservationIgnored private var tree = FlattenedFileTree()

    /// Rows made so far, which a test counts.
    var rowsBuiltCount: Int { tree.rowsBuiltCount }

    func setChildren(_ children: [VaultEntry], of folder: VaultPath) {
        tree.setChildren(children, of: folder)
        publishRows(animated: true)
    }

    /// Follows the workspace's root listing and open folders for as long as the tree shows.
    /// A view reading them in its body would run for every folder tapped.
    func follow(rootEntries: @escaping @MainActor () -> [VaultEntry], expandedFolders: @escaping @MainActor () -> Set<VaultPath>) async {
        while !Task.isCancelled {
            await withCheckedContinuation { (changed: CheckedContinuation<Void, Never>) in
                let (listedEntries, openFolders) = withObservationTracking {
                    (rootEntries(), expandedFolders())
                } onChange: {
                    changed.resume()
                }
                apply(rootEntries: listedEntries, expandedFolders: openFolders)
            }
        }
    }

    func apply(rootEntries: [VaultEntry], expandedFolders: Set<VaultPath>) {
        let rootChanged = rootEntries != tree.rootEntries
        // Contents of the vault left go with it: a same-named folder here lists its own.
        if rootEntries.isEmpty, rootChanged { tree = FlattenedFileTree() }
        tree.setExpandedFolders(expandedFolders)
        tree.setRootEntries(rootEntries)
        publishRows(animated: !rootChanged)
    }

    private func publishRows(animated: Bool) {
        guard tree.rows != rows else { return }
        if animated {
            withAnimation(GraphiteMotion.animation(.snappy)) { rows = tree.rows }
        } else {
            rows = tree.rows
        }
    }
}
