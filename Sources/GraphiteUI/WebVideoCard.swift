/**
 * File: WebVideoCard.swift
 * ------------------------
 * Layer: UI
 * Description: The card a YouTube embed draws in Live Preview and the reading view, and the fetching of web pages'
 *              titles and thumbnails for it and for a bare address's menu.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import CoreGraphics
import Foundation
import GraphiteCore
import SwiftUI

/// Fetches web pages' titles and thumbnails when a card appears or a menu item is chosen.
/// It keeps nothing itself: answers are kept by the card that asked, and repeated requests
/// are answered from the system's URL cache when the site allows it.
enum WebLinkDetailsFetching {
    /// Wide enough for a card across an iPad's column: YouTube's thumbnails are 480 wide.
    private static let thumbnailDimension = 640
    private static let requestTimeout: TimeInterval = 12

    /// The page's title and thumbnail: YouTube's oEmbed for a video or playlist, the page's own
    /// `og:title` or `<title>` for any other address. Nil when the page cannot be reached.
    static func details(for address: URL) async -> WebLinkDetails? {
        if let video = WebVideo(address: address) {
            guard let request = video.oEmbedRequest, let data = await fetchedData(from: request) else { return nil }
            return WebLinkDetails.fromOEmbed(data)
        }
        guard let data = await fetchedData(from: address) else { return nil }
        return WebLinkDetails.fromHTML(String(decoding: data, as: UTF8.self))
    }

    /// The card's picture: the video's own thumbnail, or else the one oEmbed named.
    static func thumbnail(for video: WebVideo, details: WebLinkDetails?) async -> CGImage? {
        guard let location = video.directThumbnail ?? details?.thumbnail else { return nil }
        // A picture that cannot be downloaded leaves the card's grey frame and its play button.
        return try? await BaseThumbnailStore.downloadedThumbnail(at: location, maximumDimension: thumbnailDimension) // Harmless: see above.
    }

    /// At most `WebLinkDetails.maximumPageBytes` of a successful answer.
    private static func fetchedData(from location: URL) async -> Data? {
        var request = URLRequest(url: location, timeoutInterval: requestTimeout)
        request.setValue("text/html,application/json;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request), // Offline or refused: the written title stays.
              let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= WebLinkDetails.maximumPageBytes { break }
            }
        } catch {
            return data.isEmpty ? nil : data
        }
        return data
    }
}

/// A YouTube video or playlist embedded in a note: its thumbnail with a play button, and its
/// title. A tap or click opens the address in the YouTube app or the browser; nothing plays
/// in the note, so a note of many videos holds pictures only.
struct WebVideoCard: View {
    let video: WebVideo
    /// The embed's own text (`![title](address)`), shown until the fetched title arrives and
    /// when the page cannot be reached.
    let writtenTitle: String?
    /// Shows the embed's Markdown; nil where the card is not in an editor.
    var revealSource: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var fetchedTitle: String?
    @State private var thumbnail: CGImage?

    private static let cornerRadius: CGFloat = 10
    /// A card as wide as a laptop's video player, not the whole column on a large screen.
    nonisolated static let maximumWidth: CGFloat = 560

    private var title: String {
        if let writtenTitle, !writtenTitle.trimmingCharacters(in: .whitespaces).isEmpty { return writtenTitle }
        return fetchedTitle ?? video.address.absoluteString
    }

    var body: some View {
        Button { openURL(video.address) } label: {
            VStack(alignment: .leading, spacing: 0) {
                picture
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: video.isPlaylist ? "list.and.film" : "play.rectangle").foregroundStyle(.secondary)
                    Text(title).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("YouTube").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(maxWidth: Self.maximumWidth, alignment: .leading)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.quaternary) }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Open in YouTube", systemImage: "arrow.up.right.square") { openURL(video.address) }
            if let revealSource { Button("Edit Source", systemImage: "chevron.left.forwardslash.chevron.right", action: revealSource) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(video.isPlaylist ? "YouTube playlist: \(title)" : "YouTube video: \(title)")
        .accessibilityAddTraits(.isLink)
        .task(id: video) {
            let details = await WebLinkDetailsFetching.details(for: video.address)
            fetchedTitle = details?.title
            thumbnail = await WebLinkDetailsFetching.thumbnail(for: video, details: details)
        }
    }

    private var picture: some View {
        Rectangle().fill(.quaternary)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill) }
            }
            .clipped()
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 64, height: 44)
                    .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4, y: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if video.isPlaylist {
                    Label("Playlist", systemImage: "list.bullet")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
            }
    }
}
