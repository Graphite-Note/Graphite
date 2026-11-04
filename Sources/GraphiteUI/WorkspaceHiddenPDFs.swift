/**
 * File: WorkspaceHiddenPDFs.swift
 * -------------------------------
 * Layer: UI
 * Description: The PDFs a window keeps open while they are not shown: a hidden tab's, and the one a tab showed before
 *              another file opened in it, within one limit, and the PDF views kept with them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import Foundation
import GraphiteCore

/// The hidden PDFs of the window's tabs (PDF-13): at most `maximumHiddenPDFSessionCount` stay open, the most recently
/// left; the others are let go once saved and open again from their file, on the same page.
extension WorkspaceModel {
    /// Hidden tabs keep at most this many PDFs open; the others are let go once saved. A PDF a
    /// tab showed before its file was replaced counts as a hidden tab's (`TabDocument.replacedPDF`).
    static let maximumHiddenPDFSessionCount = 1

    /// Lets go of the PDFs of hidden tabs, beyond the most recently hidden one, so memory
    /// does not grow with every PDF ever opened in a tab. A PDF with unsaved edits, a save
    /// running, or a conflict is kept. A released tab reopens its PDF, at the same page,
    /// when it is shown again, which loses PDFKit's undo history for it.
    func releaseHiddenPDFSessions() {
        let visibleTabIDs = layout.shownTabIDs
        let now = ContinuousClock.now
        for tabID in visibleTabIDs { tabDocuments[tabID]?.lastVisibleTime = now }
        let hiddenPDFDocuments = tabDocuments.filter { tabID, document in !visibleTabIDs.contains(tabID) && document.pdfSession != nil }
            .values.sorted { leftDocument, rightDocument in leftDocument.lastVisibleTime > rightDocument.lastVisibleTime }
        // The PDFs replaced in a tab, newest first, share the limit with the hidden tabs' PDFs.
        enum HiddenPDF { case tab(TabDocument), replaced(TabDocument) }
        let replacedPDFs = tabDocuments.values.compactMap { document in document.replacedPDF.map { replaced in (document, replaced.time) } }
        let hiddenPDFs = (hiddenPDFDocuments.map { document in (HiddenPDF.tab(document), document.lastVisibleTime) }
            + replacedPDFs.map { document, time in (HiddenPDF.replaced(document), time) })
            .sorted { leftPDF, rightPDF in leftPDF.1 > rightPDF.1 }
        for (hiddenPDF, _) in hiddenPDFs.dropFirst(Self.maximumHiddenPDFSessionCount) {
            switch hiddenPDF {
            case .replaced(let document):
                document.replacedPDF = nil
            case .tab(let document):
                guard let session = document.pdfSession, let path = document.loadedPath, !document.isOpening,
                      !session.hasUnsavedChanges, !session.isSaving, !session.hasExternalConflict else { continue }
                document.releasedPDFPage = (path, session.currentPageIndex)
                rememberPlaces(of: [document])
                document.unload()
            }
        }
        keepOnlyTheViewsOfOpenPDFs()
    }

    /// Lets go of a kept PDF view whose session no tab holds any more (`HiddenPDFViews`).
    func keepOnlyTheViewsOfOpenPDFs() {
        #if canImport(UIKit)
        let openSessions = tabDocuments.values.flatMap { document in [document.pdfSession, document.replacedPDF?.session].compactMap { $0 } }
        hiddenPDFViews.keepOnly(sessions: openSessions)
        #endif
    }

    /// The PDF this tab showed before, when it is the file opened again and nothing changed it meanwhile: reused as
    /// it is, with its view, history and place, rather than read from the file again.
    func replacedPDFToShowAgain(at path: VaultPath, in document: TabDocument) async -> PDFSession? {
        // Only this tab's: a second open session of the file elsewhere could save over it.
        for otherDocument in tabDocuments.values where otherDocument !== document && otherDocument.replacedPDF?.path == path {
            otherDocument.replacedPDF = nil
        }
        guard let replaced = document.replacedPDF, replaced.path == path else { return nil }
        document.replacedPDF = nil
        let session = replaced.session
        let hasChanged = try? await session.hasChangedExternally() // A file that cannot be checked is read again, as a new one would be.
        guard !session.hasExternalConflict, !session.isProtected, hasChanged == false else { return nil }
        return session
    }
}
