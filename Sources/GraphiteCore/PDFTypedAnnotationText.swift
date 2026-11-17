/**
 * File: PDFTypedAnnotationText.swift
 * ----------------------------------
 * Layer: Core
 * Description: The text people typed on a PDF, its text boxes and notes, read for Search with Core Graphics without
 *              loading the pages' content.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import Foundation
import CoreGraphics

/// The text people typed on a PDF, for Search: the `/Contents` of every text box (`/FreeText`)
/// and every note (`/Text`, the sticky notes of Graphite, Preview and Acrobat), read with
/// Core Graphics, which loads only the page and annotation dictionaries asked for, not the
/// pages' content. The pages' own printed text and the comments on marks are not read.
public enum PDFTypedAnnotationText {
    /// Bounds the work for one PDF: pages looked at, annotations per page, and text kept.
    public static let maximumPageCount = 10_000
    public static let maximumAnnotationsPerPage = 2_000
    public static let maximumUTF16Count = 1_048_576

    /// The text of the document's text boxes and notes, one per line, in page order and in each
    /// page's annotation order; empty when it has none. Stops at the limits; what was read
    /// until then is kept.
    public static func searchableText(of document: CGPDFDocument) -> String {
        var text = ""
        var textUTF16Count = 0
        let pageCount = min(document.numberOfPages, maximumPageCount)
        guard pageCount > 0 else { return "" }
        pageLoop: for pageNumber in 1...pageCount {
            guard let page = document.page(at: pageNumber), let pageDictionary = page.dictionary else { continue }
            for contents in typedContents(onPage: pageDictionary) {
                let addedCount = contents.utf16.count + 1
                guard textUTF16Count + addedCount <= maximumUTF16Count else { break pageLoop }
                text += contents + "\n"
                textUTF16Count += addedCount
            }
        }
        return text
    }

    /// The subtypes whose `/Contents` is text a person typed on the page.
    private static let typedSubtypes: Set<String> = [PDFTextBox.annotationTypeName, PDFNoteAnnotation.typeName]

    private static func typedContents(onPage pageDictionary: CGPDFDictionaryRef) -> [String] {
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations else { return [] }
        let annotationCount = min(CGPDFArrayGetCount(annotations), maximumAnnotationsPerPage)
        return (0..<annotationCount).compactMap { annotationIndex -> String? in
            var annotation: CGPDFDictionaryRef?
            var subtype: UnsafePointer<CChar>?
            var contents: CGPDFStringRef?
            guard CGPDFArrayGetDictionary(annotations, annotationIndex, &annotation), let annotation,
                  CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype, typedSubtypes.contains(String(cString: subtype)),
                  CGPDFDictionaryGetString(annotation, "Contents", &contents), let contents,
                  let text = CGPDFStringCopyTextString(contents) as String? else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.replacingOccurrences(of: "\r", with: "\n")
        }
    }
}

/// The PDF's note, a `/Text` annotation: an icon on the page whose `/Contents` opens in a `/Popup`.
public enum PDFNoteAnnotation {
    /// The subtype without its slash, as PDFKit and Core Graphics read it.
    public static let typeName = "Text"
}
