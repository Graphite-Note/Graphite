/**
 * File: PDFPictureDropReader.swift
 * --------------------------------
 * Layer: UI
 * Description: Reads the pictures a drop on an iPad PDF page carries from its item providers: images from Photos,
 *              Files and Safari, and image files dragged from Graphite's own sidebar and library.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import GraphiteCore

/// One item of a drop on a PDF page, read.
enum PDFDroppedItem: Equatable {
    /// An image's own bytes, which the page's picture is made from.
    case picture(Data)
    /// An item the page does not take, by its kind.
    case refused(PDFDroppedItemKind)
    /// A picture that could not be read: its app did not deliver it, or it is too large.
    case unreadable
}

/// Reads what a drop on a PDF page carries. Item providers are not `Sendable`, so the
/// deciding stays on the main actor; the loading runs on the system's queues.
@MainActor
enum PDFPictureDropReader {
    /// Picture types taken before another representation of the same picture: Photos offers
    /// a photo as HEIC and as JPEG, and a JPEG is kept as it is where a HEIC is encoded again.
    private static let preferredPictureTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .tiff]

    /// What an item is, from the types it offers. An item of Graphite's sidebar or library
    /// says which file it is only once read, so it counts as a picture until then.
    static func kind(of provider: NSItemProvider) -> PDFDroppedItemKind {
        if isVaultItem(provider) { return .picture }
        if provider.canLoadObject(ofClass: UIImage.self) && !provider.registeredContentTypes.contains(where: { type in type.conforms(to: .pdf) }) {
            return .picture
        }
        return PDFPictureDropPlan.kind(ofTypes: provider.registeredContentTypes)
    }

    /// Reads every item, in the drop's order.
    static func read(_ providers: [NSItemProvider]) async -> [PDFDroppedItem] {
        var items: [PDFDroppedItem] = []
        for provider in providers {
            items.append(await read(provider))
        }
        return items
    }

    private static func read(_ provider: NSItemProvider) async -> PDFDroppedItem {
        if isVaultItem(provider) { return await vaultPicture(of: provider) }
        let kind = kind(of: provider)
        guard kind == .picture else { return .refused(kind) }
        let imageTypes = provider.registeredContentTypes.filter { type in type.conforms(to: .image) }
        let type = preferredPictureTypes.first(where: { preferred in imageTypes.contains(preferred) }) ?? imageTypes.first
        if let type, let imageData = await data(of: provider, type: type) { return .picture(imageData) }
        return await encodedImage(of: provider).map(PDFDroppedItem.picture) ?? .unreadable
    }

    private static func isVaultItem(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.graphiteVaultItem.identifier)
    }

    private static func data(of provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { imageData, _ in
                // A picture its app does not deliver, or one too large to place, is not read.
                continuation.resume(returning: imageData.flatMap { loaded in loaded.count <= PickedImageFiles.maximumImageBytes ? loaded : nil })
            }
        }
    }

    /// An image offered only as an object, such as a picture of another app's own: encoded as PNG.
    private static func encodedImage(of provider: NSItemProvider) async -> Data? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        let image: UIImage? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in continuation.resume(returning: object as? UIImage) }
        }
        guard let image else { return nil }
        return await Task.detached(priority: .userInitiated) { image.pngData() }.value
    }

    /// An image file of the vault, dragged from the sidebar or the library: read from where it
    /// is, never moved. Any other file the item names is refused by its kind.
    private static func vaultPicture(of provider: NSItemProvider) async -> PDFDroppedItem {
        let transfer: VaultItemTransfer? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.graphiteVaultItem.identifier) { encoded, _ in
                continuation.resume(returning: encoded.flatMap { encoded in try? JSONDecoder().decode(VaultItemTransfer.self, from: encoded) }) // An unreadable item is no picture.
            }
        }
        guard let location = transfer?.sourceLocation else { return .unreadable }
        let kind = PDFPictureDropPlan.kind(ofFileAt: location)
        guard kind == .picture else { return .refused(kind) }
        do {
            return .picture(try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: location) }.value)
        } catch {
            return .unreadable
        }
    }
}
#endif
