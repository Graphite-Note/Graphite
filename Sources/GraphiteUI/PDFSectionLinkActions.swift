/**
 * File: PDFSectionLinkActions.swift
 * ---------------------------------
 * Layer: UI
 * Description: What a PDF pane asks of its workspace for the sections of notes its pages link to: a section's
 *              picture and address for a drop, and opening a section from the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import GraphiteCore

/// Why a section could not be placed on a page or drawn.
enum SectionLinkError: LocalizedError, Equatable {
    /// The link names no note of the vault that is open.
    case noteNotInVault(String)
    /// The vault has no name a link can carry.
    case vaultNotNamed
    /// The section could not be drawn as a picture.
    case notDrawn

    var errorDescription: String? {
        switch self {
        case .noteNotInVault(let note): "“\(note)” is not a note of this vault."
        case .vaultNotNamed: "This vault's sections can't be linked."
        case .notDrawn: "This section could not be drawn."
        }
    }
}

/// A section's picture, ready to place on a page.
struct PreparedSectionPicture: Sendable {
    /// PNG data of the section as the reading view draws it.
    let imageData: Data
    /// Its width at the size it was drawn for, in points of paper.
    let widthInPoints: CGFloat
    /// The section's address the page links to (`SectionLink.openingURL`).
    let address: String
    /// A digest of the section's text it was drawn from (`PDFPicture.sectionTextDigest`).
    let textDigest: String
}

/// The workspace's part in a PDF's section links. The PDF knows its pages; the workspace knows
/// the vault's notes, their text as it is now, and the other side of the split.
struct PDFSectionLinkActions {
    /// The folder of the vault the PDF is in; a section dragged from another vault's window is refused.
    let vaultRoot: URL?
    /// Draws a section and gives its address, for a drop.
    let prepare: @MainActor (SectionLink) async throws -> PreparedSectionPicture
    /// The digest of a section's text as it is now, to tell whether its picture is out of date.
    let currentDigest: @MainActor (SectionLink) async -> String?
    /// Opens a section on the other side of the split.
    let open: @MainActor (SectionLink) -> Void
    /// Opens a section's address a page links to: a section of this vault as `open` does, one
    /// of another vault as a link from another app would.
    let openAddress: @MainActor (URL) -> Void
}
