/**
 * File: PDFViewDocumentAnalysis.swift
 * -----------------------------------
 * Layer: UI
 * Description: Keeps PDFKit's own analysis of the pages shown, Vision's text and form recognition, out of the PDF
 *              views embedded in a note (HUNT-366).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation
import PDFKit

/// PDFKit analyses each page a view shows with Vision (`PDFPageAnalyzerV2`, recognised text and form fields), started
/// whenever the view's visible pages change. A note shows one view per embedded PDF: on the iPhone simulator, 2026-11-17,
/// dozens of these analyses waited on Vision's capacity and on the GPU while the main thread waited on a layer of theirs,
/// and the app froze for good (HUNT-366). An embed is a preview of its PDF; the PDF's own tab keeps the analysis.
enum PDFViewDocumentAnalysis {
    /// PDFView's switch for the analysis, on by default. It has no public name; a PDFKit without it is left as it is.
    static let switchKey = "documentAnalysisEnabled"

    /// Turns the analysis off before the view's document is set, so no page is analysed.
    static func turnOff(in view: PDFView) {
        guard view.responds(to: NSSelectorFromString("setDocumentAnalysisEnabled:")) else { return }
        view.setValue(false, forKey: switchKey)
    }

    /// Whether the view analyses its pages; nil when PDFKit has no such switch. The Mac's PDFKit reads it as
    /// `documentAnalysisEnabled`, iOS's as `isDocumentAnalysisEnabled`; key-value coding finds either.
    static func isOn(in view: PDFView) -> Bool? {
        let getters = [switchKey, "isDocumentAnalysisEnabled"]
        guard getters.contains(where: { getter in view.responds(to: NSSelectorFromString(getter)) }) else { return nil }
        return view.value(forKey: switchKey) as? Bool
    }
}
