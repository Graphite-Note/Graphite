/**
 * File: MacPDFPictureDropTarget.swift
 * -----------------------------------
 * Layer: UI
 * Description: Takes pictures dropped onto the pages of a Mac PDF view: the Finder's file addresses, the files
 *              Photos and Mail promise, and image data (a picture dragged from Safari), each placed where it landed;
 *              a protected or signed PDF, and a PDF file, take none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
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

    /// Image data a drag can carry without a file: what Safari and other apps put on the pasteboard.
    static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]
    /// What the view registers for: files by address and by promise, and image data.
    static var pasteboardTypes: [NSPasteboard.PasteboardType] { MacDroppedFiles.pasteboardTypes + imagePasteboardTypes }

    init(session: PDFSession, view: PDFView) {
        self.session = session
        self.view = view
    }

    // MARK: Deciding

    /// What each dragged item is: files by their names' extensions or promised types, else
    /// one picture when the pasteboard holds image data.
    static func kinds(on pasteboard: NSPasteboard) -> [PDFDroppedItemKind] {
        let addresses = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !addresses.isEmpty { return addresses.map(PDFPictureDropPlan.kind(ofFileAt:)) }
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        if !receivers.isEmpty {
            return receivers.map { receiver in PDFPictureDropPlan.kind(ofTypes: receiver.fileTypes.compactMap { identifier in UTType(identifier) }) }
        }
        return imageData(on: pasteboard) == nil ? [] : [.picture]
    }

    /// Whether the PDF takes a drag: it can be changed, and the drag carries a picture.
    func takesDrop(from pasteboard: NSPasteboard) -> Bool {
        !session.isProtected && Self.kinds(on: pasteboard).contains(.picture)
    }

    /// The pasteboard's image as bytes ImageIO reads: PNG or JPEG as they are, TIFF as PNG.
    private static func imageData(on pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) { return pngData }
        if let jpegData = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) { return jpegData }
        guard let tiffData = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: Dragging

    func draggingUpdated(_ draggingInfo: any NSDraggingInfo) -> NSDragOperation {
        guard let view, takesDrop(from: draggingInfo.draggingPasteboard),
              view.page(for: view.convert(draggingInfo.draggingLocation, from: nil), nearest: true) != nil else { return [] }
        return .copy
    }

    /// Takes the drop when it carries a picture; the pictures are read and placed after.
    func performDrop(_ draggingInfo: any NSDraggingInfo) -> Bool {
        guard let view, takesDrop(from: draggingInfo.draggingPasteboard),
              let location = view.dropLocation(atViewPoint: view.convert(draggingInfo.draggingLocation, from: nil)) else { return false }
        let pasteboard = draggingInfo.draggingPasteboard
        let imageOnPasteboard = Self.imageData(on: pasteboard)
        Task { await placePictures(from: pasteboard, imageOnPasteboard: imageOnPasteboard, at: location) }
        return true
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
