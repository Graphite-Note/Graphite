/**
 * File: NoteIconImage.swift
 * -------------------------
 * Layer: UI
 * Description: A note's icon drawn beside its name: an emoji as text, an SF Symbol in the secondary color, nothing for
 *              a symbol name the system does not have, and the square pictures of icons before links.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A picture icon, square at `pointSize`, drawn once the window's `NoteIconPictures` has it; nothing while it loads or
/// when it cannot be read.
private struct NoteIconPictureImage: View {
    let source: NoteBanner.Source
    let pointSize: CGFloat
    @Environment(\.noteIcons) private var noteIcons
    @State private var loadedPicture: ReadingThumbnail?

    var body: some View {
        Group {
            if let loadedPicture {
                Image(decorative: loadedPicture.image, scale: 1).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: pointSize, height: pointSize)
        .task(id: source) {
            guard let noteIcons, let location = noteIcons.pictureLocation(of: source) else { return }
            loadedPicture = try? await noteIcons.pictures.picture(at: location) // Unreadable: no icon, as an unknown symbol.
        }
    }
}

/// An SF Symbol drawn into pixels in a grey that reads on light and dark pages, for an icon inside text.
enum NoteIconSymbolPicture {
    static func image(systemName: String, pixelDimension: Int) throws -> CGImage {
        let side = CGFloat(pixelDimension)
        #if canImport(UIKit)
        let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.8)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?.withTintColor(.systemGray, renderingMode: .alwaysOriginal) else {
            throw NoteIconPictureError.noSymbol(systemName)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = min(side / max(symbol.size.width, 1), side / max(symbol.size.height, 1))
            let drawnSize = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: CGRect(x: (side - drawnSize.width) / 2, y: (side - drawnSize.height) / 2, width: drawnSize.width, height: drawnSize.height))
        }
        guard let image = picture.cgImage else { throw NoteIconPictureError.noSymbol(systemName) }
        return image
        #else
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: side * 0.8, weight: .regular)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: .systemGray))) else {
            throw NoteIconPictureError.noSymbol(systemName)
        }
        var proposedRect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let image = symbol.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw NoteIconPictureError.noSymbol(systemName)
        }
        return image
        #endif
    }
}

/// A note's icon at a given size. Decorative: the note's name beside it is what VoiceOver reads.
struct NoteIconImage: View {
    let icon: NoteIcon
    let pointSize: CGFloat

    var body: some View {
        Group {
            switch icon {
            case .emoji(let emoji):
                Text(verbatim: emoji).font(.system(size: pointSize))
            case .symbol(let systemName):
                if NoteIconImage.systemHasSymbol(named: systemName) {
                    Image(systemName: systemName).font(.system(size: pointSize)).foregroundStyle(.secondary)
                }
            case .picture(let source):
                NoteIconPictureImage(source: source, pointSize: pointSize)
            }
        }
        .accessibilityHidden(true)
    }

    /// Whether the system draws a symbol of this name: a name written by hand may name none.
    static func systemHasSymbol(named systemName: String) -> Bool {
        #if canImport(UIKit)
        UIImage(systemName: systemName) != nil
        #else
        NSImage(systemSymbolName: systemName, accessibilityDescription: nil) != nil
        #endif
    }
}

/// Icons before links drawn as squares of the same size: an emoji drawn into one, a picture fitted into one, centred.
enum NoteIconSquarePicture {
    /// An emoji's font size as a share of the square. Its line is taller than its picture, so at the square's own size
    /// the emoji fills about as much of it as a symbol does.
    static let emojiShare: CGFloat = 1

    static func emoji(_ emoji: String, pixelDimension: Int) throws -> CGImage {
        let side = CGFloat(pixelDimension)
        let text = NSAttributedString(string: emoji, attributes: [.font: PlatformFont.systemFont(ofSize: side * emojiShare)])
        let textSize = text.size()
        let origin = CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2)
        let context = try squareContext(side: pixelDimension, for: emoji)
        #if canImport(UIKit)
        // UIKit draws with its origin at the top.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        text.draw(at: origin)
        UIGraphicsPopContext()
        #else
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: origin)
        NSGraphicsContext.current = previousContext
        #endif
        guard let image = context.makeImage() else { throw NoteIconPictureError.notDrawn(emoji) }
        return image
    }

    /// `image` fitted into a square, centred, its proportions kept; a square image is returned as it is.
    static func squared(_ image: CGImage, pixelDimension: Int) throws -> CGImage {
        guard image.width != image.height, image.width > 0, image.height > 0 else { return image }
        let side = CGFloat(pixelDimension)
        let scale = min(side / CGFloat(image.width), side / CGFloat(image.height))
        let drawnSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let context = try squareContext(side: pixelDimension, for: "picture")
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (side - drawnSize.width) / 2, y: (side - drawnSize.height) / 2, width: drawnSize.width, height: drawnSize.height))
        guard let squared = context.makeImage() else { throw NoteIconPictureError.notDrawn("picture") }
        return squared
    }

    private static func squareContext(side: Int, for name: String) throws -> CGContext {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NoteIconPictureError.notDrawn(name) }
        return context
    }
}
