/**
 * File: VaultStoreLargeFiles.swift
 * --------------------------------
 * Layer: Core
 * Description: Looking at a file of any size without holding it in memory: its size, its revision, and a run of its bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation

/// What a file's metadata says of its version, cheaply: a change of either means another version.
public struct FileStamp: Equatable, Sendable {
    public let size: Int
    public let modificationDate: Date?
}

public extension AtomicFileWriter {
    /// Runs `body` on `url` under a coordinated read.
    func readingCoordinated<Value>(_ url: URL, _ body: (URL) throws -> Value) throws -> Value {
        var coordinationError: NSError?
        var readResult: Result<Value, Error>?
        makeCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            readResult = Result { try body(location) }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw GraphiteError.unavailable("The file provider did not grant access.") }
        return try readResult.get()
    }
}

public extension VaultStore {
    /// The file's revision, hashed a megabyte at a time.
    func revision(of path: VaultPath) throws -> FileRevision {
        try writer.readingCoordinated(path.url(in: root)) { location in try FileRevision.read(location) }
    }

    /// The file's size and date, from its metadata alone.
    func fileStamp(of path: VaultPath) throws -> FileStamp {
        try writer.readingCoordinated(path.url(in: root)) { location in
            let values = try location.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return FileStamp(size: values.fileSize ?? 0, modificationDate: values.contentModificationDate)
        }
    }

    /// At most `count` bytes of the file from `offset`; fewer at its end.
    func readBytes(of path: VaultPath, at offset: Int, count: Int) throws -> Data {
        try writer.readingCoordinated(path.url(in: root)) { location in
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() } // Read only: nothing is left to flush.
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: count) ?? Data()
        }
    }
}
