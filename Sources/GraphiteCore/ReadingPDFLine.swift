/**
 * File: ReadingPDFLine.swift
 * --------------------------
 * Layer: Core
 * Description: A paragraph line of the reading view that embeds PDFs among pictures or text, cut into a viewer per PDF and
 *              Markdown between them, as Live Preview draws the line (HUNT-351).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// The reading view's blocks for a line such as `![[Lab notebook.pdf#height=200]] ![[Cornell.pdf#height=200]]`.
enum ReadingPDFLine {
    /// The blocks of a paragraph line that embeds PDFs among its pictures or text: each PDF
    /// as its viewer, one under the other, as Live Preview draws the line, and the text and
    /// pictures between them as Markdown, the pictures side by side; each block starts at its
    /// piece's offset in the note. Nil for any other line.
    static func locatedBlocks(of line: String, lineStart: Int) -> [NotePreviewDocument.LocatedBlock]? {
        segments(of: line).map { segments in
            segments.map { segment in
                switch segment {
                case .markdown(let text, let offsetInLine):
                    NotePreviewDocument.LocatedBlock(block: .markdown(text), startOffset: lineStart + offsetInLine,
                                                     lineStartOffsets: [lineStart + offsetInLine], body: [])
                case .pdf(let embed):
                    NotePreviewDocument.LocatedBlock(block: .embed(embed), startOffset: lineStart + embed.range.location,
                                                     lineStartOffsets: [], body: [])
                }
            }
        }
    }

    /// A piece of a paragraph line that embeds PDFs (`segments(of:)`).
    enum Segment: Equatable {
        /// Text and pictures between PDFs, trimmed, with the UTF-16 offset in the line where it starts.
        case markdown(String, offsetInLine: Int)
        case pdf(EmbedReference)
    }

    /// The pieces of a paragraph line that embeds at least one PDF of the vault among other
    /// embeds or text, as `![[Lab notebook.pdf#height=200]] ![[Cornell.pdf#height=200]]`: each
    /// PDF, and the Markdown between them. Nil for any other line, and for a PDF alone on its
    /// line, which is a standalone embed.
    static func segments(of line: String) -> [Segment]? {
        guard let pieces = LivePreviewBlockScanner.imageLinePieces(ofParagraphLine: line) else { return nil }
        let pdfEmbeds = pieces.compactMap { piece -> EmbedReference? in
            guard case .image(let embed) = piece,
                  DocumentKind(fileExtension: (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension) == .pdf else { return nil }
            return embed
        }
        guard !pdfEmbeds.isEmpty else { return nil }
        let source = line as NSString
        var segments: [Segment] = []
        var markdownStart = 0
        func appendMarkdown(upTo end: Int) {
            let untrimmed = source.substring(with: NSRange(location: markdownStart, length: end - markdownStart))
            let text = untrimmed.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            let leadingWhitespace = (untrimmed as NSString).range(of: text).location
            segments.append(.markdown(text, offsetInLine: markdownStart + leadingWhitespace))
        }
        for embed in pdfEmbeds {
            appendMarkdown(upTo: embed.range.location)
            segments.append(.pdf(embed))
            markdownStart = NSMaxRange(embed.range)
        }
        appendMarkdown(upTo: source.length)
        return segments
    }
}
