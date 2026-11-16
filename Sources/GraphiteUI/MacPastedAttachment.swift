/**
 * File: MacPastedAttachment.swift
 * -------------------------------
 * Layer: UI
 * Description: What a paste or a drop on the Mac adds to a note besides text.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import AppKit

/// What a paste or drop on the Mac adds to a note besides text.
enum MacPastedAttachment: Equatable {
    /// A file or folder dragged from Graphite's sidebar, linked where it is.
    case vaultItem(VaultPath)
    /// A file or image saved as an attachment and embedded.
    case file(data: Data, stem: String, fileExtension: String)
    /// A file whose content could not be read.
    case unreadableFile(name: String)

    static let vaultItemType = NSPasteboard.PasteboardType(UTType.graphiteVaultItem.identifier)
    /// Image types saved as they are; any other image is converted to PNG.
    private static let keptImageTypes: [(type: NSPasteboard.PasteboardType, fileExtension: String)] = [
        (.png, "png"), (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"), (NSPasteboard.PasteboardType(UTType.webP.identifier), "webp"),
    ]
    static var pasteboardTypes: [NSPasteboard.PasteboardType] { [vaultItemType, .fileURL, .tiff] + keptImageTypes.map(\.type) }

    /// Whether the pasteboard carries something that becomes an attachment or a link.
    static func isOffered(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [vaultItemType]) != nil
            || pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: [.tiff] + keptImageTypes.map(\.type)) != nil
    }

    /// Vault items first, then files, then an image copied on its own. An image that comes
    /// with text, such as one copied from a web page with its caption, is pasted as text;
    /// one that comes with its address is an image.
    @MainActor
    static func attachments(on pasteboard: NSPasteboard, now: Date = .now, vaultRoot: URL? = nil) -> [MacPastedAttachment] {
        let vaultItems: [MacPastedAttachment] = (pasteboard.pasteboardItems ?? []).compactMap { pasteboardItem in
            guard let data = pasteboardItem.data(forType: vaultItemType),
                  let item = try? JSONDecoder().decode(VaultItemTransfer.self, from: data) else { return nil } // An unreadable item adds nothing.
            // A link to an item of another window's vault would name whatever has that path here.
            guard let path = item.path(inVaultAt: vaultRoot) else { return .unreadableFile(name: item.path) }
            return .vaultItem(path)
        }
        if !vaultItems.isEmpty { return vaultItems }
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !fileURLs.isEmpty {
            return fileURLs.map { fileURL in
                guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return .unreadableFile(name: fileURL.lastPathComponent) }
                let fileExtension = fileURL.pathExtension.isEmpty ? "bin" : fileURL.pathExtension
                return .file(data: data, stem: fileURL.deletingPathExtension().lastPathComponent, fileExtension: fileExtension)
            }
        }
        let hasText = pasteboard.availableType(from: [.string]) != nil
        let hasAddress = pasteboard.availableType(from: [.URL]) != nil
        guard !hasText || hasAddress, let (data, fileExtension) = imageData(on: pasteboard) else { return [] }
        return [.file(data: data, stem: WorkspaceModel.pastedImageStem(at: now), fileExtension: fileExtension)]
    }

    private static func imageData(on pasteboard: NSPasteboard) -> (Data, String)? {
        for (type, fileExtension) in keptImageTypes {
            if let data = pasteboard.data(forType: type) { return (data, fileExtension) }
        }
        guard let tiffData = pasteboard.data(forType: .tiff),
              let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) else { return nil }
        return (pngData, "png")
    }
}
#endif
