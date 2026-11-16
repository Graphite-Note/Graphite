/**
 * File: EmbedReference.swift
 * --------------------------
 * Layer: Core
 * Description: An embed written in note source: its target, its display size and the text in its brackets.
 *
 * Authors: Bahey Shalash, felixchvl
 * Version: 0.2
 * Date: 16/11/2026
 */

import Foundation

/// An embed such as `![[Drawing.png|400]]` or `![](Drawing.png)` in note source.
public struct EmbedReference: Equatable, Sendable {
    public let target: String
    public let isWiki: Bool
    /// Obsidian's display size from `![[image.png|400]]` or `|400x300`.
    public let displaySize: EmbedDisplaySize?
    public let range: NSRange
    /// What a Markdown embed's brackets hold (`![label](target)`), such as a video's title;
    /// nil for a wikilink embed.
    public let label: String?

    public init(target: String, isWiki: Bool, displaySize: EmbedDisplaySize?, range: NSRange, label: String? = nil) {
        self.target = target
        self.isWiki = isWiki
        self.displaySize = displaySize
        self.range = range
        self.label = label
    }

    /// The width given for the image, in points, before fitting any height.
    public var displayWidth: Double? { displaySize?.width }
    /// Whether the embed is a web image (`![](https://…)`), which is not a vault file. Only
    /// the destination counts, not a title written after it.
    var isRemoteImage: Bool {
        let destination = target.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? target
        return !isWiki && URL(string: destination)?.scheme != nil
    }

    /// Whether the embed alone on its line is a block of its own in Live Preview and the reading
    /// view: a vault file, or a YouTube video shown as a card. A web image stays Markdown.
    var isBlockOfItsOwn: Bool { !isRemoteImage || WebVideo(embed: self) != nil }
}
