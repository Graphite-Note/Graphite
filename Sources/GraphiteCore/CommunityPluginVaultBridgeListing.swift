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

    /// A page crosses as one text of parallel lists (`CommunityPluginListedEntry.encoded`).
    func listingAnswer(for entries: ArraySlice<CommunityPluginListedEntry>, isTruncated: Bool) async throws -> [String: Any] {
        let encodedEntries = try await CommunityPluginListedEntry.encoded(Array(entries.prefix(Self.maximumListedEntriesPerPage)))
        guard entries.count > Self.maximumListedEntriesPerPage else { return ["encodedEntries": encodedEntries, "isTruncated": isTruncated] }
        let nextPage = await openListings.keep(entries.dropFirst(Self.maximumListedEntriesPerPage))
        return ["encodedEntries": encodedEntries, "isTruncated": isTruncated, "nextPage": nextPage]
    }
}

/// The listings not fully sent yet. A runtime that stops midway leaves one here until its bridge
/// goes with it.
actor CommunityPluginOpenListings {
    private var remainingByIdentifier: [String: ArraySlice<CommunityPluginListedEntry>] = [:]

    func keep(_ remaining: ArraySlice<CommunityPluginListedEntry>) -> String {
        let identifier = UUID().uuidString
        remainingByIdentifier[identifier] = remaining
        return identifier
    }

    func take(_ identifier: String) -> ArraySlice<CommunityPluginListedEntry>? {
        remainingByIdentifier.removeValue(forKey: identifier)
    }
}
