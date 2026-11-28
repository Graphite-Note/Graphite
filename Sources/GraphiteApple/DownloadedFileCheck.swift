/**
 * File: DownloadedFileCheck.swift
 * -------------------------------
 * Layer: Apple
 * Description: A file's size and SHA-256 checked against the ones asked for, and a file's SHA-256 read in chunks.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

import Foundation
import CryptoKit

/// Whether a downloaded file is the one that was asked for: the right size and the right
/// SHA-256. Read Aloud's voices and add-on packs both check their files with it.
public enum DownloadedFileCheck {
    /// Reads the file in chunks of a megabyte, so a large file is never held in memory whole.
    public static func matches(_ fileURL: URL, byteCount: Int64, sha256: String) -> Bool {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == byteCount else { return false }
        return Self.sha256(of: fileURL) == sha256.lowercased()
    }

    /// The SHA-256 of a file's bytes in lowercase hexadecimal, read a megabyte at a time; nil when it cannot be read.
    public static func sha256(of fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1_024 * 1_024) ?? Data() } catch { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { byte in String(format: "%02x", byte) }.joined()
    }
}
