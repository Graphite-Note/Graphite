/**
 * File: InkMarkupCopyRemoval.swift
 * --------------------------------
 * Layer: Apple
 * Description: Leaves Apple's markup copy out of each Graphite ink annotation of a file PDFKit wrote, which made every
 *              stroke written into a document read from a file take twice to three times its room.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import Foundation

/// A Graphite ink annotation without Apple's markup data, `/AAPL:AKExtras`.
///
/// PDFKit writes that dictionary into every annotation it creates in a document read from a file, as every save of a
/// PDF Graphite writes on is: a copy of the whole annotation dictionary (its `/InkList` and Graphite's keys, the page's
/// re-editing record on the first stroke) and an archive of Apple's markup object, about 1.8 KB a stroke beside the
/// 1 KB of the stroke itself. Measured 2026-11-12 on an import of two pages of 2,000 strokes: 33.2 MB with the copies,
/// 11.2 MB without. Readers draw the annotation from its own keys and its appearance, and Graphite edits it through
/// them; Apple's markup tools treat an ink annotation without the copy as any other application's ink. Every other byte
/// of the annotation is copied as it is.
enum InkMarkupCopyRemoval {
    private static let markupDataKey = "AAPL:AKExtras"
    private static let inkSubtype = "Ink"

    /// Whether the dictionary is Graphite ink with Apple's markup copy.
    static func holdsMarkupCopy(_ dictionary: PDFSyntaxDictionary) -> Bool {
        guard case .name(inkSubtype)? = dictionary.entries["Subtype"], dictionary.entries[PDFPageManager.groupKey.rawValue] != nil else { return false }
        return dictionary.entryRanges[markupDataKey] != nil
    }

    /// The annotations' new bytes, by object number.
    static func find(in candidates: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?, bytes: UnsafeRawBufferPointer) -> [Int: Data] {
        var replacements: [Int: Data] = [:]
        for number in candidates {
            guard let object = objects(number) else { continue }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj",
                  case .dictionary(let annotation)? = scanner.readValue(), scanner.streamDataStart(before: object.range.upperBound) == nil,
                  holdsMarkupCopy(annotation), let copyRange = annotation.entryRanges[markupDataKey],
                  object.range.contains(copyRange.lowerBound), copyRange.upperBound <= object.range.upperBound else { continue }
            var objectBytes = Data(UnsafeRawBufferPointer(rebasing: bytes[object.range.lowerBound..<copyRange.lowerBound]))
            objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[copyRange.upperBound..<object.range.upperBound])))
            replacements[number] = objectBytes
        }
        return replacements
    }
}
