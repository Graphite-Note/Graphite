/**
 * File: TabTransfer.swift
 * -----------------------
 * Layer: UI
 * Description: A tab dragged between tab bars, in a window or from one window to another.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// A tab being dragged to another place in a tab bar.
struct TabTransfer: Codable, Transferable {
    let tabID: UUID
    /// The tab's file and its vault. Another window does not have the tab, so a drop there opens
    /// the file in a tab of its own, when the window shows the same vault.
    var path: String?
    var vaultIdentifier: UUID?

    init(tabID: UUID, path: String? = nil, vaultIdentifier: UUID? = nil) {
        self.tabID = tabID
        self.path = path
        self.vaultIdentifier = vaultIdentifier
    }

    init(tab: WorkspaceTab, vaultIdentifier: UUID?) {
        self.init(tabID: tab.id, path: tab.path?.rawValue, vaultIdentifier: vaultIdentifier)
    }

    /// What a window does with a dropped tab.
    enum Drop: Equatable {
        /// The tab is in this window's layout: it moves.
        case moveTab(UUID)
        /// The tab came from another window on the same vault: its file opens in a new tab.
        case openFile(VaultPath)
        case refused
    }

    func drop(in layout: TabLayout, vaultIdentifier currentVaultIdentifier: UUID?) -> Drop {
        if layout.tab(withID: tabID) != nil { return .moveTab(tabID) }
        guard let vaultIdentifier, vaultIdentifier == currentVaultIdentifier, let path else { return .refused }
        // A path that no longer reads as one is refused, like a drop from another vault.
        guard let filePath = try? VaultPath(path) else { return .refused }
        return .openFile(filePath)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .graphiteTab)
    }
}

extension UTType {
    /// Declared in the app's Info.plist; used only for drags inside Graphite.
    static let graphiteTab = UTType(exportedAs: "com.graphite.study.tab")
}
