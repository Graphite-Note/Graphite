/**
 * File: LibraryListing.swift
 * --------------------------
 * Layer: Core
 * Description: Which files the library shows; folders are always shown.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import Foundation

/// Which files the library shows; folders are always shown.
public enum LibraryFilter: String, CaseIterable, Sendable, Identifiable {
    case all, notebooks, notes, pictures, boards

    public var id: String { rawValue }

    public func includes(_ kind: DocumentKind) -> Bool {
        switch self {
        case .all: true
        case .notebooks: kind == .pdf
        case .notes: kind == .markdown
        case .pictures: kind == .image
        case .boards: kind == .canvas || kind == .base
        }
    }
}

/// What the library shows of one folder's listing, in order.
public enum LibraryListing {
    /// The folders and the files the filter lets through, keeping the order of `sortedEntries`,
    /// which a listing gives folders first and in the vault's sort order: a filter never changes
    /// the order, so nothing is compared.
    public static func items(ofSorted sortedEntries: [VaultEntry], filter: LibraryFilter) -> [VaultEntry] {
        sortedEntries.filter { entry in entry.isDirectory || filter.includes(entry.kind) }
    }
}
