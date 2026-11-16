/**
 * File: StoredZipArchive.swift
 * ----------------------------
 * Layer: Tests
 * Description: Writes small ZIP archives of stored entries for the tests of opening and unpacking archives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import zlib

/// Writes a ZIP archive whose entries are stored, not compressed, with any names, including the hostile ones the
/// unpacking must refuse (`../outside.md`, `/absolute.md`). Uncompressed entries keep the writer small; the reader's
/// deflate path is the NotebookImport package's own tests' concern (`ZipArchiveTests`).
public enum StoredZipArchive {
    /// The archive of `entries`, in order: each a name and its bytes; a name ending in `/` is a folder entry.
    public static func bytes(of entries: [(name: String, contents: Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let checksum = entry.contents.withUnsafeBytes { buffer in
                UInt32(crc32(0, buffer.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(buffer.count)))
            }
            let localHeaderOffset = UInt32(archive.count)
            // The fields both headers share: version needed, flags, method (0, stored), time and date, CRC-32 and sizes.
            var shared = Data()
            append(UInt16(20), to: &shared)
            append(UInt16(0), to: &shared)
            append(UInt16(0), to: &shared)
            append(UInt32(0), to: &shared)
            append(checksum, to: &shared)
            append(UInt32(entry.contents.count), to: &shared)
            append(UInt32(entry.contents.count), to: &shared)
            append(UInt16(nameBytes.count), to: &shared)
            append(UInt16(0), to: &shared)
            append(UInt32(0x0403_4B50), to: &archive)
            archive += shared + nameBytes + entry.contents
            append(UInt32(0x0201_4B50), to: &centralDirectory)
            append(UInt16(20), to: &centralDirectory)
            centralDirectory += shared
            // Comment length, disk, internal and external attributes, then where the local header is.
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt32(0), to: &centralDirectory)
            append(localHeaderOffset, to: &centralDirectory)
            centralDirectory += nameBytes
        }
        let directoryOffset = UInt32(archive.count)
        archive += centralDirectory
        append(UInt32(0x0605_4B50), to: &archive)
        append(UInt16(0), to: &archive)
        append(UInt16(0), to: &archive)
        append(UInt16(entries.count), to: &archive)
        append(UInt16(entries.count), to: &archive)
        append(UInt32(centralDirectory.count), to: &archive)
        append(directoryOffset, to: &archive)
        append(UInt16(0), to: &archive)
        return archive
    }

    /// Writes the archive of `entries` to `location`.
    public static func write(_ entries: [(name: String, contents: Data)], to location: URL) throws {
        try bytes(of: entries).write(to: location)
    }

    private static func append<Number: FixedWidthInteger>(_ number: Number, to data: inout Data) {
        withUnsafeBytes(of: number.littleEndian) { bytes in data.append(contentsOf: bytes) }
    }
}
