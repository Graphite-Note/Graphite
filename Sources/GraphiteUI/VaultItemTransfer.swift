/**
 * File: VaultItemTransfer.swift
 * -----------------------------
 * Layer: UI
 * Description: A file or folder being dragged, with the vault it comes from.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// A file or folder dragged in the sidebar or the library.
struct VaultItemTransfer: Codable, Transferable {
    let path: String
    /// Where the file is on disk, so a drag out of Graphite gives Files, the Finder or another app
    /// the file itself. Not encoded: a drop inside Graphite needs the vault path only.
    var fileLocation: URL?
    /// The folder of the vault the item comes from: two windows can show two vaults, and
    /// `path` means something else in the other one. Nil from a drag that does not say, which
    /// counts as coming from the vault it lands in.
    var vaultRoot: URL?

    init(path: String, fileLocation: URL? = nil, vaultRoot: URL? = nil) {
        self.path = path
        self.fileLocation = fileLocation
        self.vaultRoot = vaultRoot
    }

    private enum CodingKeys: String, CodingKey { case path, vaultRoot }

    /// The item's path, when it comes from the vault at `root`.
    func path(inVaultAt root: URL?) -> VaultPath? {
        guard !isFromAnotherVault(than: root) else { return nil }
        return try? VaultPath(path) // A path no vault can hold moves nothing.
    }

    /// Whether the item comes from a vault other than the one at `root`.
    func isFromAnotherVault(than root: URL?) -> Bool {
        guard let vaultRoot, let root else { return false }
        return vaultRoot.standardizedFileURL.resolvingSymlinksInPath() != root.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Where the item is on disk, from what the drag carries.
    var sourceLocation: URL? {
        vaultRoot?.appendingPathComponent(path)
    }

    static var transferRepresentation: some TransferRepresentation {
        // The vault item first: a drop in Graphite moves it. Other apps take the file.
        CodableRepresentation(contentType: .graphiteVaultItem)
        FileRepresentation(exportedContentType: .item) { transfer in
            guard let fileLocation = transfer.fileLocation else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(fileLocation, allowAccessingOriginalFile: true)
        }
    }
}

extension UTType {
    /// Declared in the app's Info.plist; used only for drags inside Graphite.
    static let graphiteVaultItem = UTType(exportedAs: "com.graphite.study.vault-item")
}
