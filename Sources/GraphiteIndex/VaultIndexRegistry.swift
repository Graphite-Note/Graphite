/**
 * File: VaultIndexRegistry.swift
 * ------------------------------
 * Layer: Index
 * Description: What a window hears about the index of its vault, which every window on that vault
 *              shares.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// What a window hears about the index of its vault, which every window on that vault shares.
public enum VaultIndexEvent: Sendable {
    /// A scan of the whole vault started, asked for by this window or another.
    case scanStarted
    /// A scan ended; `isAnotherScanQueued` when a scan asked for meanwhile runs next.
    case scanFinished(IndexingReport, isAnotherScanQueued: Bool)
    /// A scan stopped before its end, as when the index is emptied for a rebuild.
    case scanCancelled
    case scanFailed(any Error)
    /// Every entry was removed for a rebuild: the index is incomplete until the next scan
    /// ends, so a link followed meanwhile must not create a note that exists.
    case emptied
}

/// Whether a scan asked for must read the vault again, or may stand on one that already
/// ended or is running.
public enum VaultIndexScanRequest: Sendable {
    /// A window opening the vault: another window's finished or running scan serves it.
    case unlessScanned
    /// Something changed that a scan which started earlier may have missed.
    case always
    /// Another app changed what cannot be named, as a sync does again and again: a scan of the
    /// whole vault follows, but not sooner than `minimumSpacingOfSpacedScans` after the last.
    case spaced
    /// Another app changed what is inside this folder, and only that is read again.
    case folder(VaultPath)
}

/// One index per vault for the whole process (decision 12 of
/// `Docs/solid/rewrite-foundations.md`); the app's `ProcessServices` holds one. Two windows on one vault used to open the vault's
/// cache file twice, failing each other's writes ("database is locked") and pruning each
/// other's rows on rescan. Now they share one `VaultIndex`, an actor and so the file's single
/// writer, and one scan at a time; the index closes when the last window on its vault ends
/// its lease. Two vaults in two windows keep an index each.
@MainActor
public final class VaultIndexRegistry {
    /// One vault's index and its scans, while a window has the vault open.
    private final class SharedIndex {
        let vaultIdentifier: UUID
        let opening: Task<VaultIndex, any Error>
        /// The folder scans read: the latest a window opened the vault at.
        var root: URL
        var listeners: [UUID: AsyncStream<VaultIndexEvent>.Continuation] = [:]
        var runningScan: Task<Void, Never>?
        var isScanQueued = false
        /// Folders to read when the running scan ends; a queued scan of everything covers them.
        var queuedFolders: Set<VaultPath> = []
        var isSpacedScanQueued = false
        /// The wait for the spacing to pass before a spaced scan starts.
        var spacingWait: Task<Void, Never>?
        var lastWholeScanEnd: Duration?
        /// The last finished scan's report; nil before one finished or once the index is emptied.
        var lastReport: IndexingReport?

        init(vaultIdentifier: UUID, root: URL, opening: Task<VaultIndex, any Error>) {
            self.vaultIdentifier = vaultIdentifier
            self.root = root
            self.opening = opening
        }
    }

    private let cachesFolder: URL?
    private let minimumSpacingOfSpacedScans: Duration
    private let clock: any ApplicationClock
    private var sharedIndexes: [UUID: SharedIndex] = [:]

    /// Indexes kept in `cachesFolder`, or in the system's Caches folder when nil.
    public init(cachesFolder: URL?, minimumSpacingOfSpacedScans: Duration = .seconds(30), clock: any ApplicationClock = LiveApplicationClock()) {
        self.cachesFolder = cachesFolder
        self.clock = clock
        self.minimumSpacingOfSpacedScans = minimumSpacingOfSpacedScans
    }

    /// Whether a window has the vault open, so its index must stay.
    public func isOpen(_ vaultIdentifier: UUID) -> Bool { sharedIndexes[vaultIdentifier]?.listeners.isEmpty == false }

    /// The index of the vault `vaultIdentifier` at `root`, opened unless a window has it open.
    public func lease(forVault vaultIdentifier: UUID, root: URL) async throws -> VaultIndexLease {
        let shared = sharedIndexes[vaultIdentifier] ?? open(vaultIdentifier, root: root)
        // The last window on the vault closed while its scan was stopping: that scan reports
        // nothing this window asked for, so one follows it.
        if shared.listeners.isEmpty, shared.runningScan != nil { shared.isScanQueued = true }
        shared.root = root
        let (events, continuation) = AsyncStream.makeStream(of: VaultIndexEvent.self)
        let leaseIdentifier = UUID()
        // Counted before the wait, so a window that closes meanwhile does not close the index.
        shared.listeners[leaseIdentifier] = continuation
        do {
            let index = try await shared.opening.value
            return VaultIndexLease(identifier: leaseIdentifier, vaultIdentifier: vaultIdentifier, index: index, events: events, registry: self)
        } catch {
            continuation.finish()
            shared.listeners[leaseIdentifier] = nil
            // A failed opening is not kept: the next window to open the vault tries again. (A damaged
            // database never gets here: opening it made it again.)
            if sharedIndexes[vaultIdentifier] === shared { sharedIndexes[vaultIdentifier] = nil }
            throw error
        }
    }

    private func open(_ vaultIdentifier: UUID, root: URL) -> SharedIndex {
        let cachesFolder = cachesFolder
        let shared = SharedIndex(vaultIdentifier: vaultIdentifier, root: root, opening: Task.detached(priority: .utility) {
            let location = try VaultIndex.cacheURL(forVault: vaultIdentifier, legacyRoot: root, in: cachesFolder)
            return try VaultIndex.openRebuildingIfDamaged(databaseURL: location)
        })
        sharedIndexes[vaultIdentifier] = shared
        return shared
    }

    fileprivate func requestScan(_ request: VaultIndexScanRequest, for lease: VaultIndexLease) {
        guard let shared = sharedIndexes[lease.vaultIdentifier], shared.listeners[lease.identifier] != nil else { return }
        switch request {
        case .folder(let folder):
            // Before a scan of the whole vault ended, a folder's scan would count for one.
            guard shared.lastReport != nil || shared.runningScan != nil else { return startScan(of: shared, index: lease.index) }
            if shared.runningScan != nil {
                shared.queuedFolders.insert(folder)
            } else {
                startScan(of: shared, index: lease.index, inside: folder)
            }
        case .spaced:
            if shared.runningScan != nil {
                shared.isSpacedScanQueued = true
            } else {
                startSpacedScan(of: shared, index: lease.index)
            }
        case .always:
            // The running scan may have read past what prompted the request.
            if shared.runningScan != nil {
                shared.isScanQueued = true
            } else {
                startScan(of: shared, index: lease.index)
            }
        case .unlessScanned:
            guard shared.runningScan == nil else { return }
            if let lastReport = shared.lastReport {
                shared.listeners[lease.identifier]?.yield(.scanFinished(lastReport, isAnotherScanQueued: false))
            } else {
                startScan(of: shared, index: lease.index)
            }
        }
    }

    /// Scans the whole vault now, or once the spacing since the last scan has passed.
    private func startSpacedScan(of shared: SharedIndex, index: VaultIndex) {
        shared.isSpacedScanQueued = false
        guard shared.spacingWait == nil else { return }
        let timeSinceLastScan = shared.lastWholeScanEnd.map { scanEnd in clock.now - scanEnd }
        guard let timeSinceLastScan, timeSinceLastScan < minimumSpacingOfSpacedScans else { return startScan(of: shared, index: index) }
        let remainingSpacing = minimumSpacingOfSpacedScans - timeSinceLastScan
        shared.spacingWait = Task { [weak self, weak shared, clock] in
            do { try await clock.sleep(for: remainingSpacing) } catch { return }
            guard let self, let shared else { return }
            shared.spacingWait = nil
            if shared.runningScan != nil {
                shared.isScanQueued = true
            } else if !shared.listeners.isEmpty {
                self.startScan(of: shared, index: index)
            }
        }
    }

    private func startScan(of shared: SharedIndex, index: VaultIndex, inside folder: VaultPath? = nil) {
        if folder == nil {
            shared.isScanQueued = false
            shared.queuedFolders = []
            shared.isSpacedScanQueued = false
            shared.spacingWait?.cancel(); shared.spacingWait = nil
        }
        broadcast(.scanStarted, to: shared)
        let root = shared.root
        // Below the editor's priority, so a scan does not compete with typing and scrolling.
        shared.runningScan = Task(priority: .utility) { [weak self, weak shared] in
            let outcome: Result<IndexingReport, any Error>
            do { outcome = .success(try await index.reconcile(root: root, inside: folder)) } catch { outcome = .failure(error) }
            guard let self, let shared else { return }
            self.scanDidEnd(of: shared, index: index, inside: folder, with: outcome)
        }
    }

    private func scanDidEnd(of shared: SharedIndex, index: VaultIndex, inside folder: VaultPath?, with outcome: Result<IndexingReport, any Error>) {
        shared.runningScan = nil
        // The last window on the vault closed meanwhile: the index closes now.
        guard !shared.listeners.isEmpty else {
            if sharedIndexes[shared.vaultIdentifier] === shared { sharedIndexes[shared.vaultIdentifier] = nil }
            return
        }
        if folder == nil { shared.lastWholeScanEnd = clock.now }
        let isAnotherScanQueued = shared.isScanQueued || !shared.queuedFolders.isEmpty
        switch outcome {
        case .success(let report):
            shared.lastReport = report
            broadcast(.scanFinished(report, isAnotherScanQueued: isAnotherScanQueued), to: shared)
        case .failure(let error) where error is CancellationError:
            broadcast(.scanCancelled, to: shared)
        case .failure(let error):
            broadcast(.scanFailed(error), to: shared)
        }
        if shared.isScanQueued {
            startScan(of: shared, index: index)
        } else if let nextFolder = shared.queuedFolders.popFirst() {
            // A scan of everything that failed leaves only a scan of everything to count as one.
            startScan(of: shared, index: index, inside: shared.lastReport == nil ? nil : nextFolder)
        }
        if shared.isSpacedScanQueued {
            if shared.runningScan == nil { startSpacedScan(of: shared, index: index) }
        }
    }

    /// Empties the index and scans the vault again, for every window on it. A scan running
    /// is stopped first: it would count entries the removal deletes.
    fileprivate func rebuild(for lease: VaultIndexLease) async throws {
        guard let shared = sharedIndexes[lease.vaultIdentifier] else { return }
        let previousReport = shared.lastReport
        shared.lastReport = nil
        shared.isScanQueued = false
        shared.queuedFolders = []
        shared.isSpacedScanQueued = false
        shared.spacingWait?.cancel(); shared.spacingWait = nil
        broadcast(.emptied, to: shared)
        if let runningScan = shared.runningScan {
            runningScan.cancel()
            await runningScan.value
        }
        do {
            try await lease.index.removeAllEntries()
        } catch {
            // The removal is one transaction, so the index is as it was.
            if let previousReport, shared.runningScan == nil {
                shared.lastReport = previousReport
                broadcast(.scanFinished(previousReport, isAnotherScanQueued: false), to: shared)
            }
            throw error
        }
        guard !shared.listeners.isEmpty, shared.runningScan == nil else { return }
        startScan(of: shared, index: lease.index)
    }

    fileprivate func endLease(_ lease: VaultIndexLease) {
        guard let shared = sharedIndexes[lease.vaultIdentifier],
              let continuation = shared.listeners.removeValue(forKey: lease.identifier) else { return }
        continuation.finish()
        guard shared.listeners.isEmpty else { return }
        shared.spacingWait?.cancel(); shared.spacingWait = nil
        // The last window on the vault: its scan stops and the index closes once the
        // windows let go of it. A stopping scan still holds the database, so the index stays
        // listed until it ends, and a window opening the vault meanwhile shares this
        // connection instead of opening a second one, which the first would lock out.
        if let runningScan = shared.runningScan {
            runningScan.cancel()
            return
        }
        sharedIndexes[lease.vaultIdentifier] = nil
    }

    private func broadcast(_ event: VaultIndexEvent, to shared: SharedIndex) {
        for continuation in shared.listeners.values { continuation.yield(event) }
    }
}

/// One window's hold on its vault's shared index: the index, the events of its scans, and
/// the scans and rebuilds the window asks for. Ending it, or letting it go, lets the index
/// close when no other window holds it.
@MainActor
public final class VaultIndexLease {
    fileprivate let identifier: UUID
    public let vaultIdentifier: UUID
    public let index: VaultIndex
    /// Every scan's start and end, and the rebuild's emptying, whichever window asked.
    public let events: AsyncStream<VaultIndexEvent>
    private weak var registry: VaultIndexRegistry?

    fileprivate init(identifier: UUID, vaultIdentifier: UUID, index: VaultIndex, events: AsyncStream<VaultIndexEvent>, registry: VaultIndexRegistry) {
        self.identifier = identifier
        self.vaultIdentifier = vaultIdentifier
        self.index = index
        self.events = events
        self.registry = registry
    }

    isolated deinit {
        registry?.endLease(self)
    }

    public func requestScan(_ request: VaultIndexScanRequest) {
        registry?.requestScan(request, for: self)
    }

    public func rebuild() async throws {
        try await registry?.rebuild(for: self)
    }

    public func end() {
        registry?.endLease(self)
    }
}
