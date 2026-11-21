/**
 * File: PDFLinkClicks.swift
 * -------------------------
 * Layer: UI
 * Description: Web and app addresses a PDF page links to: a note's section of the vault opens beside the PDF in
 *              Graphite, which registers no obsidian:// scheme; every other address opens as PDFKit opens it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The PDF view's delegate for its links to addresses. Links to pages are followed by PDFKit
/// itself and never reach it.
@MainActor
// PDFKit calls its view's delegate on the main thread, where the view lives; the protocol
// predates Swift's actors and does not say so.
final class PDFLinkClicks: NSObject, @preconcurrency PDFViewDelegate {
    var sectionLinks: PDFSectionLinkActions?

    func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
        if let sectionLinks, SectionLink(openingURL: url) != nil {
            sectionLinks.openAddress(url)
            return
        }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}
