/**
 * File: WorkspaceSectionLinkMoves.swift
 * -------------------------------------
 * Layer: UI
 * Description: A note that moves or is renamed keeps the PDF pages that link to its sections: the PDFs linking to it
 *              are found through the index before it moves, and their section pictures link to its new place after.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple
import GraphiteIndex

extension WorkspaceModel {
    /// The PDFs whose section pictures link to a note of the move, read from the index before
    /// anything moves (the index records them, `PDFTypedAnnotationText.indexedText`).
    func pdfsLinkingToSections(of moves: [VaultPath: VaultPath]) async -> Set<VaultPath> {
        guard let index else { return [] }
        var pdfs = Set<VaultPath>()
        for movedPath in moves.keys where DocumentKind(path: movedPath) == .markdown {
            let linking = (try? await index.linkingNotes(to: movedPath)) ?? [] // Unanswered: its PDFs stay, as an unfound link does.
            pdfs.formUnion(linking.filter { source in DocumentKind(path: source) == .pdf })
        }
        return pdfs
    }

    /// Gives the section pictures of these PDFs the moved notes' new places: through its
    /// session for a PDF that is open, which saves as an edit does, else in its file, replaced
    /// atomically if no one changed it meanwhile. Not a step of any history.
    ///
    /// - Returns: The PDFs written, by their path after the move, and what could not be done.
    func relinkSectionPictures(in pdfs: Set<VaultPath>, after moves: [VaultPath: VaultPath]) async -> (written: [VaultPath], problems: [String]) {
        let rewrite: (String) -> String? = { address in SectionLink.address(address, following: moves) }
        var written: [VaultPath] = []
        var problems: [String] = []
        for pdf in pdfs.sorted() {
            let path = moves[pdf] ?? pdf
            do {
                if let session = tabDocuments.values.compactMap(\.pdfSession).first(where: { session in vaultPath(for: session.location) == path }) {
                    for edit in PDFPageManager.sectionLinkEdits(in: session.document, rewriting: rewrite) { try session.apply(edit) }
                } else if try await relinkSectionPictures(inClosedPDFAt: path, rewriting: rewrite) {
                    written.append(path)
                }
            } catch {
                var reason: String?
                reason.report(error)
                if let reason { problems.append("The links of “\(path.name)” to the moved note could not be updated: \(reason)") }
            }
        }
        return (written, problems)
    }

    /// Rewrites the section pictures of a PDF that is not open; false when it has none to change.
    private func relinkSectionPictures(inClosedPDFAt path: VaultPath, rewriting rewrite: (String) -> String?) async throws -> Bool {
        guard let store else { return false }
        let location = try path.url(in: store.root)
        // A signed PDF would lose its signature's validity: it keeps its links, as Graphite keeps it unchanged.
        guard !PDFStructureInspection.hasDigitalSignature(in: location) else { throw SectionLinkError.pdfNotChangeable }
        let snapshot = try await store.read(path)
        guard let document = PDFDocument(data: snapshot.data), !document.isLocked, document.allowsDocumentChanges else {
            throw SectionLinkError.pdfNotChangeable
        }
        let edits = PDFPageManager.sectionLinkEdits(in: document, rewriting: rewrite)
        guard !edits.isEmpty else { return false }
        _ = try await PDFFileService(writer: store.writer).save(url: location, revision: snapshot.revision, edits: edits)
        return true
    }
}
