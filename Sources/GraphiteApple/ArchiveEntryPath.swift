/**
 * File: ArchiveEntryPath.swift
 * ----------------------------
 * Layer: Apple
 * Description: Where a ZIP entry may be written inside the folder it is unpacked into, and which entries are skipped.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// The place a ZIP entry's name asks for, relative to the folder the archive is unpacked into. An archive is
/// untrusted: a name may try to leave the folder (`../../Library/x`, `/etc/x`, `C:\x`), so a name is taken apart
/// into folder names and refused when any of them climbs, when it is absolute, or when it holds a character no
/// file name may hold. The names of what the Finder and Windows add to an archive (a hidden file, `__MACOSX`'s
/// resource forks, `Thumbs.db`) are recognised so that they are skipped, not imported.
public enum ArchiveEntryPath {
    /// What an entry's name asks for.
    public enum Placement: Equatable, Sendable {
        /// A file at these folder names, the last the file's own name.
        case file([String])
        /// A folder entry (a name ending in `/`): folders are made for the files inside them, so it writes nothing.
        case folder
        /// Something the archiving app added that no one put there on purpose.
        case skipped
        /// A name that leaves the folder, or that no file name can hold.
        case refused
    }

    /// The folder Archive Utility fills with resource forks, beside the files themselves.
    private static let resourceForkFolderName = "__MACOSX"
    private static let systemFileNames: Set<String> = ["Thumbs.db", "desktop.ini", "Icon\r"]

    public static func placement(ofEntryNamed entryName: String) -> Placement {
        // Windows archivers write backslashes between folders.
        let unifiedName = entryName.replacingOccurrences(of: "\\", with: "/")
        guard !unifiedName.hasPrefix("/"), !unifiedName.contains("\0") else { return .refused }
        let components = unifiedName.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { component in component != "." }
        guard !components.isEmpty else { return unifiedName.isEmpty ? .refused : .folder }
        guard !components.contains("..") else { return .refused }
        // A drive letter (`C:`) makes the rest an absolute Windows path.
        guard let first = components.first, !(first.count == 2 && first.hasSuffix(":")) else { return .refused }
        if components.contains(where: { component in component.hasPrefix(".") || component == resourceForkFolderName })
            || systemFileNames.contains(components[components.count - 1]) {
            return .skipped
        }
        return unifiedName.hasSuffix("/") ? .folder : .file(components)
    }

    /// `components` under `folder`, or nil when, against every check above, it would not lie inside it.
    static func location(of components: [String], in folder: URL) -> URL? {
        let location = components.reduce(folder) { partial, component in partial.appendingPathComponent(component) }
        let folderPath = folder.standardizedFileURL.path
        let standardizedPath = location.standardizedFileURL.path
        return standardizedPath.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/") ? location : nil
    }
}
