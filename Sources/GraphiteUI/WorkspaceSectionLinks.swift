/**
 * File: WorkspaceSectionLinks.swift
 * ---------------------------------
 * Layer: UI
 * Description: A note's sections linked from PDF pages: the address a section's picture links to, the picture drawn
 *              from the note as it is now, and opening the section from the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

extension WorkspaceModel {
    /// Obsidian's address of a section, naming the vault by its folder's name as Obsidian's
    /// links do, so Obsidian and other PDF readers follow it as Graphite does.
    func sectionLinkAddress(for link: SectionLink) -> String? {
        link.openingURL(inVaultNamed: title)?.absoluteString
    }

    /// The note a section link names, resolved as a link from the vault's top.
    func notePath(of link: SectionLink) async -> VaultPath? {
        guard let topLevelSource = try? VaultPath("Link.md") else { return nil } // A constant, valid path.
        return await resolveLink(link.note, from: topLevelSource)
    }

    /// The section's picture and address, for a page it is dropped on.
    func preparedSectionPicture(for link: SectionLink) async throws -> PreparedSectionPicture {
        guard let address = sectionLinkAddress(for: link) else { throw SectionLinkError.vaultNotNamed }
        guard let notePath = await notePath(of: link), let noteText = await currentText(of: notePath) else {
            throw SectionLinkError.noteNotInVault(link.note)
        }
        let imageData = try await sectionPictureData(for: link, notePath: notePath, noteText: noteText)
        let pixelWidth = PictureNaturalSize.measure(ofImageData: imageData)?.shownPixelSize.width ?? 0
        return PreparedSectionPicture(imageData: imageData, widthInPoints: CGFloat(pixelWidth) / SectionPictureRendering.pixelsPerPoint, address: address,
                                      textDigest: SectionLink.textDigest(of: link.sectionText(inNoteText: noteText)))
    }

    /// The digest of the section's text as it is now (`SectionLink.textDigest`); nil when its
    /// note is not in the vault, whose picture is then left as it is.
    func currentSectionTextDigest(for link: SectionLink) async -> String? {
        guard let notePath = await notePath(of: link), let noteText = await currentText(of: notePath) else { return nil }
        return SectionLink.textDigest(of: link.sectionText(inNoteText: noteText))
    }

    /// The section's picture, drawn from the note's text as it is now, unsaved changes
    /// included. A section the note no longer has is drawn as Obsidian's message for it.
    private func sectionPictureData(for link: SectionLink, notePath: VaultPath, noteText: String) async throws -> Data {
        guard let vault = ReadingVault(folderAccess?.root, index, store: store) else {
            throw SectionLinkError.noteNotInVault(link.note)
        }
        var configuration = ReadingConfiguration()
        configuration.usesStrictLineBreaks = vaultSettings.usesStrictLineBreaks
        configuration.colorsEnabled = preferences.isEnabled(.colors)
        configuration.paletteHexByName = preferences.colorPaletteHexByName
        let appearance = NotePDFAppearance(typography: noteTypography, codeColorTheme: preferences.codeColorTheme, accent: preferences.accentColor)
        return try await SectionPictureRendering.pictureData(of: SectionPictureSource(link: link, notePath: notePath, noteText: noteText, vault: vault,
                                                                                      readingConfiguration: configuration, appearance: appearance))
    }

    /// Opens the address of a section a page links to: in this vault beside the PDF, in another
    /// vault as a link from another app opens it.
    func openSectionAddress(_ url: URL) async {
        if let link = SectionLink(openingURL: url), SectionLink.vaultName(ofOpeningURL: url).map(isCurrentVault(named:)) ?? true {
            await openSection(link)
        } else {
            await handle(url)
        }
    }

    /// Opens the section a page links to on the other side of the split, the PDF keeping its own.
    func openSection(_ link: SectionLink) async {
        guard let topLevelSource = try? VaultPath("Link.md") else { return } // A constant, valid path.
        await follow(link.linkText, from: topLevelSource, placement: .otherGroup)
    }
}
