/**
 * File: PDFPageListDrop.swift
 * ---------------------------
 * Layer: UI
 * Description: A PDF dropped onto the page list of a PDF's sidebar: where its pages go (before the first page, between
 *              two pages, after the last), the line that shows it while dragging, reading the dropped PDFs, and
 *              inserting their pages as one undo step; a page of the list dragged to another place in it moves there.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
#if os(macOS)
import AppKit
#endif

/// Where a PDF dropped onto the page list puts its pages, from where the rows stand in the list.
enum PDFPageListInsertion {
    /// How far the line before the first page or after the last stands from that row: half the list's padding.
    static let edgeGap: CGFloat = 4

    /// The index the dropped pages start at, for a drop at `y` in the list: before the first row whose middle is below
    /// the pointer, else after the last row. `rowFrames` holds the rows laid out, by page index, in the list's
    /// coordinates; a lazy list lays out the rows near the pointer, so rows far from it can be missing.
    static func insertionIndex(atY y: CGFloat, rowFrames: [Int: CGRect], pageCount: Int) -> Int {
        let orderedRows = rowFrames.filter { pageIndex, _ in pageIndex < pageCount }.sorted { first, second in first.key < second.key }
        guard let lastRow = orderedRows.last else { return pageCount }
        if let rowBelow = orderedRows.first(where: { _, frame in y < frame.midY }) { return rowBelow.key }
        return min(lastRow.key + 1, pageCount)
    }

    /// Where a page dragged within the list ends up when let go at `insertionIndex`: taken out first, it leaves a gap
    /// that moves every later place up by one.
    static func moveDestination(ofPage pageIndex: Int, insertedAt insertionIndex: Int) -> Int {
        insertionIndex > pageIndex ? insertionIndex - 1 : insertionIndex
    }

    /// Where the line for `insertionIndex` is drawn: halfway between the two rows it falls between, or just outside the
    /// one row it is next to. Nil when neither row is laid out.
    static func lineY(forInsertionIndex insertionIndex: Int, rowFrames: [Int: CGRect]) -> CGFloat? {
        switch (rowFrames[insertionIndex - 1], rowFrames[insertionIndex]) {
        case let (rowAbove?, rowBelow?): (rowAbove.maxY + rowBelow.minY) / 2
        case let (nil, rowBelow?): rowBelow.minY - edgeGap
        case let (rowAbove?, nil): rowAbove.maxY + edgeGap
        case (nil, nil): nil
        }
    }
}

/// A drag of PDFs over the page list: the place its pages would go, which the line shows, and where the rows stand.
/// The rows' frames are kept out of observation: they change as the list is laid out, which must not redraw the list.
@MainActor
@Observable
final class PDFPageListDropTargeting {
    /// Where the dragged pages would go, while a drag the list takes is over it.
    var insertionIndex: Int?
    /// Each laid-out row's frame in the list's coordinates, by page index.
    @ObservationIgnored var rowFrames: [Int: CGRect] = [:]

    func target(_ insertionIndex: Int?) {
        if self.insertionIndex != insertionIndex { self.insertionIndex = insertionIndex }
    }
}

/// One item of a drop on the page list, read.
enum PDFPageListDroppedItem: Equatable {
    /// A PDF file's bytes.
    case pdf(Data)
    /// A file or item that is not a PDF.
    case notPDF
    /// A PDF that could not be read: its app did not deliver it, or it is too large.
    case unreadable
}

/// Why the dropped PDFs' pages could not be inserted.
enum PDFPageListDropError: LocalizedError {
    case notAPDF, passwordProtected, pageNotCopied, notCombined

    var errorDescription: String? {
        switch self {
        case .notAPDF: "This file is not a PDF Graphite can read."
        case .passwordProtected: "This PDF is protected by a password, so its pages can't be inserted."
        case .pageNotCopied: "A page of the dropped PDF could not be copied."
        case .notCombined: "The dropped PDFs could not be put together."
        }
    }
}

/// Reads the PDFs a drop on the page list carries: a PDF from Files or the Finder, or a PDF of the vault dragged from
/// Graphite's sidebar. Item providers are not `Sendable`, so the deciding stays on the main actor; the loading runs on
/// the system's queues and the reading of files off the main actor.
@MainActor
enum PDFPageListDropReader {
    /// What the list is told of: PDFs, file addresses (the Finder's drag says only "a file"), the vault's items, and its
    /// own pages dragged to another place. One destination for all of them: a destination of each row for the pages,
    /// laid over the list's, took every drag over a row, and a PDF let go there was not taken.
    static let acceptedTypes: [UTType] = [.pdf, .fileURL, .graphiteVaultItem, .graphitePDFPage]

    /// The files a drag over the Mac's windows carries, by the addresses on its pasteboard, which the Finder writes: an
    /// item the Finder drags says only "a file" until read. None on the iPad, whose Files says what a file is.
    static func draggedFileAddresses() -> [URL] {
        #if os(macOS)
        NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        #else
        []
        #endif
    }

    /// Whether a drag may carry a PDF, as far as can be told before it is read; the list takes it only then.
    static func mayCarryPDF(_ providers: [NSItemProvider], draggedFileAddresses: [URL]) -> Bool {
        providers.contains { provider in mayBePDF(provider, draggedFileAddresses: draggedFileAddresses) }
    }

    /// An item of Graphite's sidebar that names its file is a PDF by that name; Files offers a PDF as one. A file the
    /// Finder drags is one when the drag's addresses name a PDF; with no address to go by, it counts as one until read.
    static func mayBePDF(_ provider: NSItemProvider, draggedFileAddresses: [URL]) -> Bool {
        if isVaultItem(provider) {
            guard let name = provider.suggestedName, !name.isEmpty else { return true }
            return isPDF(URL(fileURLWithPath: name))
        }
        if provider.registeredContentTypes.contains(where: { type in type.conforms(to: .pdf) }) { return true }
        guard provider.registeredContentTypes.contains(where: { type in type.conforms(to: .fileURL) }) else { return false }
        return draggedFileAddresses.isEmpty || draggedFileAddresses.contains(where: isPDF)
    }

    /// Whether the drag is a page of a PDF's list, which moves within its own list.
    static func carriesPage(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in provider.hasItemConformingToTypeIdentifier(UTType.graphitePDFPage.identifier) }
    }

    /// The page a drag within a list carries.
    static func draggedPage(_ providers: [NSItemProvider]) async -> PDFPageDragItem? {
        guard let provider = providers.first(where: { provider in provider.hasItemConformingToTypeIdentifier(UTType.graphitePDFPage.identifier) }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.graphitePDFPage.identifier) { encoded, _ in
                let page = encoded.flatMap { encoded in try? JSONDecoder().decode(PDFPageDragItem.self, from: encoded) } // Unreadable: no move.
                continuation.resume(returning: page)
            }
        }
    }

    /// Reads every item, in the drop's order.
    static func read(_ providers: [NSItemProvider]) async -> [PDFPageListDroppedItem] {
        var items: [PDFPageListDroppedItem] = []
        for provider in providers {
            items.append(await read(provider))
        }
        return items
    }

    private static func read(_ provider: NSItemProvider) async -> PDFPageListDroppedItem {
        if isVaultItem(provider) {
            let transfer: VaultItemTransfer? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.graphiteVaultItem.identifier) { encoded, _ in
                    let transfer = encoded.flatMap { encoded in try? JSONDecoder().decode(VaultItemTransfer.self, from: encoded) } // Unreadable: nothing read.
                    continuation.resume(returning: transfer)
                }
            }
            guard let location = transfer?.sourceLocation else { return .unreadable }
            return await readFile(at: location)
        }
        if provider.registeredContentTypes.contains(where: { type in type.conforms(to: .pdf) }) {
            return await withCheckedContinuation { continuation in
                // The copy the system makes lasts only as long as the handler, so it is read there.
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { copy, _ in
                    let pdfData = copy.flatMap { copy in try? Self.readPDFFile(at: copy) } // Unreadable or too large: said as unreadable.
                    continuation.resume(returning: pdfData.map(PDFPageListDroppedItem.pdf) ?? .unreadable)
                }
            }
        }
        guard provider.canLoadObject(ofClass: URL.self) else { return .notPDF }
        let address: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { address, _ in continuation.resume(returning: address) }
        }
        guard let address, address.isFileURL else { return .notPDF }
        return await readFile(at: address)
    }

    private static func readFile(at location: URL) async -> PDFPageListDroppedItem {
        guard isPDF(location) else { return .notPDF }
        let data = try? await Task.detached(priority: .userInitiated) { // Unreadable or too large: said as unreadable.
            let hasAccess = location.startAccessingSecurityScopedResource()
            defer { if hasAccess { location.stopAccessingSecurityScopedResource() } }
            return try Self.readPDFFile(at: location)
        }.value
        return data.map(PDFPageListDroppedItem.pdf) ?? .unreadable
    }

    private nonisolated static func readPDFFile(at location: URL) throws -> Data {
        try AtomicFileWriter().read(location, maximumBytes: PDFSession.maximumImportedPDFBytes).data
    }

    private static func isVaultItem(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.graphiteVaultItem.identifier)
    }

    private nonisolated static func isPDF(_ location: URL) -> Bool {
        UTType(filenameExtension: location.pathExtension)?.conforms(to: .pdf) == true
    }

    /// The pages of several PDFs as one PDF, in order, so a drop of them is one undo step.
    static func combined(_ droppedPDFs: [Data]) throws -> Data {
        let documents = try droppedPDFs.map { pdfData in
            guard let document = PDFDocument(data: pdfData) else { throw PDFPageListDropError.notAPDF }
            guard !document.isLocked else { throw PDFPageListDropError.passwordProtected }
            return document
        }
        guard documents.count > 1, let combined = documents.first else { return droppedPDFs.first ?? Data() }
        for document in documents.dropFirst() {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex)?.copy() as? PDFPage else { throw PDFPageListDropError.pageNotCopied }
                combined.insert(page, at: combined.pageCount)
            }
        }
        guard let combinedData = combined.dataRepresentation() else { throw PDFPageListDropError.notCombined }
        return combinedData
    }
}

extension PDFSession {
    /// Inserts the pages of the PDFs dropped onto the page list, in the drop's order, at `insertionIndex`, as one undo
    /// step, and shows the first of them.
    func insertDroppedPDFs(_ droppedPDFs: [Data], at insertionIndex: Int) throws {
        guard !droppedPDFs.isEmpty else { return }
        let pagesData = try PDFPageListDropReader.combined(droppedPDFs)
        let clampedIndex = min(max(0, insertionIndex), pageCount)
        try insertPages(pagesData, at: clampedIndex, actionName: droppedPDFs.count == 1 ? "Insert PDF" : "Insert PDFs")
        go(to: clampedIndex)
    }
}

/// The page list's drop: takes a drag that may carry a PDF, shows where its pages would go, and inserts them; a page of
/// the list dragged to another place in it moves there. A protected PDF (a password, or a signature not given up) takes
/// no drop.
struct PDFPageListDropDelegate: DropDelegate {
    let session: PDFSession
    let commands: PDFPageCommands
    let targeting: PDFPageListDropTargeting

    private func insertionIndex(for info: DropInfo) -> Int {
        PDFPageListInsertion.insertionIndex(atY: info.location.y, rowFrames: targeting.rowFrames, pageCount: session.pageCount)
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard !session.isProtected else { return false }
        let providers = info.itemProviders(for: PDFPageListDropReader.acceptedTypes)
        return PDFPageListDropReader.carriesPage(providers)
            || PDFPageListDropReader.mayCarryPDF(providers, draggedFileAddresses: PDFPageListDropReader.draggedFileAddresses())
    }

    func dropEntered(info: DropInfo) {
        targeting.target(insertionIndex(for: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        targeting.target(insertionIndex(for: info))
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        targeting.target(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let insertionIndex = insertionIndex(for: info)
        targeting.target(nil)
        let providers = info.itemProviders(for: PDFPageListDropReader.acceptedTypes)
        if PDFPageListDropReader.carriesPage(providers) {
            Task { [session, commands] in
                // A page's index means something only in the PDF it came from.
                guard let page = await PDFPageListDropReader.draggedPage(providers), page.sessionIdentifier == session.identifier else { return }
                commands.move(page: page.pageIndex, to: PDFPageListInsertion.moveDestination(ofPage: page.pageIndex, insertedAt: insertionIndex))
            }
            return true
        }
        Task { [session, commands] in
            let items = await PDFPageListDropReader.read(providers)
            let droppedPDFs = items.compactMap { item in if case .pdf(let pdfData) = item { pdfData } else { nil } }
            guard !droppedPDFs.isEmpty else {
                session.errorMessage = items.contains(.unreadable) ? "The dropped PDF could not be read." : "Only a PDF's pages can be put among the pages."
                return
            }
            commands.insertDroppedPDFs(droppedPDFs, at: insertionIndex)
        }
        return true
    }
}

/// The line between two pages of the list where a dragged PDF's pages would go.
struct PDFPageInsertionLine: View {
    let targeting: PDFPageListDropTargeting

    var body: some View {
        if let insertionIndex = targeting.insertionIndex,
           let lineY = PDFPageListInsertion.lineY(forInsertionIndex: insertionIndex, rowFrames: targeting.rowFrames) {
            Capsule()
                .fill(.tint)
                .frame(maxWidth: .infinity)
                .frame(height: 3)
                .padding(.horizontal, 14)
                .offset(y: lineY - 1.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
