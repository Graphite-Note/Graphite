/**
 * File: AtomicFileWriter.swift
 * ----------------------------
 * Layer: Core
 * Description: File revisions, and coordinated reads, whole-or-nothing writes and appends of the person's files, each
 *              write recorded on Graphite's own presenter so macOS's report of it is not taken for another app's change,
 *              and every new name written in Unicode's composed form (NFC).
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 28/11/2026
 */

import Foundation
import CryptoKit

public struct FileRevision: Codable, Equatable, Sendable {
    public let digest: String
    public let size: UInt64
    public static func of(_ data: Data) -> Self {
        Self(digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: UInt64(data.count))
    }
    public static func read(_ url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: UInt64 = 0
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            hash.update(data: bytes)
            size += UInt64(bytes.count)
        }
        return Self(digest: hash.finalize().map { String(format: "%02x", $0) }.joined(), size: size)
    }
}

public struct FileSnapshot: Sendable {
    public let data: Data
    public let revision: FileRevision
}

public enum WriteExpectation: Sendable { case absent, revision(FileRevision) }

/// What a write left at a file, read from its metadata without its contents: the file's
/// identifier, size and modification time. Another app's write changes at least one of them;
/// a replacement gives the file a new identifier.
public struct FileWriteFingerprint: Equatable, Sendable {
    let deviceIdentifier: Int64
    let fileIdentifier: UInt64
    let size: Int64
    let modificationSeconds: Int
    let modificationNanoseconds: Int

    /// The fingerprint of the file at `url` as it is now, or nil when nothing is there.
    public static func read(_ url: URL) -> FileWriteFingerprint? {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return nil }
        return FileWriteFingerprint(deviceIdentifier: Int64(status.st_dev), fileIdentifier: UInt64(status.st_ino), size: Int64(status.st_size),
                                    modificationSeconds: Int(status.st_mtimespec.tv_sec), modificationNanoseconds: Int(status.st_mtimespec.tv_nsec))
    }
}

/// A presenter told of each write made through a coordinator that names it. macOS does not
/// reliably keep a presenter's own coordinated writes from it: about a second later it may
/// report them as changes all the same (HUNT-368), so the presenter keeps what each write
/// left and lets a report go when the file still matches it.
public protocol OwnWriteRecording: AnyObject, Sendable {
    func recordOwnWrite(at url: URL)
}

/// All synchronous work belongs on a worker actor, never the main actor.
/// Revision comparison and replacement share one coordinated write accessor.
public struct AtomicFileWriter: Sendable {
    /// What a coordinated write throws when the file provider never runs it.
    private static let writeAccessRefused = GraphiteError.unavailable("The file provider did not grant write access.")

    /// Graphite's own vault presenter. Coordinating with it keeps Graphite's writes
    /// from being reported back to Graphite as external changes.
    private let filePresenter: (any NSFilePresenter & Sendable)?

    public init(filePresenter: (any NSFilePresenter & Sendable)? = nil) {
        self.filePresenter = filePresenter
    }

    public func makeCoordinator() -> NSFileCoordinator { NSFileCoordinator(filePresenter: filePresenter) }

    /// Tells Graphite's presenter what a write coordinated with it left at `location`.
    private func recordOwnWrite(at location: URL) {
        (filePresenter as? any OwnWriteRecording)?.recordOwnWrite(at: location)
    }

    /// Gives the file at `location` these dates. Importers mark each imported note with its source's
    /// time, and on importing again tell a note edited since (a later date) from one nothing has
    /// touched (the same date). Only the file's metadata changes, under coordination, so a sync
    /// provider sees a change of dates, not of contents.
    public func setFileTimes(modified: Date?, created: Date?, at location: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        if let modified { attributes[.modificationDate] = modified }
        if let created { attributes[.creationDate] = created }
        guard !attributes.isEmpty else { return }
        var coordinationError: NSError?
        var settingError: (any Error)?
        makeCoordinator().coordinate(writingItemAt: location, options: .contentIndependentMetadataOnly, error: &coordinationError) { coordinatedLocation in
            do {
                try FileManager.default.setAttributes(attributes, ofItemAtPath: coordinatedLocation.path)
                recordOwnWrite(at: coordinatedLocation)
            } catch {
                settingError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let settingError { throw settingError }
    }

    public func read(_ url: URL, maximumBytes: Int? = nil) throws -> FileSnapshot {
        try readingCoordinated(url) { location in
            if let maximumBytes {
                let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumBytes else { throw GraphiteError.oversized("This file exceeds the current editor's memory budget.") }
            }
            let data = try Data(contentsOf: location)
            return FileSnapshot(data: data, revision: FileRevision.of(data))
        }
    }

    /// Runs `body` on `url` under a coordinated read.
    public func readingCoordinated<Value>(_ url: URL, _ body: (URL) throws -> Value) throws -> Value {
        var coordinationError: NSError?
        var readResult: Result<Value, Error>?
        makeCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            readResult = Result { try body(location) }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw GraphiteError.unavailable("The file provider did not grant access.") }
        return try readResult.get()
    }

    /// Adds `data` at the end of the file at `url`, made empty first when nothing is there, under a coordinated
    /// write. Unlike `write`, the file is changed in place, so a file larger than memory can be written piece by
    /// piece: a reader may see it partly written, as with Obsidian's `appendBinary`.
    public func append(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var appendResult: Result<Void, Error>?
        makeCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { destination in
            appendResult = Result {
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try ComposedFileNames.createEmptyFile(at: destination)
                }
                let handle = try FileHandle(forWritingTo: destination)
                defer { try? handle.close() } // Closed below after a write; a failed write is already reported.
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
                recordOwnWrite(at: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let appendResult else { throw Self.writeAccessRefused }
        try appendResult.get()
    }

    @discardableResult
    public func write(_ data: Data, to url: URL, expecting: WriteExpectation) throws -> FileRevision {
        try replace(url, expecting: expecting) { staging in try data.write(to: staging) }
    }

    @discardableResult
    public func replace(_ url: URL, expecting: WriteExpectation, produce: (URL) throws -> Void) throws -> FileRevision {
        let stagingDirectory = Self.stagingDirectory(for: url)
        let staging = (stagingDirectory ?? url.deletingLastPathComponent()).appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: stagingDirectory ?? staging) }
        try produce(staging)
        try Self.flushBeforeLaterWrites(staging)
        let revision = try FileRevision.read(staging)
        var coordinationError: NSError?
        var replacementResult: Result<Void, Error>?
        makeCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            replacementResult = Result {
                let exists = FileManager.default.fileExists(atPath: destination.path)
                switch expecting {
                case .absent: guard !exists else { throw GraphiteError.conflict }
                case .revision(let previous):
                    guard exists, try FileRevision.read(destination) == previous else { throw GraphiteError.conflict }
                }
                if exists {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                } else {
                    try ComposedFileNames.moveItem(at: staging, to: destination)
                }
                Self.flushToPermanentStorage(directoryOf: destination)
                recordOwnWrite(at: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let replacementResult else { throw Self.writeAccessRefused }
        try replacementResult.get()
        return revision
    }

    /// A private folder on the destination's volume, so the staged file moves into place by
    /// renaming. Outside the vault, a staged file left by a crash or a terminated app never
    /// syncs to other devices, and it needs no coordination with the vault's file provider.
    /// Nil when the system offers none there (some network volumes); staging then falls
    /// back to a hidden file beside the destination.
    private static func stagingDirectory(for url: URL) -> URL? {
        try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
    }

    /// Orders the staged bytes before the rename that publishes them (`F_BARRIERFSYNC`), so
    /// after a power loss the destination holds the old or the new file, never a truncated
    /// one. Plain `fsync` leaves the data in the drive's cache on Apple platforms. File
    /// systems without barriers fall back to `fsync`. The file is opened for reading: both
    /// flushes work on any descriptor, and a copy of a read-only file keeps its permissions.
    private static func flushBeforeLaterWrites(_ staging: URL) throws {
        let handle = try FileHandle(forReadingFrom: staging)
        defer { try? handle.close() }
        if fcntl(handle.fileDescriptor, F_BARRIERFSYNC) == -1 { try handle.synchronize() }
    }

    /// Flushes the drive's cache after the rename (`F_FULLFSYNC` on the folder), so a save is
    /// on permanent storage when it is reported. It costs a few milliseconds per save, off
    /// the main thread. Best effort: the replacement has already happened, and a file system
    /// that cannot flush this way keeps the new file all the same.
    private static func flushToPermanentStorage(directoryOf location: URL) {
        let directoryDescriptor = open(location.deletingLastPathComponent().path, O_RDONLY)
        guard directoryDescriptor >= 0 else { return }
        _ = fcntl(directoryDescriptor, F_FULLFSYNC)
        close(directoryDescriptor)
    }
}

public extension AtomicFileWriter {
    /// Copies another file into place, reading the source under coordination too.
    @discardableResult
    func copy(from source: URL, to destination: URL, expecting: WriteExpectation) throws -> FileRevision {
        try replace(destination, expecting: expecting) { staging in
            var coordinationError: NSError?
            var copyResult: Result<Void, Error>?
            makeCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedSource in
                copyResult = Result { try FileManager.default.copyItem(at: coordinatedSource, to: staging) }
            }
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw GraphiteError.unavailable("Cannot read the file to copy.") }
            try copyResult.get()
        }
    }

    func createDirectory(at url: URL) throws {
        var coordinationError: NSError?
        var creationResult: Result<Void, Error>?
        makeCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { location in
            creationResult = Result {
                try ComposedFileNames.createDirectory(at: location)
                recordOwnWrite(at: location)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let creationResult else { throw GraphiteError.unavailable("The file provider did not allow creating the folder.") }
        try creationResult.get()
    }
}

/// Gives every name Graphite makes in the vault the composed spelling (NFC) on disk.
///
/// Foundation's file calls hand the system a URL's file-system representation, and Apple's
/// platforms decompose it: `Data.write(to:)`, `FileManager.moveItem`, `copyItem` and
/// `createDirectory` leave “Café” on disk as “Cafe” and a combining accent (U+0301). APFS
/// finds the file under either spelling, but tools that compare the bytes do not: git, Obsidian
/// on another system, sync to a file system that keeps both. POSIX calls given a Swift string
/// keep its bytes, so the names here go through `renamex_np`, `mkdir` and `open` with the path
/// composed.
///
/// Replacing a file that is already there keeps the name it has on disk, so a vault whose
/// files were written decomposed keeps them as they are; `VaultPath` composes the names it
/// reads, so links and the index find them all the same.
public enum ComposedFileNames {
    /// The path of `location` with its text composed. APFS and HFS+ look folders up in
    /// either form, so composing the folders above the new name changes nothing there.
    static func composedPath(of location: URL) -> String {
        location.path.precomposedStringWithCanonicalMapping
    }

    /// Whether the name of `location` reads differently composed and decomposed, the only
    /// names Foundation writes in the wrong form. A file URL already reports its name
    /// decomposed, so both forms are made from it.
    static func hasComposableName(_ location: URL) -> Bool {
        let name = location.lastPathComponent
        return !name.precomposedStringWithCanonicalMapping.utf8.elementsEqual(name.decomposedStringWithCanonicalMapping.utf8)
    }

    /// Moves `source` to `destination` in one rename, under the composed name. Never replaces
    /// another item: a change of capitals or of accents alone is allowed, since the volume sees
    /// the same item. Across volumes, or where the volume has no exclusive rename, Foundation
    /// moves it and the name is composed after.
    public static func moveItem(at source: URL, to destination: URL) throws {
        if renamex_np(source.path, composedPath(of: destination), UInt32(RENAME_EXCL)) == 0 { return }
        let renameFailure = errno
        guard renameFailure == EXDEV || renameFailure == ENOTSUP || renameFailure == EINVAL else {
            throw POSIXError(POSIXErrorCode(rawValue: renameFailure) ?? .EIO)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        composeName(at: destination)
    }

    /// Copies `source` to `destination` with Foundation, then composes the copy's name.
    /// A folder's contents keep the names they have on disk.
    public static func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
        composeName(at: destination)
    }

    /// Makes the folder at `location` and any missing folder above it, each under its composed
    /// name; nothing happens when the folder is there.
    public static func createDirectory(at location: URL) throws {
        var missingFolders: [URL] = []
        var folder = location.standardizedFileURL
        var isDirectory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            missingFolders.append(folder)
            let parent = folder.deletingLastPathComponent()
            guard parent.path != folder.path else { break }
            folder = parent
        }
        if missingFolders.isEmpty, !isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: location.path])
        }
        for missingFolder in missingFolders.reversed() where mkdir(composedPath(of: missingFolder), 0o777) != 0 {
            let creationFailure = errno
            // Made meanwhile by someone else: what was asked for is there.
            guard creationFailure == EEXIST, FileManager.default.fileExists(atPath: missingFolder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw POSIXError(POSIXErrorCode(rawValue: creationFailure) ?? .EIO)
            }
        }
    }

    /// Makes an empty file at `location` under its composed name; fails when something is there.
    public static func createEmptyFile(at location: URL) throws {
        let descriptor = open(composedPath(of: location), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        close(descriptor)
    }

    /// Renames the item Foundation just made at `location` to the composed spelling of its
    /// name. Best effort: the item is in place and found under either spelling, so a volume
    /// that refuses the rename leaves the name as Foundation wrote it.
    static func composeName(at location: URL) {
        guard hasComposableName(location) else { return }
        _ = renamex_np(location.path.decomposedStringWithCanonicalMapping, composedPath(of: location), UInt32(RENAME_EXCL))
    }
}
