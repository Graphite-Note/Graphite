/**
 * File: OversizedNoteDocument.swift
 * ---------------------------------
 * Layer: UI
 * Description: A note too large to edit, opened read-only: its file is read a page at a time, whatever its size,
 *              and nothing is ever written to it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation
import Observation
import GraphiteCore

/// How a large file is cut into pages of text. Every page starts where the page before it ends,
/// worked out from the file's bytes alone, so any page can be read without the ones before it:
/// after a line break near its nominal start, or, within a very long line, at the next byte
/// that starts a character.
enum OversizedNotePaging {
    static let pageBytes = 32 * 1_024
    /// How far past a page's nominal start a line break is looked for.
    static let boundarySearchBytes = 4 * 1_024
    /// What is read for one page, from its nominal start: enough to find where it ends.
    static let bytesReadPerPage = pageBytes + boundarySearchBytes

    static func pageCount(ofFileWith byteCount: Int) -> Int {
        max((byteCount + pageBytes - 1) / pageBytes, 1)
    }

    /// The text of a page, from the bytes read at its nominal start. Bytes that are not UTF-8
    /// show as replacement characters: this is a view, and nothing is written back.
    static func text(ofPage pageIndex: Int, pageCount: Int, in bytes: Data) -> String {
        let start = pageIndex == 0 ? 0 : boundary(in: bytes, from: 0)
        let end = pageIndex + 1 >= pageCount || bytes.count <= pageBytes ? bytes.count : boundary(in: bytes, from: pageBytes)
        guard start < end else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private static func boundary(in bytes: Data, from offset: Int) -> Int {
        let searchEnd = min(offset + boundarySearchBytes, bytes.count)
        if let lineBreak = bytes[offset..<searchEnd].firstIndex(of: UInt8(ascii: "\n")) { return lineBreak + 1 }
        // A UTF-8 character has at most three bytes after its first.
        var boundary = offset
        while boundary < searchEnd, boundary - offset < 3, bytes[boundary] & 0b1100_0000 == 0b1000_0000 { boundary += 1 }
        return boundary
    }
}

/// What a tab holds for a note over `MarkdownSession.maximumEditableBytes`, in place of a session:
/// no text in memory beyond the pages on screen, no editor, and no way to write to the file.
@MainActor @Observable
final class OversizedNoteDocument {
    /// How the file differs from the version shown.
    enum FileChange: Equatable {
        case none
        /// Another version, still too large to edit: the person chooses when to read it.
        case largeStill
        /// Small enough to edit now, or gone or unreadable, which opening says.
        case openAgain
    }

    let path: VaultPath
    private(set) var byteCount: Int
    private(set) var pageCount: Int
    /// Counts the versions shown, so pages on screen read their text again.
    private(set) var versionShown = 0
    private(set) var fileChange = FileChange.none
    /// The page at the top of the view, so a tab shows the note where it was left.
    @ObservationIgnored var topPageIndex: Int?
    @ObservationIgnored private let store: VaultStore
    /// The file as it was when this version was shown.
    @ObservationIgnored private var stamp: FileStamp
    /// How many pages have been read since the note opened, which shows the file is read as
    /// it is looked at.
    @ObservationIgnored private(set) var pagesRead = 0
    /// The page read last, which shows where the view is.
    @ObservationIgnored private(set) var lastPageRead: Int?

    private init(path: VaultPath, stamp: FileStamp, store: VaultStore) {
        self.path = path
        self.stamp = stamp
        self.store = store
        byteCount = stamp.size
        pageCount = OversizedNotePaging.pageCount(ofFileWith: stamp.size)
    }

    static func open(_ path: VaultPath, in store: VaultStore) async throws -> OversizedNoteDocument {
        OversizedNoteDocument(path: path, stamp: try await store.fileStamp(of: path), store: store)
    }

    func text(ofPage pageIndex: Int) async throws -> String {
        pagesRead += 1
        lastPageRead = pageIndex
        let bytes = try await store.readBytes(of: path, at: pageIndex * OversizedNotePaging.pageBytes, count: OversizedNotePaging.bytesReadPerPage)
        return OversizedNotePaging.text(ofPage: pageIndex, pageCount: pageCount, in: bytes)
    }

    /// Looks at the file again, costing one look at its size and date.
    func checkFile() async {
        let change: FileChange
        if let currentStamp = try? await store.fileStamp(of: path) { // Cannot be looked at: opening it says why.
            if currentStamp == stamp { change = .none } else { change = currentStamp.size > MarkdownSession.maximumEditableBytes ? .largeStill : .openAgain }
        } else {
            change = .openAgain
        }
        if fileChange != change { fileChange = change }
    }

    /// Shows the file as it is now, keeping the view and its place.
    func showCurrentVersion() async {
        guard let currentStamp = try? await store.fileStamp(of: path) else { return } // Cannot be looked at: the next check says so.
        stamp = currentStamp
        byteCount = currentStamp.size
        pageCount = OversizedNotePaging.pageCount(ofFileWith: currentStamp.size)
        versionShown += 1
        fileChange = .none
    }

    /// Whether the note can be loaded into the editor after all, for trimming. A file much
    /// larger than that would take more memory than the app can count on.
    var canEditAnyway: Bool { byteCount <= MarkdownSession.maximumBytesEditableAnyway }

    var notice: String {
        guard fileChange != .largeStill else {
            return "This note has changed since it was shown here. Reload shows the new version, at the same place. It stays read-only."
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .binary)
        let limit = MarkdownSession.maximumEditableBytes / 1_048_576
        if canEditAnyway {
            return "This note is \(size), too large to edit here: Graphite edits notes up to \(limit) MB, to stay within its memory. "
                + "It is shown as plain text, read-only."
        }
        return "This note is \(size), too large to edit in Graphite, even for trimming: another app can do that. "
            + "It is shown as plain text, read-only."
    }
}
