/**
 * File: WorkspaceIndexChanges.swift
 * ---------------------------------
 * Layer: UI
 * Description: How the workspace tells its panels that the index changed, and which files and facts the
 *              change touched.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// The index took in a change. `indexVersion` moves for every one, for the panels that show
    /// any of a note's text; the log and `structureVersion` let the others tell whether their
    /// own inputs changed.
    /// - Parameters:
    ///   - paths: The files refreshed; nil when the change is not known file by file (a scan,
    ///     a move), which counts as changing everything.
    ///   - changedStructure: Whether those files' existence, links, tags, aliases or properties differ.
    ///   - changedNames: Whether those files' existence, names or aliases differ.
    func recordIndexChange(paths: Set<VaultPath>?, changedStructure: Bool = true, changedNames: Bool = true) {
        let version = indexVersion + 1
        indexChangeLog.record(IndexChange(version: version, paths: paths, changedStructure: changedStructure, changedNames: changedNames))
        if paths == nil || changedStructure { structureVersion = version }
        indexVersion = version
    }
}
