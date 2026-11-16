/**
 * File: EmbedWidthEditing.swift
 * -----------------------------
 * Layer: Core
 * Description: Writes the width an image embed is shown at into its source, as Obsidian does when
 *              an image's corner is dragged: `![[image.png|300]]` or `![Caption|300](image.png)`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

public enum EmbedWidthEditing {
    /// `source` with the first embed in it shown `width` points wide, or nil when its first
    /// embed is not of `target` (the note changed under the drag) or `width` is not a size
    /// Obsidian reads. A size already given is replaced, height and all, so the image keeps
    /// its shape; a caption is kept before the size. Nothing else of `source` changes.
    public static func settingWidth(_ width: Int, ofEmbedOf target: String, in source: String) -> String? {
        guard width > 0, EmbedDisplaySize.parse(label: String(width)) != nil else { return nil }
        let text = source as NSString
        let start = text.range(of: "![")
        guard start.location != NSNotFound, let embed = EmbedLocator.embed(at: start.location + 1, in: text),
              embed.range.location == start.location, embed.target == target else { return nil }
        let embedText = text.substring(with: embed.range)
        let rewritten = embed.isWiki ? wikiEmbed(embedText, width: width) : markdownEmbed(embedText, width: width)
        return rewritten.map { rewritten in text.replacingCharacters(in: embed.range, with: rewritten) }
    }

    /// `![[target]]`, `![[target|label]]`: the target is kept as written, escaped `\|` and all.
    private static func wikiEmbed(_ embedText: String, width: Int) -> String? {
        guard embedText.hasPrefix("![["), embedText.hasSuffix("]]") else { return nil }
        let content = embedText.dropFirst(3).dropLast(2)
        guard let separator = content.firstIndex(of: "|") else { return "![[" + content + "|\(width)]]" }
        let label = String(content[content.index(after: separator)...])
        return "![[" + content[..<separator] + "|" + labelWithWidth(label, width: width) + "]]"
    }

    /// `![label](destination)`: the label holds no `]`, so it ends at the first `](`.
    private static func markdownEmbed(_ embedText: String, width: Int) -> String? {
        guard embedText.hasPrefix("!["), let labelEnd = embedText.range(of: "](") else { return nil }
        let label = String(embedText[embedText.index(embedText.startIndex, offsetBy: 2)..<labelEnd.lowerBound])
        return "![" + labelWithWidth(label, width: width) + embedText[labelEnd.lowerBound...]
    }

    /// The label with its size, the part after its last `|`, set to `width`: a label that is
    /// only a caption keeps it, an empty one becomes the width alone.
    static func labelWithWidth(_ label: String, width: Int) -> String {
        if label.trimmingCharacters(in: .whitespaces).isEmpty { return String(width) }
        var parts = label.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if let last = parts.last, EmbedDisplaySize.parse(label: last) != nil {
            parts[parts.count - 1] = String(width)
            return parts.joined(separator: "|")
        }
        return label + "|\(width)"
    }
}
