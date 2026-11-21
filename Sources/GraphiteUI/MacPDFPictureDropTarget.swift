/**
 * File: MacPDFPictureDropTarget.swift
 * -----------------------------------
 * Layer: UI
 * Description: Takes pictures dropped onto the pages of a Mac PDF view: the Finder's file addresses, the files
 *              Photos and Mail promise, and image data (a picture dragged from Safari), each placed where it landed;
 *              a protected or signed PDF takes none, and a dropped PDF file is refused with the reason in the banner.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 21/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore

/// The drop handling of a Mac PDF pane's view (`GraphiteMacPDFView`), which hands it its
/// dragging events. A PDF embedded in a note has none: the note takes the drop.
@MainActor
final class MacPDFPictureDropTarget {
    private let session: PDFSession
    private weak var view: PDFView?
    /// Called once a drop has placed its pictures, the last one selected: the markup row
    /// chooses its Images tool, so the picture can be moved and resized at once.
    var picturesWerePlaced: () -> Void = {}
    /// The workspace's part in section links; nil where the PDF takes none.
    var sectionLinks: PDFSectionLinkActions?

    /// Image data a drag can carry without a file: what Safari and other apps put on the pasteboard.
    static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]
    /// What the view registers for: files by address and by promise, and image data.
    static var pasteboardTypes: [NSPasteboard.PasteboardType] {
        [sectionLinkType, MacPastedAttachment.vaultItemType] + MacDroppedFiles.pasteboardTypes + imagePasteboardTypes
    }
    /// A note's section dragged from the editor (`SectionLinkTransfer`).
    static let sectionLinkType = NSPasteboard.PasteboardType(UTType.graphiteSectionLink.identifier)

    init(session: PDFSession, view: PDFView) {
        self.session = session
        self.view = view
    }

    // MARK: Deciding

    /// What each dragged item is: files by their names' extensions or promised types, else
    /// one picture when the pasteboard holds image data.
    static func kinds(on pasteboard: NSPasteboard) -> [PDFDroppedItemKind] {
        if !sectionLinks(on: pasteboard).isEmpty { return [.sectionLink] }
        let addresses = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !addresses.isEmpty { return addresses.map(PDFPictureDropPlan.kind(ofFileAt:)) }
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        if !receivers.isEmpty {
            return receivers.map { receiver in PDFPictureDropPlan.kind(ofTypes: receiver.fileTypes.compactMap { identifier in UTType(identifier) }) }
        }
        return imageData(on: pasteboard) == nil ? [] : [.picture]
    }

    /// Whether the PDF takes a drag: it can be changed, and the drag carries a picture, or a
    /// note's section where the workspace draws sections.
    func takesDrop(from pasteboard: NSPasteboard) -> Bool {
        let kinds = Self.kinds(on: pasteboard)
        return !session.isProtected && (kinds.contains(.picture) || (kinds.contains(.sectionLink) && sectionLinks != nil))
    }

    /// The sections a drag carries: one dragged from the editor, or a note of the file tree,
    /// which links the whole note.
    static func sectionLinks(on pasteboard: NSPasteboard) -> [SectionLinkTransfer] {
        let decoder = JSONDecoder()
        let items = pasteboard.pasteboardItems ?? []
        let dragged = items.compactMap { item in item.data(forType: sectionLinkType) }
            .compactMap { encoded in try? decoder.decode(SectionLinkTransfer.self, from: encoded) } // Unreadable: no section.
        if !dragged.isEmpty { return dragged }
        return items.compactMap { item in item.data(forType: MacPastedAttachment.vaultItemType) }
            .compactMap { encoded in try? decoder.decode(VaultItemTransfer.self, from: encoded) } // Unreadable: no note.
            .compactMap { transfer in
                guard let notePath = try? VaultPath(transfer.path), DocumentKind(path: notePath) == .markdown else { return nil } // No note.
                return SectionLinkTransfer(link: SectionLink(notePath: notePath, subpath: nil), vaultRoot: transfer.vaultRoot)
            }
    }

    /// The pasteboard's image as bytes ImageIO reads: PNG or JPEG as they are, TIFF as PNG.
    private static func imageData(on pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) { return pngData }
        if let jpegData = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) { return jpegData }
        guard let tiffData = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: Dragging

    /// A copy ("+" on the pointer) for a picture over a page. A drag of PDF files alone gets the
    /// plain pointer of a generic operation instead of none: AppKit hands the drop over only after
    /// an operation that is not none, and the drop is where the banner says why it is refused.
    func draggingUpdated(_ draggingInfo: any NSDraggingInfo) -> NSDragOperation {
        guard let view, view.page(for: view.convert(draggingInfo.draggingLocation, from: nil), nearest: true) != nil else { return [] }
        if takesDrop(from: draggingInfo.draggingPasteboard) { return .copy }
        guard isRefusedWithReason(draggingInfo.draggingPasteboard) else { return [] }
        return draggingInfo.draggingSourceOperationMask.intersection(.generic)
    }

    /// Whether a drag the PDF does not take is one a person expects to land, so a drop says why
    /// not in the banner: PDF files, onto a PDF that can be changed.
    private func isRefusedWithReason(_ pasteboard: NSPasteboard) -> Bool {
        !session.isProtected && Self.kinds(on: pasteboard).contains(.pdfDocument)
    }

    /// Takes the drop when it carries a picture; the pictures are read and placed after. A drop
    /// of PDF files is refused with the reason in the banner.
    func performDrop(_ draggingInfo: any NSDraggingInfo) -> Bool {
        let pasteboard = draggingInfo.draggingPasteboard
        guard let view, let location = view.dropLocation(atViewPoint: view.convert(draggingInfo.draggingLocation, from: nil)) else { return false }
        guard takesDrop(from: pasteboard) else {
            if isRefusedWithReason(pasteboard) { session.reportRefusedDrop(of: Self.kinds(on: pasteboard)) }
            return false
        }
        let sections = Self.sectionLinks(on: pasteboard)
        if let sectionLinks, !sections.isEmpty {
            // A block dragged from the editor gets the identifier its link names.
            (draggingInfo.draggingSource as? MarkdownMacTextView)?.prepareSectionDrag()
            Task { await placeSections(sections, actions: sectionLinks, at: location) }
            return true
        }
        let imageOnPasteboard = Self.imageData(on: pasteboard)
        Task { await placePictures(from: pasteboard, imageOnPasteboard: imageOnPasteboard, at: location) }
        return true
    }

    /// Places each section of the vault the PDF is in where it landed; the last is selected.
    ///
    /// - Returns: How many sections were placed.
    @discardableResult
    func placeSections(_ sections: [SectionLinkTransfer], actions: PDFSectionLinkActions, at location: PDFDropLocation) async -> Int {
        let ownSections = sections.filter { transfer in transfer.isInVault(at: actions.vaultRoot) }
        guard !ownSections.isEmpty else {
            session.errorMessage = "A section of a note in another vault can't be linked from this PDF."
            return 0
        }
        var placedCount = 0
        for transfer in ownSections where await session.placeDroppedSectionLink(transfer.link, actions: actions, at: location) { placedCount += 1 }
        if placedCount > 0 { picturesWerePlaced() }
        return placedCount
    }

    /// Reads the files the drop carries, or else its image, and places the pictures.
    ///
    /// - Returns: How many pictures were placed.
    @discardableResult
    func placePictures(from pasteboard: NSPasteboard, imageOnPasteboard: Data?, at location: PDFDropLocation) async -> Int {
        let files = await MacDroppedFiles.read(from: pasteboard)
        let batch = DroppedFileBatch(files: files)
        defer { batch.discard() }
        let pictureLocations = batch.locations.filter { location in PDFPictureDropPlan.kind(ofFileAt: location) == .picture }
        var imagesData: [Data] = []
        for pictureLocation in pictureLocations {
            do {
                imagesData.append(try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: pictureLocation) }.value)
            } catch {
                session.reportFailedChange(error)
            }
        }
        if files.isEmpty, let imageOnPasteboard { imagesData.append(imageOnPasteboard) }
        guard !imagesData.isEmpty else {
            session.reportRefusedDrop(of: batch.locations.map(PDFPictureDropPlan.kind(ofFileAt:)))
            return 0
        }
        let placedCount = await session.placeDroppedPictures(imagesData, at: location)
        if placedCount > 0 { picturesWerePlaced() }
        return placedCount
    }
}
#endif
