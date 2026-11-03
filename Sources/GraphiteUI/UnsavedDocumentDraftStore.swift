/**
 * File: UnsavedDocumentDraftStore.swift
 * -------------------------------------
 * Layer: UI
 * Description: Keeps the text of notes and canvases that could not reach their files, in the app's own
 *              Application Support folder and never in a vault, so it outlives the app.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import CryptoKit
import Foundation
import GraphiteCore

/// A document's edits as they were when its file could not take them: a save was refused or
/// failed, or the app was about to leave the screen with them unsaved.
struct UnsavedDocumentDraft: Codable, Equatable, Sendable {
    let path: VaultPath
    /// The whole file as the open document would save it.
    let contents: Data
    /// The version of the file the edits were made over. The draft may be saved over that
    /// version only: any other file is newer, and is a conflict for the person to settle.
    let baseRevision: FileRevision
    let date: Date
}

/// Each draft is one file named after a hash of the note's vault path, in a folder per vault,
/// written like a save: it is whole or absent, and it survives the app ending right after.
/// They are the person's unsaved work, not a cache. A vault with no drafts costs nothing: no
/// file is touched while saves succeed.
@MainActor
final class UnsavedDocumentDraftStore {
    let directory: URL
    /// Writes and removals run one after another in the order they were asked for, so a
    /// removal after a save cannot be overtaken by an earlier write, nor a newer text by an
    /// older one.
    private var latestOperation: Task<Void, Never>?
    /// Vaults a window has already told about the drafts an ended app left.
    private var vaultsToldAboutDrafts: Set<UUID> = []

    init(directory: URL) {
        self.directory = directory
    }

    /// The drafts folder in `applicationFolders`' Application Support. One store per process
    /// (`ProcessServices`) writes it, for every window.
    static func directory(in applicationFolders: ApplicationFolders) -> URL {
        (applicationFolders.applicationSupportFolder ?? URL.applicationSupportDirectory).appendingPathComponent("Unsaved Drafts", isDirectory: true)
    }

    /// Writes the draft, replacing the path's earlier one.
    /// - Returns: Whether the draft is on disk, once it is.
    func keep(_ draft: UnsavedDocumentDraft, inVault vaultIdentifier: UUID) async -> Bool {
        let location = Self.location(of: draft.path, in: folder(ofVault: vaultIdentifier))
        return await enqueue { (try? Self.write(draft, to: location)) != nil }.value // The caller is told, and quitting stops for it.
    }

    func remove(_ path: VaultPath, inVault vaultIdentifier: UUID) {
        let location = Self.location(of: path, in: folder(ofVault: vaultIdentifier))
        _ = enqueue { try? FileManager.default.removeItem(at: location) } // No draft there is the same outcome.
    }

    /// Forgets a vault's drafts, as for a vault taken off the list.
    func removeAll(inVault vaultIdentifier: UUID) {
        let folder = folder(ofVault: vaultIdentifier)
        _ = enqueue { try? FileManager.default.removeItem(at: folder) } // No folder there is the same outcome.
    }

    /// The path's draft, read after every write and removal asked for so far.
    func draft(of path: VaultPath, inVault vaultIdentifier: UUID) async -> UnsavedDocumentDraft? {
        let location = Self.location(of: path, in: folder(ofVault: vaultIdentifier))
        return await enqueue { Self.readDraft(at: location) }.value
    }

    /// Every draft of the vault, read after every write and removal asked for so far. A file
    /// that cannot be read is left on disk, untouched.
    func drafts(inVault vaultIdentifier: UUID) async -> [UnsavedDocumentDraft] {
        let folder = folder(ofVault: vaultIdentifier)
        return await enqueue { Self.readDrafts(in: folder) }.value
    }

    /// Lets the drafts of a moved file, or of the files in a moved folder, follow them.
    func moveDrafts(from path: VaultPath, to destination: VaultPath, inVault vaultIdentifier: UUID) {
        let folder = folder(ofVault: vaultIdentifier)
        _ = enqueue {
            for draft in Self.readDrafts(in: folder) where draft.path.isInside(path) {
                guard let newPath = try? draft.path.replacingPrefix(path, with: destination) else { continue } // It stays, and comes back as a copy.
                let movedDraft = UnsavedDocumentDraft(path: newPath, contents: draft.contents, baseRevision: draft.baseRevision, date: draft.date)
                // The old one goes only once the new one is on disk.
                guard (try? Self.write(movedDraft, to: Self.location(of: newPath, in: folder))) != nil else { continue } // It stays, and comes back as a copy.
                try? FileManager.default.removeItem(at: Self.location(of: draft.path, in: folder)) // Left over, it comes back as a copy.
            }
        }
    }

    /// Whether a window should still tell about this vault's drafts; true once per vault, so
    /// a second window on it says nothing new.
    func takeTurnToTellAboutDrafts(inVault vaultIdentifier: UUID) -> Bool {
        vaultsToldAboutDrafts.insert(vaultIdentifier).inserted
    }

    private func folder(ofVault vaultIdentifier: UUID) -> URL {
        directory.appendingPathComponent(vaultIdentifier.uuidString, isDirectory: true)
    }

    private func enqueue<Outcome: Sendable>(_ operation: @escaping @Sendable () -> Outcome) -> Task<Outcome, Never> {
        let previousOperation = latestOperation
        let task = Task.detached(priority: .userInitiated) {
            await previousOperation?.value
            return operation()
        }
        latestOperation = Task { _ = await task.value }
        return task
    }

    private nonisolated static func location(of path: VaultPath, in folder: URL) -> URL {
        let digest = SHA256.hash(data: Data(path.rawValue.utf8)).map { byte in String(format: "%02x", byte) }.joined()
        return folder.appendingPathComponent(digest + ".draft")
    }

    private nonisolated static func write(_ draft: UnsavedDocumentDraft, to location: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(draft)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let expectation: WriteExpectation = FileManager.default.fileExists(atPath: location.path) ? .revision(try FileRevision.read(location)) : .absent
        try AtomicFileWriter().write(data, to: location, expecting: expectation)
    }

    private nonisolated static func readDraft(at location: URL) -> UnsavedDocumentDraft? {
        guard FileManager.default.fileExists(atPath: location.path),
              let data = try? Data(contentsOf: location) else { return nil } // Unreadable now: left on disk for later.
        return try? PropertyListDecoder().decode(UnsavedDocumentDraft.self, from: data) // Damaged: left on disk, untouched.
    }

    private nonisolated static func readDrafts(in folder: URL) -> [UnsavedDocumentDraft] {
        let locations = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] // No folder: no drafts.
        return locations.filter { location in location.pathExtension == "draft" }.compactMap(readDraft(at:))
    }
}

/// What a note or canvas needs to keep its own draft: the process's store, its vault and its path.
@MainActor
struct DocumentDraftKeeper {
    let store: UnsavedDocumentDraftStore
    let vaultIdentifier: UUID
    let path: VaultPath

    func keep(_ contents: Data, madeOver revision: FileRevision) async -> Bool {
        await store.keep(UnsavedDocumentDraft(path: path, contents: contents, baseRevision: revision, date: .now), inVault: vaultIdentifier)
    }

    func remove() {
        store.remove(path, inVault: vaultIdentifier)
    }

    func storedDraft() async -> UnsavedDocumentDraft? {
        await store.draft(of: path, inVault: vaultIdentifier)
    }

    /// The draft kept so far follows the document's file to `newPath`.
    func moveDraft(to newPath: VaultPath) {
        store.moveDrafts(from: path, to: newPath, inVault: vaultIdentifier)
    }

    /// The keeper of the same document at `newPath`.
    func following(to newPath: VaultPath) -> DocumentDraftKeeper {
        DocumentDraftKeeper(store: store, vaultIdentifier: vaultIdentifier, path: newPath)
    }
}

/// How long a note's or canvas's autosave waits before trying a failed save again: longer
/// after each failure in a row, so one that keeps failing does not keep the disk busy.
enum AutosaveRetryPolicy {
    static let firstDelay = Duration.seconds(2)
    static let maximumDelay = Duration.seconds(60)
    private static let maximumDoublings = 5

    static func delay(afterConsecutiveFailures failureCount: Int) -> Duration {
        min(firstDelay * (1 << min(max(failureCount - 1, 0), maximumDoublings)), maximumDelay)
    }
}
