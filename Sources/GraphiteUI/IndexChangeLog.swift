/**
 * File: IndexChangeLog.swift
 * --------------------------
 * Layer: UI
 * Description: Which files each change of the index touched, so a panel that shows none of what changed
 *              does not read the vault again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// One change of the index, named by the files it touched.
struct IndexChange: Equatable, Sendable {
    /// The `indexVersion` the change brought.
    let version: Int
    /// The files refreshed; nil when the change is not known file by file, as after a scan or a move.
    let paths: Set<VaultPath>?
    /// Whether a file came or went, or its links, tags, aliases or properties differ.
    let changedStructure: Bool
    /// Whether a file came or went, or its name or aliases differ.
    let changedNames: Bool
}

/// The latest changes of the index, so each panel can ask for the newest one that concerns it
/// (`WorkspaceModel.recordIndexChange`).
struct IndexChangeLog: Equatable, Sendable {
    /// Older changes drop out. Each panel asks for the newest version that concerns it, which a
    /// dropped change can only lower, so the panel reads again, as it did on every change before.
    static let capacity = 64
    private(set) var changes: [IndexChange] = []

    mutating func record(_ change: IndexChange) {
        changes.append(change)
        if changes.count > Self.capacity { changes.removeFirst(changes.count - Self.capacity) }
    }

    /// The newest version after which the backlinks of `note` may differ, or 0 when none did. Its own
    /// saves count only when its name or aliases changed, since what links to a note does not
    /// change as the note is typed. A change of any other file counts, as it may add or remove a
    /// link or a mention.
    func newestVersionAffectingBacklinks(of note: VaultPath) -> Int {
        changes.last { change in
            guard let paths = change.paths else { return true }
            return change.changedNames || !paths.isSubset(of: [note])
        }?.version ?? 0
    }
}
