/**
 * File: NoteIconPictures.swift
 * ----------------------------
 * Layer: UI
 * Description: The pixels of notes' picture icons: a picture of the vault decoded through the reading view's image
 *              cache, a picture of the web (Notion's SVG icons among them) fetched once and kept for the window.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import Foundation
import CoreGraphics
import GraphiteCore
import GraphiteApple

/// Why an icon has no picture. Never shown: an icon that cannot be drawn is left out, as an unknown symbol is.
enum NoteIconPictureError: Error, Equatable {
    case refused(statusCode: Int)
    case tooLarge(limitBytes: Int)
    case noSymbol(String)
    case iconsOff
}

/// Where a picture icon's pixels are read from.
enum NoteIconPictureLocation: Hashable, Sendable {
    case vaultFile(URL)
    case webAddress(URL)

    /// The location of `source` in the vault at `root`; nil for a vault path that does not parse.
    init?(source: NoteBanner.Source, root: URL) {
        switch source {
        case .vaultFile(let linkTarget):
            guard let path = try? VaultPath(linkTarget), let location = try? path.url(in: root) else { return nil } // Not a vault path: no picture.
            self = .vaultFile(location)
        case .webAddress(let address):
            self = .webAddress(address)
        }
    }
}

/// A window's decoded picture icons, at most `maximumPictureCount`, each decoded once however many rows show it. A
/// web picture is read at most once at a time and kept only in memory: the vault is never written.
actor NoteIconPictures {
    static let maximumPictureCount = 256
    /// Larger downloads are refused: an icon is a small picture.
    static let maximumDownloadBytes = 2 * 1_048_576
    /// The longest side an icon is decoded at, enough for the reading view's large icon at 2x.
    static let pixelDimension = 192

    private var picturesByLocation: [NoteIconPictureLocation: ReadingThumbnail] = [:]
    private var loads: [NoteIconPictureLocation: Task<ReadingThumbnail, any Error>] = [:]

    /// The picture at `location`, decoded when first asked for.
    func picture(at location: NoteIconPictureLocation) async throws -> ReadingThumbnail {
        if let picture = picturesByLocation[location] { return picture }
        if let load = loads[location] { return try await load.value }
        let load = Task { try await Self.decode(location) }
        loads[location] = load
        defer { loads[location] = nil }
        let picture = try await load.value
        if picturesByLocation.count >= Self.maximumPictureCount { picturesByLocation.removeAll() }
        picturesByLocation[location] = picture
        return picture
    }

    private static func decode(_ location: NoteIconPictureLocation) async throws -> ReadingThumbnail {
        switch location {
        case .vaultFile(let fileLocation):
            return try await ReadingImageCache.shared.thumbnail(for: fileLocation, kind: .inline, displayPixelWidth: pixelDimension)
        case .webAddress(let address):
            let image = try PictureDataDecoding.image(from: try await downloaded(address), maximumPixelDimension: pixelDimension)
            return ReadingThumbnail(image: image, aspectRatio: CGFloat(image.width) / CGFloat(max(image.height, 1)), isEditableDrawing: false)
        }
    }

    /// The bytes at `address`, refusing an answer that is not a success or is larger than `maximumDownloadBytes`.
    private static func downloaded(_ address: URL) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.bytes(from: address)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw NoteIconPictureError.refused(statusCode: httpResponse.statusCode)
        }
        guard response.expectedContentLength <= Int64(maximumDownloadBytes) else { throw NoteIconPictureError.tooLarge(limitBytes: maximumDownloadBytes) }
        var pictureData = Data()
        for try await byte in bytes {
            pictureData.append(byte)
            guard pictureData.count <= maximumDownloadBytes else { throw NoteIconPictureError.tooLarge(limitBytes: maximumDownloadBytes) }
        }
        return pictureData
    }
}
