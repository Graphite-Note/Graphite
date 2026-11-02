/**
 * File: VaultFolderListing.swift
 * ------------------------------
 * Layer: UI
 * Description: Every visible folder of a vault, found without reading any file, and stopped when its task is.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

enum VaultFolderListing {
    /// Every visible folder under `root`, in the order Finder sorts names. Stops with `CancellationError` once
    /// the task running it is cancelled: a walk of a big vault on iCloud-backed storage takes seconds, and one
    /// nobody waits for any longer must not go on.
    nonisolated static func folders(in root: URL) throws -> [VaultPath] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options) else { return [] }
        var folders: [VaultPath] = []
        while let location = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard let values = try? location.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
            if values.isDirectory == true, let folder = try? VaultPath(location.relativePath) { folders.append(folder) }
        }
        return folders.sorted { leftFolder, rightFolder in leftFolder.rawValue.localizedStandardCompare(rightFolder.rawValue) == .orderedAscending }
    }
}
