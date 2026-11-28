/**
 * File: GuideVaultCopy.swift
 * --------------------------
 * Layer: UI
 * Description: The reader's own copy of the Graphite Guide vault, made in Graphite's Documents folder from the pack.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
 */

import Foundation
import GraphiteCore

/// The Graphite Guide vault the reader opens is a copy of the downloaded pack (`GuideVaultPack`) in Graphite's own
/// Documents folder (On My iPad › Graphite in Files), so they can change, tick and draw in it freely while the pack stays
/// as it came. The copy is made the first time, then the same copy opens; a fresh copy, when asked for, goes beside the
/// old one under a free name ("Graphite Guide 2"), so nothing the reader wrote is ever deleted. The pack's revision
/// and file names the copy was made from are kept in the device's settings, not in the vault, so a newer pack can be
/// brought into it (`GuideVaultCopyUpdate`).
struct GuideVaultCopy {
    static let folderName = "Graphite Guide"
    /// The name of the folder of the copy the Guide opens, in Graphite's Documents folder.
    static let copyNameKey = "GraphiteGuideVaultCopyName"
    /// The revision of the pack the copy was made from or last brought up to.
    static let copyRevisionKey = "GraphiteGuideVaultCopyRevision"
    /// The names of that pack's files, so a note the reader deleted is not brought back.
    static let copyFileNamesKey = "GraphiteGuideVaultCopyFileNames"
    /// The pack's own marker (`AddOnPackStore`), which is not part of the vault.
    static let packMarkerFileName = ".graphite-installed"

    let documentsFolder: URL
    let defaults: UserDefaults

    /// The folder name of the copy made before, or nil when there is none or the reader removed it.
    func existingCopyName() -> String? {
        guard let name = defaults.string(forKey: Self.copyNameKey) else { return nil }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: documentsFolder.appendingPathComponent(name, isDirectory: true).path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue ? name : nil
    }

    /// The revision of the pack the copy came from, or nil for a copy made before revisions were recorded.
    func recordedRevision() -> String? { defaults.string(forKey: Self.copyRevisionKey) }

    /// The file names of the pack the copy came from, or nil for a copy made before they were recorded.
    func recordedFileNames() -> Set<String>? { defaults.stringArray(forKey: Self.copyFileNamesKey).map(Set.init) }

    /// Remembers that the copy holds `pack` now, after it was made or brought up to it.
    func record(_ pack: AddOnPack) {
        defaults.set(pack.revision, forKey: Self.copyRevisionKey)
        defaults.set(pack.files.map(\.name), forKey: Self.copyFileNamesKey)
    }

    /// Copies the pack's folder into the Documents folder under the first free name, without the pack's marker, and
    /// remembers it as the copy to open, made from `pack`. Returns the copy's folder name.
    func makeCopy(of pack: AddOnPack, from packFolder: URL) throws -> String {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: documentsFolder, withIntermediateDirectories: true)
        let name = freeName()
        let destination = documentsFolder.appendingPathComponent(name, isDirectory: true)
        try fileManager.copyItem(at: packFolder, to: destination)
        let marker = destination.appendingPathComponent(Self.packMarkerFileName)
        if fileManager.fileExists(atPath: marker.path) { try fileManager.removeItem(at: marker) }
        defaults.set(name, forKey: Self.copyNameKey)
        record(pack)
        return name
    }

    /// "Graphite Guide", or "Graphite Guide 2", 3… when that name is taken by any file or folder.
    private func freeName() -> String {
        var number = 1
        var name = Self.folderName
        while FileManager.default.fileExists(atPath: documentsFolder.appendingPathComponent(name).path) {
            number += 1
            name = "\(Self.folderName) \(number)"
        }
        return name
    }
}
