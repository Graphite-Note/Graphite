/**
 * File: VaultIndexRecovery.swift
 * ------------------------------
 * Layer: Index
 * Description: Opening the index database, and making it again when it is damaged.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GRDB

extension VaultIndex {
    /// The index at `databaseURL`. A database that cannot be used because it is damaged (not a
    /// database, malformed, or half-migrated) is deleted with its journal files and made again:
    /// it is a cache of the vault, and the next scan fills it, so it must not lock the vault out.
    /// Anything else (another process holding the lock, a full disk, no permission) is thrown
    /// with the file untouched.
    public static func openRebuildingIfDamaged(databaseURL: URL, cloudFileStatus: CloudFileStatus = .live) throws -> VaultIndex {
        do {
            return try VaultIndex(databaseURL: databaseURL, cloudFileStatus: cloudFileStatus)
        } catch let error where isDamagedDatabase(error) {
            for suffix in ["", "-wal", "-shm"] {
                let location = URL(fileURLWithPath: databaseURL.path + suffix)
                guard FileManager.default.fileExists(atPath: location.path) else { continue }
                try FileManager.default.removeItem(at: location)
            }
            return try VaultIndex(databaseURL: databaseURL, cloudFileStatus: cloudFileStatus)
        }
    }

    /// Whether opening failed because of what is in the file, which a new file cures, and not
    /// because of the moment or the machine (a lock, no space, no permission), which it does not.
    static func isDamagedDatabase(_ error: any Error) -> Bool {
        guard let databaseError = error as? DatabaseError else { return false }
        switch databaseError.resultCode {
        case .SQLITE_NOTADB, .SQLITE_CORRUPT, .SQLITE_ERROR, .SQLITE_CONSTRAINT: return true
        default: return false
        }
    }
}
