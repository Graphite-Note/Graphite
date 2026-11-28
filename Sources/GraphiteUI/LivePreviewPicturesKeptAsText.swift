/**
 * File: LivePreviewPicturesKeptAsText.swift
 * -----------------------------------------
 * Layer: UI
 * Description: The pictures of the lines Live Preview keeps as text although they embed pictures, a quote's and a
 *              task's: their embeds, found again only when the text changes, and each picture looked up and decoded
 *              once, as an image line's view does, for the editor to draw among the line's text (HUNT-380).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import Foundation
import GraphiteCore

/// The embeds of quotes and tasks in a note, and the lookups of their pictures, for one editor.
@MainActor
final class LivePreviewPicturesKeptAsText {
    /// The embeds, found again only when the text or its blocks changed.
    private var cache: (revision: Int, sourceLength: Int, embeds: [EmbedReference])?
    /// The targets whose picture is being found, or was not found.
    private var lookedUpTargets: Set<String> = []

    /// The picture embeds of quotes and tasks outside the rendered blocks, their ranges counted in `source`.
    func embeds(in source: NSString, revision: Int, blockEntries: [LivePreviewBlockEntry]) -> [EmbedReference] {
        if let cache, cache.revision == revision, cache.sourceLength == source.length { return cache.embeds }
        let embeds = LivePreviewInlinePictures.embedsKeptAsText(in: source, outside: blockEntries)
        cache = (revision, source.length, embeds)
        return embeds
    }

    /// Finds and decodes the picture of `embed`, then tells `found` its target. Each target is looked up once while the
    /// editor lives; a file found later shows when the note is opened again.
    func findPicture(of embed: EmbedReference, environment: LivePreviewEnvironment, columnWidth: CGFloat,
                     found: @escaping @MainActor (String) -> Void) {
        guard lookedUpTargets.insert(embed.target).inserted else { return }
        let displayPixelWidth = Int((columnWidth * 3).rounded())
        Task { @MainActor in
            guard let path = await environment.resolve(embed.target, embed.isWiki), DocumentKind(path: path) == .image,
                  let location = try? path.url(in: environment.root), // A path outside the vault has no picture to draw.
                  case .found = await LivePreviewEmbedImageLocations.lookUpPicture(for: embed, path: path, location: location, in: environment.root,
                                                                                   displayPixelWidth: displayPixelWidth) else { return }
            found(embed.target)
        }
    }
}
