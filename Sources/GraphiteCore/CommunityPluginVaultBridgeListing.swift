/**
 * File: CommunityPluginVaultBridgeListing.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: The vault's file list for plugins, answered page by page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// `vault.list`: the vault's files for plugins, page by page. An answer crosses to the plugins'
/// page on the main thread, so none is large.
extension CommunityPluginVaultBridge {
    /// The most entries one answer holds; the rest follow, asked for by `nextPage`.
    public static let maximumListedEntriesPerPage = 2_000

    func listingAnswer(for entries: ArraySlice<ListedEntry>, isTruncated: Bool) async -> [String: Any] {
        let page = entries.prefix(Self.maximumListedEntriesPerPage).map { entry in
            var dictionary = Self.statDictionary(isFolder: entry.isFolder, size: entry.size, modified: entry.modified, created: entry.created)
            dictionary["path"] = entry.path.rawValue
            return dictionary
        }
        guard entries.count > Self.maximumListedEntriesPerPage else { return ["entries": page, "isTruncated": isTruncated] }
        let nextPage = await openListings.keep(entries.dropFirst(Self.maximumListedEntriesPerPage))
        return ["entries": page, "isTruncated": isTruncated, "nextPage": nextPage]
    }

    /// One listed item, made off the main thread and turned into JSON afterwards.
    struct ListedEntry: Sendable {
        let path: VaultPath
        let isFolder: Bool
        let size: Int
        let modified: Date
        let created: Date

        init(path: VaultPath, values: URLResourceValues) {
            self.path = path
            isFolder = values.isDirectory == true
            size = values.fileSize ?? 0
            modified = values.contentModificationDate ?? .distantPast
            created = values.creationDate ?? modified
        }
    }
}

/// The listings not fully sent yet. A runtime that stops midway leaves one here until its bridge
/// goes with it.
actor CommunityPluginOpenListings {
    private var remainingByIdentifier: [String: ArraySlice<CommunityPluginVaultBridge.ListedEntry>] = [:]

    func keep(_ remaining: ArraySlice<CommunityPluginVaultBridge.ListedEntry>) -> String {
        let identifier = UUID().uuidString
        remainingByIdentifier[identifier] = remaining
        return identifier
    }

    func take(_ identifier: String) -> ArraySlice<CommunityPluginVaultBridge.ListedEntry>? {
        remainingByIdentifier.removeValue(forKey: identifier)
    }
}
