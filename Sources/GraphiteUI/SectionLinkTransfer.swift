/**
 * File: SectionLinkTransfer.swift
 * -------------------------------
 * Layer: UI
 * Description: A section of a note dragged out of the editor: the link a PDF page turns into the section's picture,
 *              carried beside the dragged text, and the block identifier it gives a block only once it is dropped.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import UniformTypeIdentifiers
import GraphiteCore

/// The section a drag from a note links to, as a drag inside Graphite carries it. The text the
/// drag carries for other places (another note, another app) is unchanged.
struct SectionLinkTransfer: Codable, Equatable {
    let note: String
    let subpath: String?
    /// The folder of the vault the note is in, so a page in a window on another vault refuses it.
    let vaultRoot: URL?

    init(link: SectionLink, vaultRoot: URL?) {
        note = link.note
        subpath = link.subpath
        self.vaultRoot = vaultRoot
    }

    var link: SectionLink { SectionLink(note: note, subpath: subpath) }

    /// Whether the section is in the vault at `root`; a drag that does not say is.
    func isInVault(at root: URL?) -> Bool {
        guard let vaultRoot, let root else { return true }
        return vaultRoot.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Adds the transfer to a drag item's provider. `prepare`, run on the main actor when the
    /// item is first read, gives a block its identifier, so a drag that lands elsewhere, or
    /// nowhere, leaves the note as it was.
    static func register(_ transfer: SectionLinkTransfer, on provider: NSItemProvider, prepare: @escaping @MainActor @Sendable () -> Void) {
        guard let encoded = try? JSONEncoder().encode(transfer) else { return } // Two strings and an address always encode.
        provider.registerDataRepresentation(forTypeIdentifier: UTType.graphiteSectionLink.identifier, visibility: .ownProcess) { completion in
            Task { @MainActor in
                prepare()
                completion(encoded, nil)
            }
            return nil
        }
    }

    /// The transfer an item provider carries, if it carries one. On the main actor, as the
    /// drop's other readers: item providers are not `Sendable`.
    @MainActor
    static func load(from provider: NSItemProvider) async -> SectionLinkTransfer? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.graphiteSectionLink.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.graphiteSectionLink.identifier) { encoded, _ in
                let transfer = encoded.flatMap { encoded in try? JSONDecoder().decode(SectionLinkTransfer.self, from: encoded) } // Unreadable: no section.
                continuation.resume(returning: transfer)
            }
        }
    }
}

extension UTType {
    /// Declared in the app's Info.plist; used only for drags inside Graphite.
    static let graphiteSectionLink = UTType(exportedAs: "com.graphite.study.section-link")
}
