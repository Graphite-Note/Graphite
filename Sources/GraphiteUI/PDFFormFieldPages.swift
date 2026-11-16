/**
 * File: PDFFormFieldPages.swift
 * -----------------------------
 * Layer: UI
 * Description: The pages of a PDF file that hold form fields, read from the file's own page dictionaries off the main
 *              thread, so the shown document's annotations are read only on those pages to make the fields read-only.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import Foundation
import CoreGraphics
import PDFKit

/// The pages of a PDF file with a form field (a `/Widget` annotation), by page number.
///
/// The shown document's form fields are made read-only (`PDFViewPageObserver`), which needs PDFKit's annotations of the
/// page, and PDFKit makes them all the first time a page's annotations are read: 20 to 54 ms on the main thread for a
/// page written with 520 strokes, as each stroke is an annotation, at every page a PDF showed for the first time. A
/// handwritten PDF coming into view in a note stopped the scrolling for that (2026-11-16, measured with PDFKit on macOS
/// 27). The file's own page dictionaries say which pages have fields, read once as the PDF opens, off the main thread.
enum PDFFormFieldPages {
    /// The one-based numbers of the pages of the file at `fileLocation` with a form field; nil when the file cannot be
    /// read, so every page is looked at as before.
    static func pageNumbers(at fileLocation: URL) -> Set<Int>? {
        guard let pdfDocument = CGPDFDocument(fileLocation as CFURL) else { return nil }
        // The pages and their dictionaries belong to the document and are freed with it.
        return withExtendedLifetime(pdfDocument) {
            var pageNumbers = Set<Int>()
            guard pdfDocument.numberOfPages > 0 else { return pageNumbers }
            for pageNumber in 1...pdfDocument.numberOfPages {
                if let page = pdfDocument.page(at: pageNumber), let dictionary = page.dictionary, hasFormField(inPage: dictionary) {
                    pageNumbers.insert(pageNumber)
                }
            }
            return pageNumbers
        }
    }

    /// Whether the page dictionary's `/Annots` holds an annotation of subtype `/Widget`.
    static func hasFormField(inPage dictionary: CGPDFDictionaryRef) -> Bool {
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Annots", &annotations), let annotations else { return false }
        for annotationIndex in 0..<CGPDFArrayGetCount(annotations) {
            var annotation: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotations, annotationIndex, &annotation), let annotation else { continue }
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype, String(cString: subtype) == "Widget" { return true }
        }
        return false
    }

    /// Whether `page` may hold a form field: a page of the file read as it opened only when `pageNumbers` names it, any
    /// other page (one put in from another PDF, or with no file read) whenever its own dictionary has one.
    static func mayHaveFormField(_ page: PDFPage, in document: PDFDocument, pageNumbers: Set<Int>?) -> Bool {
        guard let corePage = page.pageRef else { return true }
        if let pageNumbers, let documentReference = document.documentRef, corePage.document === documentReference {
            return pageNumbers.contains(corePage.pageNumber)
        }
        guard let dictionary = corePage.dictionary else { return true }
        return hasFormField(inPage: dictionary)
    }
}
