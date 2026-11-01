/**
 * File: VaultStoreListing.swift
 * -----------------------------
 * Layer: Core
 * Description: Listing the vault's folders off the store's actor, and what can be asked about them
 *              without a listing: one item, a folder's date, the settings files' dates.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import Synchronization

/// A settings file's date and size, as `VaultStore.settingsFilesRevision` compares them.
public struct SettingsFileStamp: Equatable, Sendable {
    public let modified: Date?
    public let size: Int?
}

/// Listing the vault's folders, and what can be asked about them without listing them.
extension VaultStore {
    /// How many folders have been listed through `children(of:sortedBy:)`, so a test can count
    /// that a change makes no more listings than it must.
    public nonisolated var directoryListingCount: Int { directoryListings.withLock { count in count } }

    /// Lists a folder, sorted. Not isolated to the actor, and it runs off the caller's: a root of
    /// 24,712 files takes one metadata read each and about 360,000 name comparisons, and reads
    /// and saves on this actor must not wait for that.
    public nonisolated func children(of directory: VaultPath, sortedBy sortOrder: FileSortOrder = .alphabetical) async throws -> [VaultEntry] {
        directoryListings.withLock { count in count += 1 }
        return try listedChildren(of: directory, sortedBy: sortOrder)
    }

    nonisolated func listedChildren(of directory: VaultPath, sortedBy sortOrder: FileSortOrder = .alphabetical) throws -> [VaultEntry] {
        let url = try directory.url(in: root)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]).compactMap { child -> VaultEntry? in
            // One child that vanished since the listing, or that has a name no vault path
            // can hold, is left out instead of failing the whole folder.
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                  let childPath = try? directory.appending(child.lastPathComponent) else { return nil }
            return VaultEntry(path: childPath, isDirectory: values.isDirectory == true, size: values.fileSize ?? 0,
                              modified: values.contentModificationDate ?? .distantPast, created: values.creationDate)
        }
        return sortOrder.sorted(entries)
    }

    /// What a folder's listing shows for each of these items, nil for one it would not show:
    /// gone, hidden or a symbolic link. One metadata read per item and no listing.
    public nonisolated func entries(at paths: Set<VaultPath>) async -> [VaultPath: VaultEntry?] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        var entries: [VaultPath: VaultEntry?] = [:]
        for path in paths {
            // Not through `url(in:)`, which follows a link to what it leads to: a listing leaves
            // the link itself out.
            guard !path.isHidden, (try? path.url(in: root)) != nil, let values = try? root.appendingPathComponent(path.rawValue).resourceValues(forKeys: keys),
                  values.isSymbolicLink != true else {
                entries.updateValue(nil, forKey: path)
                continue
            }
            entries.updateValue(VaultEntry(path: path, isDirectory: values.isDirectory == true, size: values.fileSize ?? 0,
                                           modified: values.contentModificationDate ?? .distantPast, created: values.creationDate), forKey: path)
        }
        return entries
    }

    /// Refuses a folder that cannot be listed, as one removed or no longer permitted, without
    /// reading what is in it: a vault switch asks this before it closes the open vault.
    public nonisolated func checkFolderCanBeListed() async throws {
        guard let directory = opendir(root.path) else {
            let openingFailure = errno
            switch openingFailure {
            case EACCES, EPERM: throw CocoaError(.fileReadNoPermission, userInfo: [NSURLErrorKey: root])
            case ENOENT, ENOTDIR: throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: root])
            default: throw POSIXError(POSIXErrorCode(rawValue: openingFailure) ?? .EIO)
            }
        }
        closedir(directory)
    }

    /// When a folder's list of names last changed: a file added, removed or renamed in it moves
    /// this date, a file edited in place does not. Nil when the folder cannot be asked.
    public nonisolated func listingDate(of folder: VaultPath) async -> Date? {
        guard let location = try? folder.url(in: root) else { return nil }
        return try? location.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The date and size of each settings file a window reads when it comes back to the front,
    /// so that it reads them again only when one moved. Asked of the file system alone: a file
    /// iCloud has evicted is not downloaded. `workspace.json`, which Obsidian rewrites all the
    /// time, is not among them.
    public nonisolated func settingsFilesRevision() async -> [String: SettingsFileStamp] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var revision: [String: SettingsFileStamp] = [:]
        let settingsFilePaths = [Self.applicationConfigurationPath, ObsidianAppearance.configurationPath, BookmarkList.configurationPath,
                                 DailyNoteSettings.configurationPath, HotkeyFile.configurationPath, TemplateSettings.configurationPath]
        for settingsFilePath in settingsFilePaths {
            guard let values = try? root.appendingPathComponent(settingsFilePath).resourceValues(forKeys: keys) else { continue }
            revision[settingsFilePath] = SettingsFileStamp(modified: values.contentModificationDate, size: values.fileSize)
        }
        return revision
    }
}
