/**
 * File: OpenedFileStaging.swift
 * -----------------------------
 * Layer: Apple
 * Description: Keeps a copy of a file another app opened in Graphite, and clears the copy iOS left in the app's Inbox.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// A file opened in Graphite from another app (the share sheet's Open in, Files, AirDrop, the Finder's Open With or a
/// drop on the Dock icon) is copied at once into a staging folder of its own (`DroppedFileStaging`), before the vault it
/// goes into is even open: the system's permission to read it, and the file itself, may not last.
///
/// iOS hands Graphite either the original, readable while its security scope is held (Files, opening in place), or a
/// copy it put in `Documents/Inbox` (another app's share sheet, AirDrop). Graphite's Documents folder is the one Files
/// shows as On My iPad › Graphite, beside the vaults kept there, so the Inbox copy is removed once staged, and the Inbox
/// itself when it is empty. An original elsewhere is only read.
public enum OpenedFileStaging {
    /// Copies `file` into a new staging folder; see `DroppedFileStaging.stage`. The read is coordinated, so a file
    /// provider first downloads a file that is not on the device.
    /// - Parameter inboxFolder: Where iOS leaves the copies it hands over (`inboxFolder()`); a file inside it is removed
    ///   once copied.
    public static func stage(_ file: URL, inboxFolder: URL?) throws -> (copy: URL, folder: URL) {
        let hasAccess = file.startAccessingSecurityScopedResource()
        defer { if hasAccess { file.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var staged: Result<(copy: URL, folder: URL), any Error>?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [.withoutChanges], error: &coordinationError) { coordinatedFile in
            staged = Result { try DroppedFileStaging.stage(coordinatedFile, namedAfter: file.lastPathComponent) }
        }
        if let coordinationError { throw coordinationError }
        guard let staged else { throw CocoaError(.fileReadUnknown) }
        let copy = try staged.get()
        if let inboxFolder, isInside(file, folder: inboxFolder) { removeHandedOverCopy(file, inboxFolder: inboxFolder) }
        return copy
    }

    /// The folder iOS copies handed-over files into: `Inbox` in the app's Documents folder.
    public static func inboxFolder() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Whether `file` lies inside `folder`, at any depth.
    public static func isInside(_ file: URL, folder: URL) -> Bool {
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    private static func removeHandedOverCopy(_ file: URL, inboxFolder: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: file) // A copy that stays is only clutter in the Inbox, which iOS may clear itself.
        let remaining = try? fileManager.contentsOfDirectory(atPath: inboxFolder.path) // Unlisted: the Inbox stays.
        if remaining?.isEmpty == true { try? fileManager.removeItem(at: inboxFolder) } // iOS makes it again when it needs it.
    }
}
