/**
 * File: GuideVaultCopyUpdate.swift
 * --------------------------------
 * Layer: UI
 * Description: Brings the reader's copy of the Graphite Guide vault up to a newer pack without losing what they wrote.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// The reader's copy of the Guide (`GuideVaultCopy`) was made from one pack; the app now pins a newer one. The update
/// tells the Guide's own files from the reader's by their SHA-256: a file whose bytes are the ones the pack has now, or
/// the ones an earlier pack had for that path (`earlierFiles`), was never changed by the reader (Docs/Guide-vault-todo.md,
/// section 7).
///
/// - A file new in the pack is added. A file the reader deleted from the copy is not brought back.
/// - An unchanged file the pack changed is replaced; an unchanged file the pack no longer has is removed.
/// - A note the reader changed is kept, and the pack's version is written beside it ("Name (Guide update).md").
/// - The reader's own files, and settings in `.obsidian` the reader changed, are left as they are.
struct GuideVaultCopyUpdate {
    /// What the update did to one file of the copy.
    enum Change: Equatable {
        case added
        case replaced
        case removed
        /// The reader's version kept; the pack's version written at `besidePath`, relative to the copy.
        case keptWithNewVersionBeside(besidePath: String)
        /// A setting of the vault the reader changed, kept without a second version.
        case keptReadersSetting
    }

    /// The pack's folder, with its files at their paths.
    let packFolder: URL
    /// The reader's copy.
    let copyFolder: URL
    /// The files of the pack the app pins now.
    let files: [AddOnFile]
    /// Files of the packs pinned before, at a path and with bytes the current pack does not have.
    let earlierFiles: [AddOnFile]
    /// The names of the files of the pack the copy was made from or last brought up to, or nil for a copy made before
    /// they were recorded: then every file missing from the copy counts as new.
    let previousFileNames: Set<String>?

    static let settingsFolderPrefix = ".obsidian/"
    static let besideSuffix = " (Guide update)"

    /// Applies the update, file by file in the order of their paths, and returns what changed. A file that cannot be
    /// written stops the update with its error; what was done before stays, and running it again finishes it.
    func apply() throws -> [String: Change] {
        let fileManager = FileManager.default
        var changes: [String: Change] = [:]
        let knownHashesByPath = Dictionary(grouping: files + earlierFiles, by: \.name).mapValues { versions in Set(versions.map(\.sha256)) }
        for file in files.sorted(by: { first, second in first.name < second.name }) {
            let destination = copyFolder.appendingPathComponent(file.name)
            guard fileManager.fileExists(atPath: destination.path) else {
                if previousFileNames?.contains(file.name) != true {
                    try place(file, at: destination)
                    changes[file.name] = .added
                }
                continue
            }
            guard let currentHash = DownloadedFileCheck.sha256(of: destination), currentHash != file.sha256 else { continue }
            if knownHashesByPath[file.name]?.contains(currentHash) == true {
                try place(file, at: destination)
                changes[file.name] = .replaced
            } else if file.name.hasPrefix(Self.settingsFolderPrefix) {
                changes[file.name] = .keptReadersSetting
            } else {
                changes[file.name] = .keptWithNewVersionBeside(besidePath: try placeBeside(file))
            }
        }
        let currentNames = Set(files.map(\.name))
        for earlier in earlierFiles where !currentNames.contains(earlier.name) && changes[earlier.name] == nil {
            let location = copyFolder.appendingPathComponent(earlier.name)
            guard DownloadedFileCheck.sha256(of: location) == earlier.sha256 else { continue }
            try fileManager.removeItem(at: location)
            changes[earlier.name] = .removed
        }
        return changes
    }

    /// Copies the pack's file over `destination` in one step: written beside it first, then swapped in.
    private func place(_ file: AddOnFile, at destination: URL) throws {
        let fileManager = FileManager.default
        let source = packFolder.appendingPathComponent(file.name)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: destination.path) else { return try fileManager.copyItem(at: source, to: destination) }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).guide-update")
        try fileManager.copyItem(at: source, to: staging)
        do {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } catch {
            try? fileManager.removeItem(at: staging) // best effort: the reader's file stays as it was
            throw error
        }
    }

    /// Writes the pack's version beside the reader's note under the first free "(Guide update)" name, or finds it
    /// already there from an earlier, interrupted run. Returns its path relative to the copy.
    private func placeBeside(_ file: AddOnFile) throws -> String {
        let path = file.name as NSString
        let folder = path.deletingLastPathComponent, stem = (path.lastPathComponent as NSString).deletingPathExtension
        let fileExtension = path.pathExtension.isEmpty ? "" : "." + path.pathExtension
        var number = 1
        while true {
            let name = stem + Self.besideSuffix + (number == 1 ? "" : " \(number)") + fileExtension
            let besidePath = folder.isEmpty ? name : folder + "/" + name
            let location = copyFolder.appendingPathComponent(besidePath)
            if !FileManager.default.fileExists(atPath: location.path) {
                try place(file, at: location)
                return besidePath
            }
            if DownloadedFileCheck.sha256(of: location) == file.sha256 { return besidePath }
            number += 1
        }
    }
}

/// The words the Guide shows once after an update: the new pages, how many were updated, and the notes whose changes
/// were kept with the new version beside them.
enum GuideVaultUpdateSummary {
    static let maximumPagesNamed = 6

    static func text(for changes: [String: GuideVaultCopyUpdate.Change]) -> String? {
        let notes = changes.filter { path, _ in path.hasSuffix(".md") && !path.hasPrefix(GuideVaultCopyUpdate.settingsFolderPrefix) }
        let added = notes.filter { _, change in change == .added }.keys.sorted(by: pageOrder)
        let updatedCount = notes.values.filter { change in change == .replaced }.count
        let kept = notes.compactMap { path, change -> (note: String, beside: String)? in
            guard case .keptWithNewVersionBeside(let besidePath) = change else { return nil }
            return (pageName(path), pageName(besidePath))
        }.sorted { first, second in first.note < second.note }
        var sentences: [String] = []
        if !added.isEmpty {
            // The main pages only, when there are some: a dashboard's own notes are counted, not named.
            let mainPages = added.filter { path in rank(path) == 0 }
            let namedPages = Array((mainPages.isEmpty ? added : mainPages).prefix(maximumPagesNamed))
            let named = namedPages.map(pageName).joined(separator: ", ")
            let more = added.count > namedPages.count ? " and \(added.count - namedPages.count) more" : ""
            sentences.append("The Guide has new pages: \(named)\(more).")
        }
        if updatedCount > 0 { sentences.append(updatedCount == 1 ? "1 page was updated." : "\(updatedCount) pages were updated.") }
        for keptNote in kept { sentences.append("Your changes to \(keptNote.note) were kept; the Guide's new version is \(keptNote.beside).") }
        if sentences.isEmpty { return nil }
        if added.isEmpty, kept.isEmpty { sentences.insert("The Guide was updated.", at: 0) }
        return sentences.joined(separator: " ")
    }

    /// A note's name without its folders or `.md`.
    private static func pageName(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The pages named first: a folder's own page ("Recipes/Recipes.md") and pages directly in a numbered section,
    /// before the notes inside a folder of examples; then in the order of their paths.
    private static func pageOrder(_ first: String, _ second: String) -> Bool {
        let firstRank = rank(first), secondRank = rank(second)
        return firstRank == secondRank ? first < second : firstRank < secondRank
    }

    private static func rank(_ path: String) -> Int {
        let components = path.split(separator: "/")
        let isFolderPage = components.count >= 2 && pageName(path) == String(components[components.count - 2])
        return components.count <= 2 || isFolderPage ? 0 : 1
    }
}
