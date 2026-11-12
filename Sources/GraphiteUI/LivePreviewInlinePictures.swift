/**
 * File: LivePreviewInlinePictures.swift
 * -------------------------------------
 * Layer: UI
 * Description: While the cursor is on a line of images, Live Preview shows the source of the embed the cursor is in
 *              and draws the line's other pictures among its text, at their sizes, as Obsidian does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore

/// A picture drawn among an image line's text: the decoded pixels its view showed and the size it is drawn at.
/// The styler hides the embed's source and keeps room for the picture after it, as for a formula.
final class InlinePictureLayout: NSObject {
    let image: CGImage
    /// The picture's size in points; it stands on the line's baseline.
    let size: CGSize
    /// Room left on each side of the picture, about the gap `ImageLineFlowLayout` leaves.
    static let horizontalPadding: CGFloat = 1

    init(image: CGImage, size: CGSize) {
        self.image = image
        self.size = size
    }
}

/// One embed of an image line drawn as its picture while the line shows its text.
struct InlinePicture: Equatable {
    /// The embed's source in the note, `![[a.jpg|200]]` or `![alt|200](a.jpg)`.
    let range: NSRange
    let layout: InlinePictureLayout
}

/// Which embeds of the image lines the selection is on are drawn as pictures. A line of images
/// (`LivePreviewBlock.Kind.imageLine`) is one rendered block while the cursor is elsewhere. With
/// the cursor on it, its text shows, and only the embed the cursor is in shows its source, as
/// in Obsidian: every other embed of the line keeps its picture, at its size, in its place
/// among the text, so the arrow keys walk through the line one embed's source at a time.
@MainActor
enum LivePreviewInlinePictures {
    /// The pictures of the image lines in `entries` that `revealedMarkup`'s selection is on,
    /// leaving out the embeds the selection touches, whose source shows. An embed whose
    /// picture no view has decoded yet keeps its text, as before the line showed pictures.
    /// - Parameter thumbnail: The decoded picture of an embed, nil when there is none at hand.
    static func pictures(in entries: [LivePreviewBlockEntry], revealedMarkup: RevealedMarkup, source: NSString, columnWidth: CGFloat,
                         thumbnail: (EmbedReference) -> ReadingThumbnail?) -> [InlinePicture] {
        guard columnWidth > 0 else { return [] }
        let selection = revealedMarkup.selection
        var pictures: [InlinePicture] = []
        for entry in entries[firstIndex(endingAtOrAfter: selection.location, in: entries)...] {
            guard entry.range.location <= NSMaxRange(selection) else { break }
            guard case .imageLine(let pieces) = entry.block.kind,
                  LivePreviewBlockActivity.isActive(blockRange: entry.range, selection: selection, in: source) else { continue }
            for case .image(let embed) in pieces {
                let range = NSRange(location: entry.range.location + embed.range.location, length: embed.range.length)
                guard !revealedMarkup.showsInlineElement(at: range), isEmbed(embed, at: range, in: source),
                      let found = thumbnail(embed) else { continue }
                let pictureSize = size(of: embed, aspectRatio: found.aspectRatio, columnWidth: columnWidth)
                pictures.append(InlinePicture(range: range, layout: InlinePictureLayout(image: found.image, size: pictureSize)))
            }
        }
        return pictures
    }

    /// The picture an image line's view last decoded for `embed`, kept by the reading view's
    /// image cache, where the view found its file.
    static func lastDecodedThumbnail(of embed: EmbedReference, in root: URL) -> ReadingThumbnail? {
        guard let foundImage = LivePreviewEmbedImageLocations.foundImage(for: embed, in: root) else { return nil }
        return ReadingImageCache.shared.latestThumbnail(for: foundImage.location, kind: .block)
    }

    /// The lines whose pictures differ between two sets, which a moving selection restyles whole:
    /// an embed's picture and its source are styled as a unit.
    static func linesChanging(from previousPictures: [InlinePicture], to newPictures: [InlinePicture], in source: NSString) -> [NSRange] {
        let previousRanges = Set(previousPictures.map(\.range)), newRanges = Set(newPictures.map(\.range))
        let changedRanges = previousRanges.symmetricDifference(newRanges).filter { range in NSMaxRange(range) <= source.length }
        let lines = Set(changedRanges.map { range in source.lineRange(for: range) })
        return lines.sorted { leftRange, rightRange in leftRange.location < rightRange.location }
    }

    /// The size an image line's view gives the picture (`LivePreviewEmbedView`): its `|width`,
    /// fitted inside a `|widthxheight`, or the column's width, never wider than the column.
    static func size(of embed: EmbedReference, aspectRatio: CGFloat, columnWidth: CGFloat) -> CGSize {
        let givenWidth = embed.displaySize.map { displaySize in CGFloat(displaySize.fittedWidth(aspectRatio: Double(aspectRatio))) } ?? columnWidth
        let width = max(1, min(givenWidth, columnWidth - 2 * InlinePictureLayout.horizontalPadding))
        return CGSize(width: width, height: aspectRatio > 0 ? width / aspectRatio : width)
    }

    /// Whether the note still has the embed at `range`: an edit moves blocks before it finds
    /// the line's pieces again.
    private static func isEmbed(_ embed: EmbedReference, at range: NSRange, in source: NSString) -> Bool {
        guard range.length >= 3, NSMaxRange(range) <= source.length else { return false }
        return EmbedLocator.embed(at: range.location + 1, in: source)?.range == range
    }

    /// The index of the first entry that ends at or after `location`; `entries` are in note order and do not overlap.
    private static func firstIndex(endingAtOrAfter location: Int, in entries: [LivePreviewBlockEntry]) -> Int {
        var lowerBound = 0, upperBound = entries.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if NSMaxRange(entries[middle].range) < location { lowerBound = middle + 1 } else { upperBound = middle }
        }
        return lowerBound
    }
}

extension MarkdownTextStyler {
    /// Draws each picture inside `styledRange` in place of its embed's source: the source is
    /// hidden, the picture's room is kept after the character before its last, which never
    /// breaks from the last (`]]`, or the `)` after a file name), and the last is raised by
    /// the picture's height so the line is tall enough for it. The note's text is unchanged.
    func drawInlinePictures(_ pictures: [InlinePicture], within styledRange: NSRange, in textStorage: NSTextStorage) {
        guard configuration.mode == .livePreview, drawsConcealedReplacements else { return }
        for picture in pictures where NSMaxRange(picture.range) <= textStorage.length && NSIntersectionRange(picture.range, styledRange) == picture.range {
            let range = picture.range
            conceal(range, in: textStorage)
            textStorage.addAttribute(ConcealedReplacement.pictureAttributeKey, value: picture.layout, range: range)
            textStorage.addAttribute(.kern, value: picture.layout.size.width + 2 * InlinePictureLayout.horizontalPadding,
                                     range: NSRange(location: NSMaxRange(range) - 2, length: 1))
            textStorage.addAttribute(.baselineOffset, value: picture.layout.size.height, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        }
    }
}

extension ConcealedReplacementLayoutFragment {
    /// Draws each picture whose room is on this line, in that room, standing on the baseline.
    func drawInlinePictures(in lineFragment: NSTextLineFragment, lineOrigin: CGPoint, baseline: CGFloat) {
        let attributedString = lineFragment.attributedString
        let wholeString = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(ConcealedReplacement.pictureAttributeKey, in: lineFragment.characterRange) { value, range, _ in
            guard let layout = value as? InlinePictureLayout else { return }
            var pictureRange = NSRange(location: NSNotFound, length: 0)
            _ = attributedString.attribute(ConcealedReplacement.pictureAttributeKey, at: range.location, longestEffectiveRange: &pictureRange, in: wholeString)
            let roomCharacterLocation = NSMaxRange(pictureRange) - 2
            guard pictureRange.length > 2, NSLocationInRange(roomCharacterLocation, lineFragment.characterRange) else { return }
            let roomStartX = lineOrigin.x + lineFragment.locationForCharacter(at: roomCharacterLocation).x
            let frame = CGRect(x: roomStartX + InlinePictureLayout.horizontalPadding, y: baseline - layout.size.height,
                               width: layout.size.width, height: layout.size.height)
            #if canImport(UIKit)
            UIImage(cgImage: layout.image).draw(in: frame)
            #else
            NSImage(cgImage: layout.image, size: frame.size).draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            #endif
        }
    }
}
