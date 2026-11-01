/**
 * File: WikiLinkResolver.swift
 * ----------------------------
 * Layer: Core
 * Description: What a written link means: its parts, the paths it can name and which file of several it means, as in Obsidian.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import Foundation

public enum WikiLinkResolver {
    /// Splits a Wikilink's content at its first `|`. Inside a table the pipe is written
    /// `\|`, and that backslash is not part of the target.
    public static func targetAndLabel(of content: String) -> (target: String, label: String?) {
        let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        var target = String(parts.first ?? "")
        if parts.count > 1, target.hasSuffix("\\") { target.removeLast() }
        return (target, parts.count > 1 ? String(parts[1]) : nil)
    }

    public static func pathPart(_ target: String) -> String {
        String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
    /// Text for comparing names: file systems may store "é" as one character or as "e"
    /// plus an accent (as macOS often does), while links are typed with the first.
    public static func comparisonKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Text for matching names the way Obsidian does: ignoring case for every letter, not
    /// only ASCII, and whatever Unicode form the name is stored in. The index stores names
    /// and paths folded this way, so search compares them in SQL as the matcher does.
    public static func caseFoldedKey(_ text: String) -> String {
        // Lowercasing can leave a decomposed sequence, so normalization comes second.
        comparisonKey(text.lowercased())
    }

    /// The file names a link's path part may mean. A dot does not always start an
    /// extension (`[[Homework 2.1]]` is `Homework 2.1.md`), so both readings are tried,
    /// the file with the written extension first.
    public static func fileNameVariants(for part: String) -> [String] {
        (part as NSString).pathExtension.isEmpty ? [part + ".md", part] : [part, part + ".md"]
    }

    /// The files a link names by path, in the order Obsidian tries them: from the vault root,
    /// then beside the note, for each file-name reading. So `[[Note]]` in `Course/` means
    /// `Note.md` at the root when both it and `Course/Note.md` exist (`getLinkpathDest` in
    /// Obsidian 1.14.5). Wikilinks and Markdown links look in the same places, as in Obsidian,
    /// whose "absolute path in vault" Markdown links (which Graphite's link completion writes
    /// too) start at the root. A path starting with `./` or `../` is relative to the note
    /// only, and one starting with `/` is from the vault root only. A Markdown link's path is
    /// percent-decoded; a Wikilink's is not, as in Obsidian.
    public static func directCandidates(target: String, source: VaultPath, isWiki: Bool = true) -> [VaultPath] {
        // A Wikilink is written as the file is named: Obsidian decodes only Markdown links.
        let writtenPart = pathPart(target)
        var part = isWiki ? writtenPart : (writtenPart.removingPercentEncoding ?? writtenPart)
        if part.isEmpty { return [source] }
        guard URL(string: part)?.scheme == nil else { return [] }
        // `[[/Folder/Note]]` starts at the vault root, and only there; it is never joined
        // to the linking note's folder.
        if part.hasPrefix("/") {
            part = String(part.drop { character in character == "/" })
            guard !part.isEmpty else { return [] }
            return fileNameVariants(for: part).compactMap { fileNameVariant in try? VaultPath(fileNameVariant) }
        }
        let isRelativeToNote = isExplicitlyRelative(part)
        var paths: [VaultPath] = []
        for fileNameVariant in fileNameVariants(for: part) {
            if !isRelativeToNote, let fromVaultRoot = try? VaultPath(fileNameVariant) { paths.append(fromVaultRoot) }
            if let besideNote = try? source.parent.appending(fileNameVariant) { paths.append(besideNote) }
        }
        return Array(NSOrderedSet(array: paths).array.compactMap { candidate in candidate as? VaultPath })
    }

    /// The files a link's name or partial path matches, the one it means first, as Obsidian
    /// orders them: files whose path starts with the linking note's folder, then the rest, the
    /// shortest path first within each. That is a plain prefix in Obsidian, which also takes
    /// `Course 2/` for a note in `Course`. Every resolver goes through this, so a link means
    /// one file wherever it is read: tapping it, an embed, backlinks, the graph, a base, a rename.
    public static func closestFirst(_ paths: [String], toNoteAt source: VaultPath) -> [String] {
        guard paths.count > 1 else { return paths }
        let sourceFolderKey = caseFoldedKey(source.parent.rawValue)
        return paths.map { path in (path: path, isNearSource: caseFoldedKey(path).hasPrefix(sourceFolderKey), length: path.utf16.count) }
            .sorted { leftMatch, rightMatch in
                if leftMatch.isNearSource != rightMatch.isNearSource { return leftMatch.isNearSource }
                if leftMatch.length != rightMatch.length { return leftMatch.length < rightMatch.length }
                return leftMatch.path < rightMatch.path
            }
            .map(\.path)
    }

    /// The first of `directCandidates` that is a file in the vault at `root`. A folder is not
    /// a link target: `[[Projects]]` beside a Projects folder names the note Projects.md, as
    /// in Obsidian, so a folder never stands in for a file that is missing.
    public static func existingDirectFile(target: String, source: VaultPath, isWiki: Bool = true, in root: URL) -> VaultPath? {
        for candidate in directCandidates(target: target, source: source, isWiki: isWiki) {
            guard let location = try? candidate.url(in: root) else { continue } // A candidate outside the vault names no file.
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory), !isDirectory.boolValue { return candidate }
        }
        return nil
    }

    /// Whether a link's path starts with `./` or `../`, which only the note's own folder
    /// can resolve.
    public static func isExplicitlyRelative(_ linkPath: String) -> Bool {
        linkPath == "." || linkPath == ".." || linkPath.hasPrefix("./") || linkPath.hasPrefix("../")
    }
}
