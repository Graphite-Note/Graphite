/**
 * File: FileTreeNameFilter.swift
 * ------------------------------
 * Layer: Core
 * Description: Finding folders and files by part of their name: the comparison the file tree's filter and the
 *              search's folder: share, and the vault's tree of names the filter narrows at each keystroke.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation

/// How the file tree's filter and the search's `folder:` compare a name with typed text: the text anywhere in the name,
/// ignoring case, accents and character width, so "bati" finds "Batikha-hour" and "ete" finds "Été".
public enum VaultNameMatching {
    static let comparisonOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// The text as names are compared: folded, then composed, so a name stored decomposed (as the Mac's file system
    /// may store it) compares as the same characters typed.
    public static func folded(_ text: String) -> String {
        text.folding(options: comparisonOptions, locale: nil).precomposedStringWithCanonicalMapping
    }

    /// Whether `name` contains `text`, folded alike.
    public static func name(_ name: String, contains text: String) -> Bool {
        let foldedText = folded(text)
        guard !foldedText.isEmpty else { return true }
        return folded(name).range(of: foldedText, options: .literal) != nil
    }

    /// The part of `name` that `text` matched, which the tree highlights.
    public static func matchedRange(of text: String, in name: String) -> Range<String.Index>? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return nil }
        return name.range(of: trimmedText, options: comparisonOptions)
    }

    /// The name the filter reads: a note's name without `.md`, which every note shares and the tree does not show, and
    /// every other file's or folder's whole name, extension included ("slides.pdf" is found by "pdf").
    public static func filteredName(of entry: VaultEntry) -> String {
        !entry.isDirectory && entry.kind == .markdown ? entry.path.stem : entry.path.name
    }
}

/// A row of the file tree, filtered or not: a file or folder, at its depth in the vault (0 at its root).
public struct FileTreeRow: Identifiable, Equatable, Sendable {
    public let entry: VaultEntry
    public let depth: Int
    public var id: String { entry.path.rawValue }

    public init(entry: VaultEntry, depth: Int) {
        self.entry = entry
        self.depth = depth
    }
}

/// Every folder and file of the vault by name, in the file tree's order, built once (off the main thread) from the
/// paths the index and the workspace already list, so filtering it reads no file and answers within a frame.
///
/// Entries are kept in the tree's order, folders before their contents, and are found by position. Every name the
/// filter reads is folded once, here, into one run of bytes with a zero byte after each name, so a keystroke is one
/// `memmem` pass over the run: about 30,000 names in a millisecond, where comparing names one by one as Swift strings
/// took most of a frame.
public struct FileTreeNameIndex: Sendable {
    /// Tells one build from another, so a result is known by its text and the index it came from.
    public let generation = UUID()
    let entries: [VaultEntry]
    /// Each entry's folder, by position; -1 for the vault's root.
    let parentPositions: [Int]
    /// Each folder's contents, by position, in the tree's order; empty for a file.
    let childPositions: [[Int]]
    let rootChildPositions: [Int]
    /// Each entry's depth, 0 at the vault's root.
    let depths: [Int]
    /// The position after each entry and everything inside it, where the next entry beside it starts.
    let positionsAfterContents: [Int]
    let positionsByPath: [VaultPath: Int]
    let foldedNames: [UInt8]
    /// Where each entry's folded name starts in `foldedNames`, in increasing order.
    let foldedNameStarts: [Int]

    /// - Parameters:
    ///   - entries: The vault's files (the index's file table) and what the workspace has listed, files and folders;
    ///     a path given twice keeps its last entry. Folders above every path are added, and hidden paths left out.
    ///   - sortOrder: The order of the tree's rows, folders first as the tree lists them.
    public init(entries: [VaultEntry], sortOrder: FileSortOrder) {
        var entriesByPath: [VaultPath: VaultEntry] = [:]
        entriesByPath.reserveCapacity(entries.count)
        for entry in entries where !entry.path.rawValue.isEmpty && !entry.path.isHidden { entriesByPath[entry.path] = entry }
        var contentsByFolder: [VaultPath: [VaultEntry]] = [:]
        for entry in Array(entriesByPath.values) {
            var path = entry.path
            // Folders no listing named yet, known from the paths inside them.
            while !path.parent.rawValue.isEmpty, entriesByPath[path.parent] == nil {
                let folder = VaultEntry(path: path.parent, isDirectory: true, size: 0, modified: .distantPast)
                entriesByPath[folder.path] = folder
                path = folder.path
            }
        }
        for entry in entriesByPath.values { contentsByFolder[entry.path.parent, default: []].append(entry) }
        var builder = Builder(capacity: entriesByPath.count)
        builder.append(contentsOf: contentsByFolder, of: .root, parentPosition: -1, sortOrder: sortOrder)
        self.entries = builder.entries
        parentPositions = builder.parentPositions
        childPositions = builder.childPositions
        rootChildPositions = builder.rootChildPositions
        depths = builder.depths
        positionsAfterContents = builder.positionsAfterContents
        positionsByPath = builder.positionsByPath
        foldedNames = builder.foldedNames
        foldedNameStarts = builder.foldedNameStarts
    }

    /// How many folders and files the index holds.
    public var entryCount: Int { entries.count }

    /// The folders and files whose name contains `text`; nil when the text, without its spaces at either end, is empty.
    public func filter(_ text: String) -> FileTreeNameFilterResult? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        // A zero byte ends each name in the run, so the text must hold none.
        let pattern = Array(VaultNameMatching.folded(trimmedText).utf8.filter { byte in byte != 0 })
        guard !pattern.isEmpty else { return nil }
        var isMatched = [Bool](repeating: false, count: entries.count)
        var matchedPositions: [Int] = []
        foldedNames.withUnsafeBufferPointer { names in
            pattern.withUnsafeBufferPointer { patternBytes in
                guard let namesStart = names.baseAddress, let patternStart = patternBytes.baseAddress else { return }
                var offset = 0
                while offset < names.count, let found = memmem(namesStart + offset, names.count - offset, patternStart, patternBytes.count) {
                    let foundOffset = namesStart.distance(to: found.assumingMemoryBound(to: UInt8.self))
                    let position = position(ofNameAt: foundOffset)
                    isMatched[position] = true
                    matchedPositions.append(position)
                    // On to the next name: one match is enough for a name.
                    offset = position + 1 < foldedNameStarts.count ? foldedNameStarts[position + 1] : names.count
                }
            }
        }
        var hasMatchInside = [Bool](repeating: false, count: entries.count)
        var folderPositionsAboveMatches: [Int] = []
        for position in matchedPositions {
            var folder = parentPositions[position]
            // Each folder is marked once: the walk stops at the first folder already marked.
            while folder >= 0, !hasMatchInside[folder] {
                hasMatchInside[folder] = true
                folderPositionsAboveMatches.append(folder)
                folder = parentPositions[folder]
            }
        }
        return FileTreeNameFilterResult(text: trimmedText, index: self, isMatched: isMatched, hasMatchInside: hasMatchInside,
                                        folderPositionsAboveMatches: folderPositionsAboveMatches, matchCount: matchedPositions.count)
    }

    /// The entry whose name holds the byte at `offset` of `foldedNames`.
    private func position(ofNameAt offset: Int) -> Int {
        var lowerBound = 0, upperBound = foldedNameStarts.count
        while upperBound - lowerBound > 1 {
            let middle = (lowerBound + upperBound) / 2
            if foldedNameStarts[middle] <= offset { lowerBound = middle } else { upperBound = middle }
        }
        return lowerBound
    }

    /// Lays the entries out in the tree's order while the index is built.
    private struct Builder {
        var entries: [VaultEntry] = []
        var parentPositions: [Int] = []
        var childPositions: [[Int]] = []
        var rootChildPositions: [Int] = []
        var depths: [Int] = []
        var positionsAfterContents: [Int] = []
        var positionsByPath: [VaultPath: Int] = [:]
        var foldedNames: [UInt8] = []
        var foldedNameStarts: [Int] = []

        init(capacity: Int) {
            depths.reserveCapacity(capacity)
            positionsAfterContents.reserveCapacity(capacity)
            entries.reserveCapacity(capacity)
            parentPositions.reserveCapacity(capacity)
            childPositions.reserveCapacity(capacity)
            positionsByPath.reserveCapacity(capacity)
            foldedNameStarts.reserveCapacity(capacity)
        }

        /// Appends a folder's contents, each folder followed by its own; returns their positions.
        @discardableResult
        mutating func append(contentsOf contentsByFolder: [VaultPath: [VaultEntry]], of folder: VaultPath, parentPosition: Int,
                             sortOrder: FileSortOrder) -> [Int] {
            var positions: [Int] = []
            for entry in sortOrder.sorted(contentsByFolder[folder] ?? []) {
                let position = entries.count
                positions.append(position)
                entries.append(entry)
                parentPositions.append(parentPosition)
                childPositions.append([])
                depths.append(parentPosition < 0 ? 0 : depths[parentPosition] + 1)
                positionsAfterContents.append(position + 1)
                positionsByPath[entry.path] = position
                foldedNameStarts.append(foldedNames.count)
                foldedNames.append(contentsOf: VaultNameMatching.folded(VaultNameMatching.filteredName(of: entry)).utf8)
                foldedNames.append(0)
                if entry.isDirectory {
                    childPositions[position] = append(contentsOf: contentsByFolder, of: entry.path, parentPosition: position, sortOrder: sortOrder)
                    positionsAfterContents[position] = entries.count
                }
            }
            if parentPosition < 0 { rootChildPositions = positions }
            return positions
        }
    }
}

/// The folders and files one filter text matched, and what the tree shows for them: each match with the folders above
/// it, those folders expanded; a matching folder collapsed, its whole content shown once it is expanded.
public struct FileTreeNameFilterResult: Sendable, Equatable {
    /// The text as matched, without spaces at either end.
    public let text: String
    let index: FileTreeNameIndex
    let isMatched: [Bool]
    let hasMatchInside: [Bool]
    /// The folders a match is inside, by position: found while matching, so no keystroke reads every entry twice.
    let folderPositionsAboveMatches: [Int]
    /// How many folders and files matched.
    public let matchCount: Int

    /// A result is a function of its text and its index alone, so those are all it is compared by: comparing every
    /// entry's flag at each keystroke would cost what filtering does.
    public static func == (leftResult: Self, rightResult: Self) -> Bool {
        leftResult.text == rightResult.text && leftResult.index.generation == rightResult.index.generation
    }

    public func isMatched(_ path: VaultPath) -> Bool {
        index.positionsByPath[path].map { position in isMatched[position] } ?? false
    }

    /// The folders a match is inside, which the tree shows expanded.
    public var foldersAboveMatches: Set<VaultPath> {
        Set(folderPositionsAboveMatches.map { position in index.entries[position].path })
    }

    /// What the tree shows inside `folder` (`.root` for the vault's top level): everything inside a matching folder,
    /// and elsewhere the matches and the folders that lead to one.
    public func shownChildren(of folder: VaultPath) -> [VaultEntry] {
        shownChildPositions(of: folder.rawValue.isEmpty ? -1 : index.positionsByPath[folder]).map { position in index.entries[position] }
    }

    /// The rows the tree shows with `expandedFolders` expanded, a folder's shown contents after it.
    ///
    /// One pass over the entries in the tree's order, stepping over the contents of every row not shown or folded: at
    /// each keystroke that matches most of a vault, this is most of the work.
    public func rows(expandedFolders: Set<VaultPath>) -> [FileTreeRow] {
        var isExpanded = [Bool](repeating: false, count: index.entries.count)
        for folder in expandedFolders { if let position = index.positionsByPath[folder] { isExpanded[position] = true } }
        // Whether everything inside an entry shows: it matched, or a folder above it did. Its folder comes first.
        var showsWholeContent = [Bool](repeating: false, count: index.entries.count)
        var rows: [FileTreeRow] = []
        rows.reserveCapacity(matchCount + folderPositionsAboveMatches.count)
        var position = 0
        while position < index.entries.count {
            let parent = index.parentPositions[position]
            let isInsideWholeContent = parent >= 0 && showsWholeContent[parent]
            // Not shown: nothing inside it is, as nothing inside it matched.
            guard isInsideWholeContent || isMatched[position] || hasMatchInside[position] else {
                position = index.positionsAfterContents[position]
                continue
            }
            showsWholeContent[position] = isInsideWholeContent || isMatched[position]
            rows.append(FileTreeRow(entry: index.entries[position], depth: index.depths[position]))
            position = isExpanded[position] ? position + 1 : index.positionsAfterContents[position]
        }
        return rows
    }

    /// Positions of what shows inside a folder; nil for a folder the index does not hold, -1 for the root.
    private func shownChildPositions(of folderPosition: Int?) -> [Int] {
        guard let folderPosition else { return [] }
        let children = folderPosition < 0 ? index.rootChildPositions : index.childPositions[folderPosition]
        guard !showsWholeContent(of: folderPosition) else { return children }
        return children.filter { position in isMatched[position] || hasMatchInside[position] }
    }

    /// Whether the folder or one above it matched, so all it holds shows.
    private func showsWholeContent(of folderPosition: Int) -> Bool {
        var position = folderPosition
        while position >= 0 {
            if isMatched[position] { return true }
            position = index.parentPositions[position]
        }
        return false
    }
}
