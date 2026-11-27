/**
 * File: ReadingCover.swift
 * ------------------------
 * Layer: UI
 * Description: A note's cover in the reading view, from its `banner` property as Banners and Pixel Banner write it:
 *              found in the vault or on the web when the note is built, drawn short above the title, and collapsed to
 *              a strip for the session from a button on it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import SwiftUI
import GraphiteCore

/// The picture of a note's cover, found, and which part of it shows.
struct ReadingCover: Equatable, Sendable {
    enum Picture: Equatable, Sendable {
        case vaultFile(path: VaultPath, location: URL)
        case webAddress(URL)
    }

    let picture: Picture
    /// 0 shows the picture's top, 1 its bottom (`NoteBanner.verticalFocus`).
    let verticalFocus: Double
}

extension ReadingViewBuilder {
    /// The cover the note's frontmatter names, or nil without a `banner` property, or when its picture is not a
    /// picture of the vault. The frontmatter is parsed only when it holds the word `banner`.
    func cover(inFrontmatter frontmatterText: String, note: VaultPath, root: URL, index: some ReadingFileLookup,
               configuration: ReadingConfiguration) async -> ReadingCover? {
        guard frontmatterText.range(of: NoteBanner.propertyKey, options: .caseInsensitive) != nil,
              let yaml = try? MarkdownSemantics.parse(frontmatterText).frontmatter, // Frontmatter that does not parse has no banner.
              let properties = NoteProperties.parse(yaml, declaredTypes: configuration.declaredPropertyTypes),
              let banner = NoteBanner(properties: properties) else { return nil }
        switch banner.source {
        case .webAddress(let address):
            return ReadingCover(picture: .webAddress(address), verticalFocus: banner.verticalFocus)
        case .vaultFile(let linkTarget):
            guard let path = await resolve(linkTarget, isWiki: true, note: note, root: root, index: index), DocumentKind(path: path) == .image,
                  let location = try? path.url(in: root) else { return nil } // A path outside the vault names no cover.
            return ReadingCover(picture: .vaultFile(path: path, location: location), verticalFocus: banner.verticalFocus)
        }
    }
}

/// Settings › Appearance › Covers on iPhone, shown on a phone while the Icons, Covers and Columns core plugin is on.
struct CoversOnPhoneSection: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        if SettingsDevice.current == .phone, preferences.isEnabled(.pageLook) {
            Section {
                Toggle("Covers on iPhone", isOn: $preferences.showsCoversOnPhone)
            } footer: {
                Text("Draws a note's banner property as a cover above its title in reading view. Off, the note starts at its title.")
                    .formFooterAlignment()
            }
        }
    }
}

/// The cover above the note's title: the picture cropped to a short band of the note's width, with a button that
/// folds it to a strip and opens it again. A picture that cannot be read leaves no room.
struct ReadingCoverView: View {
    let cover: ReadingCover
    let notePath: VaultPath
    @Environment(\.calloutFoldNote) private var foldNote
    @State private var loadedImage: CGImage?
    @State private var didFail = false
    /// Whether the cover is open, when no fold store keeps it (a note shown outside a pane).
    @State private var isExpandedWithoutStore = true

    static let expandedHeightPoints: CGFloat = 140
    static let collapsedHeightPoints: CGFloat = 22
    static let cornerRadiusPoints: CGFloat = 10
    /// The key the cover is folded under in the note's fold store, beside its callouts' keys.
    static let foldKey = "graphite-cover"
    /// The widest the picture is decoded: the readable column at the largest display scale, with room to spare.
    static let maximumPixelWidth = 2400

    private var isExpanded: Bool {
        guard let foldNote else { return isExpandedWithoutStore }
        return foldNote.store.isExpanded(notePath: foldNote.notePath, key: Self.foldKey, initially: true)
    }

    var body: some View {
        if !didFail {
            picture
                .frame(maxWidth: .infinity)
                .frame(height: isExpanded ? Self.expandedHeightPoints : Self.collapsedHeightPoints)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadiusPoints))
                .overlay(alignment: isExpanded ? .bottomTrailing : .trailing) { foldButton }
                .animation(GraphiteMotion.animation(.snappy(duration: 0.2)), value: isExpanded)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Cover")
                .task(id: cover) { await load() }
        }
    }

    @ViewBuilder private var picture: some View {
        if let loadedImage {
            GeometryReader { proxy in
                let aspectRatio = CGFloat(loadedImage.width) / CGFloat(max(loadedImage.height, 1))
                let drawnHeight = max(proxy.size.width / aspectRatio, proxy.size.height)
                let hiddenHeight = drawnHeight - proxy.size.height
                Image(decorative: loadedImage, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: drawnHeight)
                    .offset(y: -hiddenHeight * cover.verticalFocus)
            }
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    private var foldButton: some View {
        Button {
            setExpanded(!isExpanded)
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: isExpanded ? 26 : 18)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(isExpanded ? 8 : 2)
        .accessibilityLabel(isExpanded ? "Hide Cover" : "Show Cover")
    }

    private func setExpanded(_ expands: Bool) {
        if let foldNote {
            foldNote.store.setExpanded(expands, notePath: foldNote.notePath, key: Self.foldKey)
        } else {
            isExpandedWithoutStore = expands
        }
    }

    private func load() async {
        do {
            let image: CGImage
            switch cover.picture {
            case .vaultFile(_, let location):
                image = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: Self.maximumPixelWidth).image
            case .webAddress(let address):
                image = try await BaseThumbnailStore.downloadedThumbnail(at: address, maximumDimension: Self.maximumPixelWidth)
            }
            guard !Task.isCancelled else { return }
            loadedImage = image
            didFail = false
        } catch {
            // A task cancelled while it waited for a decoding slot ends in an error; it is not a failure of the picture.
            if !Task.isCancelled { didFail = true }
        }
    }
}
