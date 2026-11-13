/**
 * File: ZipArchiveUnpacking.swift
 * -------------------------------
 * Layer: Apple
 * Description: Unpacks a ZIP archive opened in Graphite into a temporary folder, keeping its folders, within limits that
 *              stop a zip bomb, and never writing outside that folder.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import NotebookImport

/// How much of an archive is unpacked at most. A ZIP declares each entry's size, and the reader never writes more than
/// it declares (`ZipArchive`), so these bounds, checked against the declarations before anything is written, hold for
/// whatever the archive's bytes really decode to.
public struct ArchiveUnpackingLimits: Sendable, Equatable {
    /// The most files written; an archive with more is refused whole.
    public var maximumFileCount: Int
    /// The most bytes written for all the files together; an archive that declares more is refused whole.
    public var maximumTotalBytes: Int
    /// The bound of one entry (`maximumEntryBytes`); a larger entry is left out and the others are unpacked.
    public var entryLimits: NotebookImportLimits

    public init(maximumFileCount: Int, maximumTotalBytes: Int, entryLimits: NotebookImportLimits) {
        self.maximumFileCount = maximumFileCount
        self.maximumTotalBytes = maximumTotalBytes
        self.entryLimits = entryLimits
    }

    /// 10,000 files, four times an entry's bound in all (2 GiB on the Mac, 1 GiB on the iPhone and iPad): a library
    /// export of notebooks is well within both.
    public static let standard = ArchiveUnpackingLimits(maximumFileCount: 10_000,
                                                        maximumTotalBytes: 4 * NotebookImportLimits.standard.maximumEntryBytes,
                                                        entryLimits: .standard)
}

/// Why an archive was not unpacked at all. Nothing of it is left in the folder.
public enum ArchiveUnpackingFailure: Error, Equatable, Sendable {
    /// The file could not be read.
    case unreadable
    /// The file is not a ZIP archive, or its end is cut off.
    case notAZipArchive
    /// Its directory of entries is damaged.
    case damaged
    /// It needs ZIP64 records (an archive over 4 GB or of more than 65,535 entries), which Graphite does not read.
    case needsZip64
    case tooManyFiles(count: Int, limit: Int)
    /// Its files declare more bytes in all than an archive may unpack to.
    case tooLarge(byteCount: Int, limitBytes: Int)
    /// The device has less free room than the files need.
    case notEnoughRoom(byteCount: Int)
}

/// An archive unpacked into a folder: its files, at their folders, and the entries that were not written.
public struct UnpackedArchive: Sendable, Equatable {
    public struct File: Sendable, Equatable {
        public let location: URL
        /// The folder names from the archive's top down to the file, then the file's name.
        public let pathComponents: [String]

        public init(location: URL, pathComponents: [String]) {
            self.location = location
            self.pathComponents = pathComponents
        }
    }

    /// An entry that is not among the files, and why; the rest of the archive was still unpacked.
    public struct LeftOutEntry: Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            /// Its name leads outside the archive's folder, or no file name can hold it.
            case pathOutsideArchive
            case encrypted
            case tooLarge(limitBytes: Int)
            case compressionNotSupported
            /// Its bytes are damaged.
            case damaged
            /// Another entry already took its name, or a folder of it (names differ only in capitals on most Macs).
            case nameTaken
            /// The device refused to write it, such as when it is full.
            case notWritten
        }

        public let name: String
        public let reason: Reason

        public init(name: String, reason: Reason) {
            self.name = name
            self.reason = reason
        }
    }

    public let folder: URL
    /// In the archive's order.
    public let files: [File]
    public let leftOutEntries: [LeftOutEntry]
}

/// Unpacks a ZIP archive into an empty folder, entry by entry, with the reader the notebook import already uses
/// (`ZipArchive`): the archive is memory-mapped and each entry is copied out in pieces, so neither is held whole.
/// What the Finder adds (resource forks, `.DS_Store`) is skipped. An entry whose name climbs out of the folder is
/// refused, so nothing is ever written outside it.
public enum ZipArchiveUnpacking {
    /// Unpacks `archive` into `folder`, which must exist and be empty. The archive is only read.
    public static func unpack(_ archive: URL, into folder: URL,
                              limits: ArchiveUnpackingLimits = .standard) throws(ArchiveUnpackingFailure) -> UnpackedArchive {
        let reader = try openedArchive(archive, limits: limits)
        var plannedFiles: [(entry: ZipArchive.Entry, components: [String])] = []
        var leftOutEntries: [UnpackedArchive.LeftOutEntry] = []
        var plannedNames = Set<String>()
        // Of two entries with one name the later is read, as `ZipArchive` and Python's `zipfile` read them.
        for entry in reader.entries.reversed() where plannedNames.insert(entry.name).inserted {
            switch ArchiveEntryPath.placement(ofEntryNamed: entry.name) {
            case .file(let components): plannedFiles.append((entry, components))
            case .refused: leftOutEntries.append(UnpackedArchive.LeftOutEntry(name: entry.name, reason: .pathOutsideArchive))
            case .folder, .skipped: continue
            }
        }
        plannedFiles.reverse()
        leftOutEntries.reverse()
        try checkSize(of: plannedFiles.map(\.entry), within: limits, in: folder)
        var files: [UnpackedArchive.File] = []
        for planned in plannedFiles {
            if let reason = write(planned.entry, of: reader, to: planned.components, in: folder) {
                leftOutEntries.append(UnpackedArchive.LeftOutEntry(name: planned.entry.name, reason: reason))
            } else if let location = ArchiveEntryPath.location(of: planned.components, in: folder) {
                files.append(UnpackedArchive.File(location: location, pathComponents: planned.components))
            }
        }
        return UnpackedArchive(folder: folder, files: files, leftOutEntries: leftOutEntries)
    }

    private static func openedArchive(_ archive: URL, limits: ArchiveUnpackingLimits) throws(ArchiveUnpackingFailure) -> ZipArchive {
        let bytes: Data
        do { bytes = try Data(contentsOf: archive, options: .alwaysMapped) } catch { throw .unreadable }
        do throws(ZipArchiveError) {
            return try ZipArchive(archiveBytes: bytes, limits: limits.entryLimits)
        } catch {
            switch error {
            case .endOfCentralDirectoryMissing: throw .notAZipArchive
            case .zip64NotSupported: throw .needsZip64
            case .centralDirectoryDamaged, .readOutsideArchive, .entryMissing, .entryEncrypted, .compressionMethodNotSupported, .entryTooLarge,
                 .compressionRatioImpossible, .entryDataOutsideArchive, .entryDataDamaged, .checksumMismatch: throw .damaged
            }
        }
    }

    /// Refuses the archive before anything is written when its files are too many or declare too many bytes. An entry
    /// over its own bound is left out later and not counted here.
    private static func checkSize(of entries: [ZipArchive.Entry], within limits: ArchiveUnpackingLimits,
                                  in folder: URL) throws(ArchiveUnpackingFailure) {
        guard entries.count <= limits.maximumFileCount else { throw .tooManyFiles(count: entries.count, limit: limits.maximumFileCount) }
        let byteCount = entries.filter { entry in entry.uncompressedByteCount <= limits.entryLimits.maximumEntryBytes }
            .reduce(0) { total, entry in total + entry.uncompressedByteCount }
        guard byteCount <= limits.maximumTotalBytes else { throw .tooLarge(byteCount: byteCount, limitBytes: limits.maximumTotalBytes) }
        let roomKey = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        let room = try? folder.resourceValues(forKeys: [roomKey]).volumeAvailableCapacityForImportantUsage // Unknown: written, failing per entry.
        if let room, room > 0, Int64(byteCount) > room { throw .notEnoughRoom(byteCount: byteCount) }
    }

    /// Writes one entry at its place, making its folders; nil when it was written, else why not. A file left half
    /// written by damage found at its end is removed.
    private static func write(_ entry: ZipArchive.Entry, of reader: ZipArchive, to components: [String],
                              in folder: URL) -> UnpackedArchive.LeftOutEntry.Reason? {
        guard let location = ArchiveEntryPath.location(of: components, in: folder) else { return .pathOutsideArchive }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: location.path) else { return .nameTaken }
        do {
            try fileManager.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            // A file already holds the name of one of its folders.
            return .nameTaken
        }
        guard fileManager.createFile(atPath: location.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: location) else { return .notWritten } // Why does not change the answer.
        let reason: UnpackedArchive.LeftOutEntry.Reason?
        do throws(ZipEntryCopyError<any Error>) {
            try reader.copy(entry) { (piece: UnsafeRawBufferPointer) throws(any Error) in try handle.write(contentsOf: piece) }
            reason = nil
        } catch {
            switch error {
            case .archive(let archiveError): reason = Self.reason(for: archiveError)
            case .destination: reason = .notWritten
            }
        }
        try? handle.close() // Every piece was handed over already; a close that fails loses nothing written.
        if reason != nil { try? fileManager.removeItem(at: location) } // A leftover piece is in a temporary folder the caller removes.
        return reason
    }

    private static func reason(for error: ZipArchiveError) -> UnpackedArchive.LeftOutEntry.Reason {
        switch error {
        case .entryEncrypted: .encrypted
        case .entryTooLarge(_, let limitBytes): .tooLarge(limitBytes: limitBytes)
        case .compressionMethodNotSupported: .compressionNotSupported
        case .endOfCentralDirectoryMissing, .zip64NotSupported, .centralDirectoryDamaged, .entryMissing, .compressionRatioImpossible,
             .entryDataOutsideArchive, .entryDataDamaged, .checksumMismatch, .readOutsideArchive: .damaged
        }
    }
}
