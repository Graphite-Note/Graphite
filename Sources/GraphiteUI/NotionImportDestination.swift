/**
 * File: NotionImportDestination.swift
 * -----------------------------------
 * Layer: UI
 * Description: The open vault as the Importer's destination: every folder and file written through the vault's
 *              coordinated writer, never over a file already there, with the import held while it is paused. Updating
 *              an earlier import, a file is replaced only while it is what the import read.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore
import ImporterCore
import Synchronization

/// The open vault as the Importer's `ImportDestination`. A folder is made with the store, a note or base is saved as a
/// new file, and an attachment is written piece by piece into a staged file outside the vault that moves into place as
/// one coordinated write when it ends, so a sync provider never sees half of it. Nothing already in the vault is
/// replaced. Before each write the import waits while it is paused (`NotionImportPause`), and each file written is
/// handed to `filesWritten`, which refreshes the index in batches.
struct NotionImportDestination: ImportDestination {
    let store: VaultStore
    let pause: NotionImportPause
    let filesWritten: NotionImportWrittenFiles

    func createFolder(at path: ImporterCore.VaultPath) async throws {
        await pause.waitWhilePaused()
        try await store.createDirectory(try Self.vaultPath(of: path))
    }

    func writeNewFile(_ contents: [UInt8], at path: ImporterCore.VaultPath) async throws {
        await pause.waitWhilePaused()
        let vaultPath = try Self.vaultPath(of: path)
        do {
            _ = try await store.save(Data(contents), at: vaultPath, expecting: .absent)
        } catch GraphiteError.conflict {
            throw ImportDestinationError.fileAlreadyExists(path)
        }
        await filesWritten.add(vaultPath)
    }

    func createNewFile(at path: ImporterCore.VaultPath) async throws -> any ImportFileWriting {
        await pause.waitWhilePaused()
        let vaultPath = try Self.vaultPath(of: path)
        let location = try vaultPath.url(in: store.root)
        if FileManager.default.fileExists(atPath: location.path) { throw ImportDestinationError.fileAlreadyExists(path) }
        return try NotionImportStagedFile(destination: location, writer: store.writer, pause: pause) { [filesWritten] in
            await filesWritten.add(vaultPath)
        }
    }

    func names(inFolderAt path: ImporterCore.VaultPath) async throws -> [String] {
        let location = try Self.vaultPath(of: path).url(in: store.root)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isFolder), isFolder.boolValue else { return [] }
        return try store.writer.readingCoordinated(location) { coordinatedLocation in
            try FileManager.default.contentsOfDirectory(atPath: coordinatedLocation.path)
        }
    }

    func assignPropertyTypes(_ types: [String: ImporterCore.PropertyType]) async throws -> [String] {
        await pause.waitWhilePaused()
        // Every type the Importer writes is one of Obsidian's, which Graphite knows by the same names.
        let vaultTypes = types.compactMapValues { type in GraphiteCore.PropertyType(rawValue: type.rawValue) }
        return try await store.assignPropertyTypesKeepingExisting(vaultTypes)
    }

    /// Graphite's path of an Importer path, both relative to the vault's folder.
    static func vaultPath(of path: ImporterCore.VaultPath) throws -> GraphiteCore.VaultPath {
        try GraphiteCore.VaultPath(path.components.joined(separator: "/"))
    }
}

/// The folder of an earlier import, updated by a later import of the same workspace through Notion's API: a file is
/// replaced only while it still holds the bytes the import read, by the store's save checked against the revision read.
extension NotionImportDestination: UpdatingImportDestination {
    func readFile(at path: ImporterCore.VaultPath) async throws -> [UInt8]? {
        let vaultPath = try Self.vaultPath(of: path)
        guard try await store.fileExists(vaultPath) else { return nil }
        return Array(try await store.read(vaultPath).data)
    }

    func replaceFile(at path: ImporterCore.VaultPath, expecting expected: [UInt8], with contents: [UInt8]) async throws {
        await pause.waitWhilePaused()
        let vaultPath = try Self.vaultPath(of: path)
        guard try await store.fileExists(vaultPath) else { throw ImportUpdateError.changedSinceRead(path) }
        let snapshot = try await store.read(vaultPath)
        guard Array(snapshot.data) == expected else { throw ImportUpdateError.changedSinceRead(path) }
        do {
            _ = try await store.save(Data(contents), at: vaultPath, expecting: .revision(snapshot.revision))
        } catch GraphiteError.conflict {
            throw ImportUpdateError.changedSinceRead(path)
        }
        await filesWritten.add(vaultPath)
    }

    func filePaths(inFolderAt path: ImporterCore.VaultPath) async throws -> [ImporterCore.VaultPath] {
        let location = try Self.vaultPath(of: path).url(in: store.root)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isFolder), isFolder.boolValue else { return [] }
        let relativePaths = try store.writer.readingCoordinated(location) { coordinatedLocation in
            try FileManager.default.subpathsOfDirectory(atPath: coordinatedLocation.path).filter { relativePath in
                let entry = coordinatedLocation.appendingPathComponent(relativePath)
                return (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true // An unreadable entry is no file to update.
            }
        }
        return relativePaths.sorted().compactMap { relativePath in
            ImporterCore.VaultPath(components: path.components + relativePath.split(separator: "/").map(String.init))
        }
    }
}

/// An attachment being written: its pieces go to a file in a private folder on the vault's volume, which moves into the
/// vault through the coordinated writer when it is closed, never over a file already there. A file left unclosed (the
/// import failed or stopped) is removed with its folder.
actor NotionImportStagedFile: ImportFileWriting {
    private let destination: URL
    private let writer: AtomicFileWriter
    private let pause: NotionImportPause
    private let whenWritten: @Sendable () async -> Void
    private let stagingFolder: URL
    private let stagedFile: URL
    private let handle: FileHandle

    init(destination: URL, writer: AtomicFileWriter, pause: NotionImportPause, whenWritten: @escaping @Sendable () async -> Void) throws {
        self.destination = destination
        self.writer = writer
        self.pause = pause
        self.whenWritten = whenWritten
        stagingFolder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        stagedFile = stagingFolder.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: stagedFile.path, contents: nil) else {
            try? FileManager.default.removeItem(at: stagingFolder) // A folder the system made for this file alone.
            throw NotionImportFileFailure.noTemporaryFile(fileName: destination.lastPathComponent)
        }
        do {
            handle = try FileHandle(forWritingTo: stagedFile)
        } catch {
            try? FileManager.default.removeItem(at: stagingFolder) // A folder the system made for this file alone.
            throw error
        }
    }

    deinit {
        try? handle.close() // Already closed when the file was written.
        try? FileManager.default.removeItem(at: stagingFolder) // Only this file's staging folder, emptied or not.
    }

    func append(_ bytes: [UInt8]) async throws {
        await pause.waitWhilePaused()
        try handle.write(contentsOf: Data(bytes))
    }

    func close() async throws {
        try handle.close()
        let stagedFile = stagedFile
        do {
            try writer.replace(destination, expecting: .absent) { staging in try FileManager.default.moveItem(at: stagedFile, to: staging) }
        } catch GraphiteError.conflict {
            throw NotionImportFileFailure.appearedWhileImported(fileName: destination.lastPathComponent)
        }
        await whenWritten()
    }
}

/// Why an import could not write one of its files or folders.
enum NotionImportFileFailure: LocalizedError, Equatable {
    /// No temporary file could be made to write an attachment into.
    case noTemporaryFile(fileName: String)
    /// Another file was put at an attachment's place while it was written, and that file is kept.
    case appearedWhileImported(fileName: String)
    /// The folder chosen for the import is not one of the vault's folders.
    case notAVaultFolder(path: String)

    var errorDescription: String? {
        switch self {
        case .noTemporaryFile(let fileName): "Graphite could not make a temporary file for “\(fileName)”."
        case .appearedWhileImported(let fileName): "A file appeared at “\(fileName)” while it was imported, and it is kept."
        case .notAVaultFolder(let path): "“\(path)” is not a folder of this vault."
        }
    }
}

/// Holds an import while it is paused: each write waits here until the import is resumed or stopped.
final class NotionImportPause: Sendable {
    private struct State {
        var isPaused = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var isPaused: Bool { state.withLock { state in state.isPaused } }

    /// How many writes wait for the import to be resumed.
    var waitingWriteCount: Int { state.withLock { state in state.waiting.count } }

    func pause() {
        state.withLock { state in state.isPaused = true }
    }

    /// Lets every waiting write go on, as Resume and Cancel do.
    func resume() {
        let waiting = state.withLock { state in
            state.isPaused = false
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in waiting { continuation.resume() }
    }

    func waitWhilePaused() async {
        await withCheckedContinuation { continuation in
            let mustWait = state.withLock { state in
                if state.isPaused { state.waiting.append(continuation) }
                return state.isPaused
            }
            if !mustWait { continuation.resume() }
        }
    }
}

/// The files an import has written, handed to the vault in batches so the file list and the index take them in while the
/// import goes on, without a refresh for every file.
actor NotionImportWrittenFiles {
    /// How many written files make a batch.
    static let batchFileCount = 50
    private let deliver: @MainActor @Sendable ([GraphiteCore.VaultPath]) async -> Void
    private var pending: [GraphiteCore.VaultPath] = []

    init(deliver: @escaping @MainActor @Sendable ([GraphiteCore.VaultPath]) async -> Void) {
        self.deliver = deliver
    }

    func add(_ path: GraphiteCore.VaultPath) async {
        pending.append(path)
        if pending.count >= Self.batchFileCount { await deliverPending() }
    }

    /// Hands over the files written since the last batch, as the import ends.
    func deliverPending() async {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = []
        await deliver(batch)
    }
}
