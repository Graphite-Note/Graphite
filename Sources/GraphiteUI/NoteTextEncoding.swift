/**
 * File: NoteTextEncoding.swift
 * ----------------------------
 * Layer: UI
 * Description: A note's text as stored in UTF-8, and a queued insertion for its editor.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// A note's text as stored in UTF-8. A leading byte-order mark is kept apart from the
/// text, as Foundation's decoder would drop it, so that it can be written back unchanged.
enum NoteTextEncoding {
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The text, or nil when the bytes are not valid UTF-8.
    static func decode(_ data: Data) -> (text: String, hasByteOrderMark: Bool)? {
        let hasByteOrderMark = data.starts(with: byteOrderMark)
        guard let text = String(validating: data.dropFirst(hasByteOrderMark ? byteOrderMark.count : 0), as: UTF8.self) else { return nil }
        return (text, hasByteOrderMark)
    }

    static func encode(_ text: String, hasByteOrderMark: Bool) -> Data {
        hasByteOrderMark ? Data(byteOrderMark) + Data(text.utf8) : Data(text.utf8)
    }
}

struct EditorInsertion: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let range: NSRange
    /// Where the selection goes afterwards; after the inserted text when nil.
    var selectionAfter: NSRange?
}
