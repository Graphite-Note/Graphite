/**
 * File: SectionPictureRendering.swift
 * -----------------------------------
 * Layer: UI
 * Description: The picture of a note's section placed on a PDF page: the section drawn as the reading view draws it,
 *              on paper, through the note's PDF renderer, cut to its text and kept as a PNG.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
import GraphiteApple

/// What a section's picture is drawn from: the note's text as it is now, and how the vault
/// reads and draws notes.
struct SectionPictureSource {
    let link: SectionLink
    let notePath: VaultPath
    /// The note's whole text, frontmatter included.
    let noteText: String
    let vault: ReadingVault
    let readingConfiguration: ReadingConfiguration
    let appearance: NotePDFAppearance
}

/// Draws a section of a note as a picture for a PDF page. The section is laid out by the
/// note's PDF renderer on an A5 page with small margins, so its text is about the size of a
/// page's own; only its first page is kept, as a preview, cut below its last line.
@MainActor
enum SectionPictureRendering {
    /// Pixels per point of paper: text stays sharp with the page zoomed to three times.
    static let pixelsPerPoint: CGFloat = 3
    /// Paper kept below the last line and above the first, in points.
    static let paddingPoints: CGFloat = 12
    /// The frame drawn around the picture, so it reads as a card linked to the note on a white
    /// page: its width in points and its grey.
    static let frameWidthPoints: CGFloat = 1
    static let frameGrey: CGFloat = 0.78
    /// The PDF renderer's options for a section: no title, no properties, a small page.
    static var options: NotePDFOptions {
        var options = NotePDFOptions()
        options.includesFileNameAsTitle = false
        options.includesProperties = false
        options.pageSize = .a5
        options.margins = .small
        return options
    }

    /// The section's picture as PNG data. A section the note no longer has is drawn as
    /// Obsidian's message for it, so the page says so instead of showing an old picture.
    static func pictureData(of source: SectionPictureSource) async throws -> Data {
        let markdown = source.link.sectionText(inNoteText: source.noteText)
            // The section's name in code, so its `#` does not read as a tag.
            ?? "> Unable to find section `#\(source.link.subpath ?? "")` in \(source.notePath.stem)"
        let pdfSource = NotePDFSource(text: markdown, path: source.notePath, vault: source.vault, readingConfiguration: source.readingConfiguration,
                                      title: source.link.title, appearance: source.appearance)
        let pdf = try await NotePDFRenderer(source: pdfSource, options: options).render(pageLimit: 1) { _ in }
        guard let page = PDFDocument(data: pdf.data)?.page(at: 0), let image = croppedPicture(of: page) else {
            throw SectionLinkError.notDrawn
        }
        return try ImageEncoding.pngData(from: image)
    }

    /// The page drawn on white at `pixelsPerPoint`, cut to the rows that hold something, with
    /// `paddingPoints` of paper above and below.
    static func croppedPicture(of page: PDFPage) -> CGImage? {
        let pageBox = page.bounds(for: .mediaBox)
        let width = Int((pageBox.width * pixelsPerPoint).rounded())
        let height = Int((pageBox.height * pixelsPerPoint).rounded())
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage(), let rows = inkedRows(of: context, width: width, height: height) else { return nil }
        let padding = Int((paddingPoints * pixelsPerPoint).rounded())
        // The context's first row in memory is the top of the picture.
        let top = max(rows.lowerBound - padding, 0)
        let bottom = min(rows.upperBound + padding, height)
        guard let cropped = image.cropping(to: CGRect(x: 0, y: top, width: width, height: bottom - top)) else { return nil }
        return framed(cropped, colorSpace: colorSpace)
    }

    /// The picture with a thin grey frame along its edges.
    private static func framed(_ image: CGImage, colorSpace: CGColorSpace) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        let lineWidth = frameWidthPoints * pixelsPerPoint
        context.setStrokeColor(CGColor(srgbRed: frameGrey, green: frameGrey, blue: frameGrey, alpha: 1))
        context.setLineWidth(lineWidth)
        context.stroke(bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        return context.makeImage()
    }

    /// The first and last rows (from the top) with a pixel darker than paper; nil for a blank page.
    private static func inkedRows(of context: CGContext, width: Int, height: Int) -> Range<Int>? {
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bytesPerRow = context.bytesPerRow
        let paperThreshold: UInt8 = 245
        func isInked(_ row: Int) -> Bool {
            let start = row * bytesPerRow
            for column in 0..<width {
                let offset = start + column * 4
                if pixels[offset] < paperThreshold || pixels[offset + 1] < paperThreshold || pixels[offset + 2] < paperThreshold { return true }
            }
            return false
        }
        guard let first = (0..<height).first(where: isInked), let last = (0..<height).reversed().first(where: isInked) else { return nil }
        return first..<(last + 1)
    }
}
