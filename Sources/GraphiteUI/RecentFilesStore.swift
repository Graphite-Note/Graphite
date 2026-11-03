/**
 * File: RecentFilesStore.swift
 * ----------------------------
 * Layer: UI
 * Description: The recently opened files of each vault, shared by every window of the process.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import Observation
import GraphiteCore

/// The recently opened files of each vault, remembered per vault on the device. One store
/// for every window (`ProcessServices`), so two windows on one vault share one list: a file
/// opened in one window is in the other's quick switcher at once, and neither window writes
/// over the other's list with a copy read earlier.
///
/// The device's preferences hold the same list under the vault's key, written with every
/// change, so what a later launch reads is always the list as it was last changed.
@MainActor @Observable
final class RecentFilesStore {
    private(set) var recentFilesByVault: [UUID: RecentFiles] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func defaultsKey(forVault vaultIdentifier: UUID) -> String {
        "GraphiteRecentFiles." + vaultIdentifier.uuidString
    }

    /// The vault's recent files, as last read or changed; none for a vault not yet read.
    func recentFiles(forVault vaultIdentifier: UUID) -> RecentFiles {
        recentFilesByVault[vaultIdentifier] ?? RecentFiles()
    }

    /// Reads the vault's list from the device, as a window does when it opens the vault.
    func load(forVault vaultIdentifier: UUID) {
        let storedPaths = defaults.stringArray(forKey: Self.defaultsKey(forVault: vaultIdentifier)) ?? []
        let paths = storedPaths.compactMap { path in try? VaultPath(path) } // A path that no longer reads as one is dropped.
        recentFilesByVault[vaultIdentifier] = RecentFiles(paths: paths)
    }

    func update(_ recentFiles: RecentFiles, forVault vaultIdentifier: UUID) {
        guard recentFiles != self.recentFiles(forVault: vaultIdentifier) else { return }
        recentFilesByVault[vaultIdentifier] = recentFiles
        defaults.set(recentFiles.paths.map(\.rawValue), forKey: Self.defaultsKey(forVault: vaultIdentifier))
    }

    /// Forgets a vault's list, in memory and on the device, as when the vault is removed.
    func forgetVault(_ vaultIdentifier: UUID) {
        recentFilesByVault[vaultIdentifier] = nil
        defaults.removeObject(forKey: Self.defaultsKey(forVault: vaultIdentifier))
    }
}
