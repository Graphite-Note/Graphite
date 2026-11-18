/**
 * File: PDFPageDuplication.swift
 * ------------------------------
 * Layer: Apple
 * Description: Duplicates a page of a PDF with its annotations and their Graphite keys, which PDFKit's copy of a page
 *              read from a file leaves out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
import Foundation
import PDFKit
import GraphiteCore

extension PDFPageManager {
    /// Puts a copy of the page after it, with its annotations and their Graphite keys.
    static func duplicate(_ source: PDFPage, at pageIndex: Int, in document: PDFDocument) throws {
        guard let duplicate = source.copy() as? PDFPage else { throw GraphiteError.invalidFile("Cannot duplicate page.") }
        document.insert(duplicate, at: pageIndex + 1)
        carryGraphiteKeys(from: source, to: duplicate)
    }

    /// Gives a duplicate's annotations the Graphite keys of those they copy: a page whose annotations PDFKit read from
    /// the file copies them without keys it does not know, so every save lost a duplicated page's ink groups (HUNT-370).
    static func carryGraphiteKeys(from source: PDFPage, to duplicate: PDFPage) {
        let sourceAnnotations = source.annotations
        let duplicateAnnotations = duplicate.annotations
        guard sourceAnnotations.count == duplicateAnnotations.count else { return }
        for (sourceAnnotation, duplicateAnnotation) in zip(sourceAnnotations, duplicateAnnotations) where sourceAnnotation.type == duplicateAnnotation.type {
            for key in graphiteAnnotationKeys {
                guard let value = sourceAnnotation.value(forAnnotationKey: key), duplicateAnnotation.value(forAnnotationKey: key) == nil else { continue }
                duplicateAnnotation.setValue(value, forAnnotationKey: key)
            }
        }
    }
}
