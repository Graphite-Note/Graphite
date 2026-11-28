/**
 * File: VaultStore.swift
 * ----------------------
 * Layer: Core
 * Description: The vault's folder on disk: reading, saving, moving, copying and deleting its files. Its Obsidian settings
 *              files are in VaultStoreObsidianSettings.swift.
 *
 * Authors: Bahey Shalash
 * Version: 0.13
 * Date: 28/11/2026
 */

import Foundation
import Synchronization

public struct VaultEntry: Sendable, Identifiable, Hashable {
    public var id: VaultPath { path }
    public let path: VaultPath
    public let isDirectory: Bool
    public let size: Int
    public let modified: Date
    /// The modification date when the file system does not record creation.
    public let created: Date
    public var kind: DocumentKind { DocumentKind(path: path) }
    public init(path: VaultPath, isDirectory: Bool, size: Int, modified: Date, created: Date? = nil) {
        self.path = path; self.isDirectory = isDirectory; self.size = size; self.modified = modified; self.created = created ?? modified
    }
}

/// Obsidian's "Deleted files" setting (`trashOption` in `.obsidian/app.json`).
public enum DeletionMethod: String, CaseIterable, Identifiable, Sendable {
    /// Move to the system's trash (`system`), Obsidian's default.
    case systemTrash = "system"
    /// Move to the vault's own `.trash` folder (`local`).
    case vaultTrash = "local"
    /// Delete for good (`none`).
    case permanent = "none"
    public var id: String { rawValue }
}

public enum DeletionOutcome: Equatable, Sendable {
    case movedToSystemTrash
    case movedToVaultTrash(VaultPath)
    case deleted
}

/// Names Graphite accepts for new and renamed files, following Obsidian's rules.
public enum FileNameRules {
    /// Characters no file name may contain on the platforms a vault syncs to.
    static let forbiddenCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
    /// Characters that would break links to a note (`[[Name#Heading]]`, `[[Name|alias]]`).
    static let linkBreakingCharacters = CharacterSet(charactersIn: "#^[]|")
    /// Line breaks, tabs and the other C0 and C1 control characters. No link syntax can
    /// contain a line break, and none of them can be typed into a name field on purpose.
    /// Format characters such as the zero-width joiner in emoji stay allowed.
    static let controlCharacters = CharacterSet(charactersIn: "\u{0}"..."\u{1F}")
        .union(CharacterSet(charactersIn: "\u{7F}"..."\u{9F}"))
        .union(.newlines)
    /// The longest file name Apple file systems store, in UTF-8 bytes.
    static let maximumFileNameBytes = 255
    /// Room kept for what Graphite adds to a typed name: an extension of up to eight
    /// characters (".md", ".base", ".markdown") and a number that tells it from an
    /// existing file (" 100000" at most).
    static let reservedSuffixBytes = 16
    /// What the name of a copy of edits that could not be saved adds to the file's own.
    static let separateCopySuffix = " Graphite edits"

    /// The stem of a copy of a file's edits: the file's own, shortened when it would otherwise
    /// make a name no file system stores, as a name that is already the longest allowed would.
    public static func separateCopyStem(of stem: String) -> String {
        let maximumStemBytes = maximumFileNameBytes - reservedSuffixBytes - separateCopySuffix.utf8.count
        var shortenedStem = stem
        while shortenedStem.utf8.count > maximumStemBytes { shortenedStem.removeLast() }
        return shortenedStem + separateCopySuffix
    }

    /// Why `name` cannot be used, or nil when it can.
    public static func problem(with name: String, isNote: Bool) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "Enter a name." }
        if trimmedName.hasPrefix(".") { return "A name cannot start with a dot, or the file would be hidden." }
        if trimmedName.rangeOfCharacter(from: forbiddenCharacters) != nil { return "A name cannot contain any of these characters: / \\ : * ? \" < > |" }
        if trimmedName.rangeOfCharacter(from: controlCharacters) != nil { return "A name cannot contain line breaks or tabs." }
        if isNote, trimmedName.rangeOfCharacter(from: linkBreakingCharacters) != nil { return "A note's name cannot contain # ^ [ ] or |, which would break links to it." }
        if trimmedName.utf8.count > maximumFileNameBytes - reservedSuffixBytes { return "The name is too long." }
        return nil
    }
}

/// Why edits that could not be saved did not go to a copy.
public enum SeparateCopyRefusal: LocalizedError, Equatable {
    case vaultFolderIsGone(fileName: String)
    /// A drawing can only be saved as a new file when it has a file already.
    case drawingHasNoFile
    /// A PDF's edits cannot be left behind by choosing a version; it has its own Save a Copy.
    case pdfHasUnsavedEdits(fileName: String)

    public var errorDescription: String? {
        switch self {
        case .vaultFolderIsGone(let fileName): "The vault's folder is no longer where it was, so a copy cannot be written beside “\(fileName)”."
        case .drawingHasNoFile: "This drawing cannot be saved as a new file."
        case .pdfHasUnsavedEdits(let fileName): "“\(fileName)” has edits that could not be saved. Use Save a Copy in its banner first, then choose a version."
        }
    }
}

public actor VaultStore {
    public nonisolated let root: URL
    public nonisolated let writer: AtomicFileWriter
    nonisolated let directoryListings = Mutex(0)
    /// The Obsidian settings Graphite last read or saved, which a save without an explicit
    /// starting point compares against: only the keys that differ are written, so a key
    /// Obsidian changed since then keeps its new value. Read and written by `VaultStoreObsidianSettings.swift` alone.
    var settingsBaseline: ObsidianSettings?
    /// The appearance settings Graphite last read or saved, as `settingsBaseline` is for `app.json`.
    var appearanceBaseline: ObsidianAppearance?

    public init(root: URL, filePresenter: (any NSFilePresenter & Sendable)? = nil) {
        self.root = root
        writer = AtomicFileWriter(filePresenter: filePresenter)
    }

    public func read(_ path: VaultPath, maximumBytes: Int? = nil) throws -> FileSnapshot {
        try writer.read(path.url(in: root), maximumBytes: maximumBytes)
    }

    public func save(_ data: Data, at path: VaultPath, expecting: WriteExpectation) throws -> FileRevision {
        try writer.write(data, to: path.url(in: root), expecting: expecting)
    }

    /// Adds `data` at the end of the file at `path`, in place (`AtomicFileWriter.append`).
    public func append(_ data: Data, at path: VaultPath) throws {
        try writer.append(data, to: path.url(in: root))
    }

    public func fileExists(_ path: VaultPath) throws -> Bool {
        FileManager.default.fileExists(atPath: try path.url(in: root).path)
    }

    /// Whether a file, not a folder, is at `path`: what a link names.
    public func regularFileExists(_ path: VaultPath) throws -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: try path.url(in: root).path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    public func createDirectory(_ path: VaultPath) throws {
        let url = try path.url(in: root)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try writer.createDirectory(at: url)
    }

    // MARK: File management

    /// Moves or renames a file or folder. Never replaces another item; a change of
    /// capitals alone is allowed, since case-insensitive volumes see the same item.
    /// The move waits for whoever presents the file off the actor: a file provider that takes
    /// long, or never answers, must not hold back every read and save of the vault behind it.
    public func move(_ path: VaultPath, to destination: VaultPath) async throws {
        let (sourceLocation, destinationLocation) = try locationsOfMove(path, to: destination)
        let writer = writer
        try await Task.detached(priority: .userInitiated) {
            try Self.coordinateMove(from: sourceLocation, to: destinationLocation, writer: writer)
        }.value
    }

    /// A move of a small item of the vault's own, in one step with what is around it on the actor.
    func moveOnActor(_ path: VaultPath, to destination: VaultPath) throws {
        let (sourceLocation, destinationLocation) = try locationsOfMove(path, to: destination)
        try Self.coordinateMove(from: sourceLocation, to: destinationLocation, writer: writer)
    }

    /// Where `path` is and where it goes, once nothing rules the move out; the destination's folder is made.
    private func locationsOfMove(_ path: VaultPath, to destination: VaultPath) throws -> (source: URL, destination: URL) {
        guard !path.rawValue.isEmpty, !destination.rawValue.isEmpty else { throw GraphiteError.invalidPath(path.rawValue) }
        guard !destination.isInside(path) || destination == path else { throw GraphiteError.unavailable("A folder cannot be moved into itself.") }
        let sourceLocation = try path.url(in: root)
        let destinationLocation = try destination.url(in: root)
        guard FileManager.default.fileExists(atPath: sourceLocation.path) else { throw GraphiteError.unavailable("“\(path.name)” is no longer in the vault.") }
        // The path check above compares names exactly. On a case-insensitive volume `a/B`
        // is inside `A` too, so the destination's existing folders are compared by identity.
        var destinationAncestor = destination.parent
        while destinationAncestor != .root {
            if Self.isSameItem(sourceLocation, try destinationAncestor.url(in: root)) { throw GraphiteError.unavailable("A folder cannot be moved into itself.") }
            destinationAncestor = destinationAncestor.parent
        }
        if FileManager.default.fileExists(atPath: destinationLocation.path), !Self.isSameItem(sourceLocation, destinationLocation) {
            throw GraphiteError.unavailable("“\(destination.rawValue)” already exists.")
        }
        try createDirectory(destination.parent)
        return (sourceLocation, destinationLocation)
    }

    private static func coordinateMove(from sourceLocation: URL, to destinationLocation: URL, writer: AtomicFileWriter) throws {
        let coordinator = writer.makeCoordinator()
        var coordinationError: NSError?
        var moveResult: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: sourceLocation, options: .forMoving, writingItemAt: destinationLocation, options: .forReplacing, error: &coordinationError) { coordinatedSource, coordinatedDestination in
            moveResult = Result {
                coordinator.item(at: coordinatedSource, willMoveTo: coordinatedDestination)
                try ComposedFileNames.moveItem(at: coordinatedSource, to: coordinatedDestination)
                coordinator.item(at: coordinatedSource, didMoveTo: coordinatedDestination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let moveResult else { throw GraphiteError.unavailable("The file provider did not allow the move.") }
        try moveResult.get()
    }

    private static func isSameItem(_ firstLocation: URL, _ secondLocation: URL) -> Bool {
        guard let firstIdentifier = try? firstLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let secondIdentifier = try? secondLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return false }
        return firstIdentifier.isEqual(secondIdentifier)
    }

    /// Creates an empty folder; fails if something already has that name.
    public func createFolder(named name: String, in directory: VaultPath) throws -> VaultPath {
        if let problem = FileNameRules.problem(with: name, isNote: false) { throw GraphiteError.unavailable(problem) }
        let path = try directory.appending(name.trimmingCharacters(in: .whitespaces))
        guard !FileManager.default.fileExists(atPath: try path.url(in: root).path) else { throw GraphiteError.unavailable("“\(path.name)” already exists.") }
        try createDirectory(path)
        return path
    }

    /// Removes a file or folder the way the vault's "Deleted files" setting says.
    public func delete(_ path: VaultPath, method: DeletionMethod) throws -> DeletionOutcome {
        guard !path.rawValue.isEmpty else { throw GraphiteError.invalidPath(path.rawValue) }
        let location = try path.url(in: root)
        guard FileManager.default.fileExists(atPath: location.path) else { throw GraphiteError.unavailable("“\(path.name)” is no longer in the vault.") }
        switch method {
        case .systemTrash:
            do {
                // A coordinated deletion first asks other apps and file providers presenting
                // the item to save and let go of it; `trashItem` does not tell them on macOS.
                // The call stays outside that accessor: on iPadOS `trashItem` coordinates the
                // move itself, and nesting it inside a coordinated write of the same item
                // deadlocked the vault's file actor.
                try coordinateDeletion(at: location) { _ in }
                try FileManager.default.trashItem(at: location, resultingItemURL: nil)
                return .movedToSystemTrash
            } catch {
                // Some file providers have no trash; the vault's own trash keeps the file safe.
                return .movedToVaultTrash(try moveToVaultTrash(path))
            }
        case .vaultTrash:
            return .movedToVaultTrash(try moveToVaultTrash(path))
        case .permanent:
            try coordinateDeletion(at: location) { coordinatedLocation in try FileManager.default.removeItem(at: coordinatedLocation) }
            return .deleted
        }
    }

    /// Obsidian's `.trash` folder at the vault's root.
    private func moveToVaultTrash(_ path: VaultPath) throws -> VaultPath {
        let trashDirectory = try VaultPath(".trash")
        try createDirectory(trashDirectory)
        let location = try path.url(in: root)
        let isDirectory = (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let trashedPath = try availablePath(in: trashDirectory, stem: isDirectory ? path.name : path.stem,
                                            extension: isDirectory ? "" : (path.name as NSString).pathExtension, firstSuffix: nil)
        try moveOnActor(path, to: trashedPath)
        return trashedPath
    }

    private func coordinateDeletion(at location: URL, _ deletion: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var deletionResult: Result<Void, Error>?
        writer.makeCoordinator().coordinate(writingItemAt: location, options: .forDeleting, error: &coordinationError) { coordinatedLocation in
            deletionResult = Result { try deletion(coordinatedLocation) }
        }
        if let coordinationError { throw coordinationError }
        guard let deletionResult else { throw GraphiteError.unavailable("The file provider did not allow the deletion.") }
        try deletionResult.get()
    }

    /// "Name.md", else "Name 1.md", "Name 2.md"… (or starting at `firstSuffix`).
    private func availablePath(in directory: VaultPath, stem: String, extension fileExtension: String, firstSuffix: Int?) throws -> VaultPath {
        func name(_ suffix: Int?) -> String {
            let base = stem + (suffix.map { number in " \(number)" } ?? "")
            return fileExtension.isEmpty ? base : base + "." + fileExtension
        }
        func isAvailable(_ path: VaultPath) throws -> Bool { !FileManager.default.fileExists(atPath: try path.url(in: root).path) }
        if firstSuffix == nil {
            let path = try directory.appending(name(nil))
            if try isAvailable(path) { return path }
        }
        for suffix in max(firstSuffix ?? 1, 1)...100_000 {
            let path = try directory.appending(name(suffix))
            if try isAvailable(path) { return path }
        }
        throw GraphiteError.unavailable("Choose another name.")
    }

    /// Copies a file or folder beside itself as "Name 1", like Obsidian's "Make a copy".
    public func duplicate(_ path: VaultPath) async throws -> VaultPath {
        let sourceLocation = try path.url(in: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceLocation.path, isDirectory: &isDirectory) else { throw GraphiteError.unavailable("“\(path.name)” is no longer in the vault.") }
        let copyPath = try availablePath(in: path.parent, stem: isDirectory.boolValue ? path.name : path.stem,
                                         extension: isDirectory.boolValue ? "" : (path.name as NSString).pathExtension, firstSuffix: 1)
        let copyLocation = try copyPath.url(in: root)
        // Off the actor: a copy of gigabytes must not hold back every save waiting behind it.
        let writer = writer
        let isFolder = isDirectory.boolValue
        try await Task.detached(priority: .userInitiated) {
            guard isFolder else {
                try writer.copy(from: sourceLocation, to: copyLocation, expecting: .absent)
                return
            }
            var coordinationError: NSError?
            var copyResult: Result<Void, Error>?
            writer.makeCoordinator().coordinate(readingItemAt: sourceLocation, options: [], writingItemAt: copyLocation, options: .forReplacing, error: &coordinationError) { coordinatedSource, coordinatedCopy in
                copyResult = Result { try ComposedFileNames.copyItem(at: coordinatedSource, to: coordinatedCopy) }
            }
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw GraphiteError.unavailable("The file provider did not allow the copy.") }
            try copyResult.get()
        }.value
        return copyPath
    }

    /// A free path beside `path` for edits that could not be saved into it. Its folder is made
    /// again when another app renamed or removed it, so the copy always has a place. The vault's
    /// own folder is not: one that moved would come back empty beside the real one.
    public func separateCopyPath(of path: VaultPath, fileExtension: String) throws -> VaultPath {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw SeparateCopyRefusal.vaultFolderIsGone(fileName: path.name)
        }
        try createDirectory(path.parent)
        return try uniquePath(directory: path.parent, stem: FileNameRules.separateCopyStem(of: path.stem), extension: fileExtension)
    }

    /// "Name.ext", else "Name 1.ext", "Name 2.ext"…, the names Obsidian gives new files.
    /// A file without an extension gets no trailing dot, and leading dots are dropped from
    /// the stem, since a hidden file would vanish from Files and the sidebar while a note
    /// still embeds it (an imported `.env` becomes `env`).
    public func uniquePath(directory: VaultPath, stem: String, extension fileExtension: String) throws -> VaultPath {
        let trimmedStem = String(stem.trimmingCharacters(in: .whitespacesAndNewlines).drop { character in character == "." })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStem.isEmpty, !trimmedStem.contains("/"), !trimmedStem.contains("\\"), !trimmedStem.contains("\n") else { throw GraphiteError.invalidPath(stem) }
        return try availablePath(in: directory, stem: trimmedStem, extension: fileExtension, firstSuffix: nil)
    }
}

/// Reads one folder of the vault, as `VaultStore.children` lists it.
enum VaultFolderReader {
    static func children(of directory: VaultPath, in root: URL, sortedBy sortOrder: FileSortOrder) throws -> [VaultEntry] {
        let url = try directory.url(in: root)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let entries = children.compactMap { child -> VaultEntry? in
            // One child that vanished since the listing, or that has a name no vault path
            // can hold, is left out instead of failing the whole folder.
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                  let childPath = try? directory.appending(child.lastPathComponent) else { return nil }
            return VaultEntry(path: childPath, isDirectory: values.isDirectory == true, size: values.fileSize ?? 0,
                              modified: values.contentModificationDate ?? .distantPast, created: values.creationDate)
        }
        return sortOrder.sorted(entries)
    }

    /// The folders in `directory` as Obsidian lists a configuration folder (`.obsidian/plugins`):
    /// every one whose name does not start with a dot, sorted by name. Not as `children` lists
    /// a folder, which also leaves out items macOS marks hidden (`UF_HIDDEN`): in a vault iCloud
    /// Drive syncs everything inside `.obsidian` can carry that mark, and then no plugin was
    /// listed (HUNT-322). Symbolic links stay out.
    static func foldersAsObsidianListsThem(in directory: VaultPath, root: URL) throws -> [VaultPath] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url(in: root).path)
        return names.filter { name in !name.hasPrefix(".") }.compactMap { name -> VaultPath? in
            guard let path = try? directory.appending(name), // A name no vault path can hold is left out.
                  let values = try? root.appendingPathComponent(path.rawValue).resourceValues(forKeys: keys), // Gone since the listing: left out.
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return path
        }.sorted { firstPath, secondPath in firstPath.rawValue < secondPath.rawValue }
    }
}
