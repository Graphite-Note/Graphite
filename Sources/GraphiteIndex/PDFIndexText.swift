/**
 * File: PDFIndexText.swift
 * ------------------------
 * Layer: Index
 * Description: What the index reads of a PDF: the text of its text boxes and notes, and the sections of notes its
 *              pictures link to, read with Core Graphics without loading the pages' content.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import Foundation
import CoreGraphics
import GRDB
import GraphiteCore

/// What Search reads of a PDF: the text of its text boxes and notes (`PDFTypedAnnotationText`), not its
/// printed text. Core Graphics loads only the page and annotation dictionaries it is asked
/// for, so a large PDF is not read whole; what is read is bounded by `PDFTypedAnnotationText`.
enum PDFIndexText {
    /// A PDF this size or smaller is read for its text boxes and notes; most of its bytes, the pages'
    /// content and images, are never loaded.
    static let maximumPDFBytes = 2 * 1_073_741_824

    /// The text of the PDF at a location that is already coordinated. An encrypted PDF has
    /// none Graphite can read without its password; one Core Graphics cannot open is a failure,
    /// read again by the next scan.
    static func reading(at location: URL) -> VaultIndex.NoteReading {
        guard let document = CGPDFDocument(location as CFURL) else {
            return .failed(PDFIndexReadingError.unreadable)
        }
        guard document.isUnlocked else { return .text("") }
        return .text(PDFTypedAnnotationText.indexedText(of: document))
    }

    /// The same, under a file coordination of its own, as a refresh of one file reads it.
    static func coordinatedReading(at location: URL) -> VaultIndex.NoteReading {
        var coordinationError: NSError?
        var reading: VaultIndex.NoteReading?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: location, options: [], error: &coordinationError) { coordinatedLocation in
            reading = Self.reading(at: coordinatedLocation)
        }
        if let coordinationError { return .failed(coordinationError) }
        return reading ?? .failed(PDFIndexReadingError.unavailable)
    }
}

extension VaultIndex {
    /// A PDF's pictures of notes' sections are links of the PDF (`PDFTypedAnnotationText.indexedText`);
    /// every PDF is read again on the next scan to record them.
    static func registerPDFSectionLinksMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("pdf-section-links-13") { database in
            try database.execute(sql: "UPDATE files SET size = -1 WHERE path LIKE '%.pdf'")
        }
    }
}
