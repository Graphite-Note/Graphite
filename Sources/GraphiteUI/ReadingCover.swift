/**
 * File: ReadingCover.swift
 * ------------------------
 * Layer: UI
 * Description: A note's cover in the reading view, from its `banner` property as Banners and Pixel Banner write it:
 *              found in the vault or on the web when the note is built, drawn short above the title, and collapsed to
 *              a strip for the session from a button on it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
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

/// What the top of a note shows from its frontmatter: its cover and its icon, as Notion draws a page.
struct ReadingPageLook: Equatable, Sendable {
    var cover: ReadingCover?
    /// The note's icon, a picture of the vault named by its path in the vault.
    var icon: NoteIcon?

    /// The properties the page's header already draws, lowercased, which the Properties panel leaves out.
    var drawnPropertyKeys: Set<String> {
        (cover == nil ? [] : NoteBanner.coverPropertyKeys).union(icon == nil ? [] : [NoteIcon.propertyKey])
    }
}

extension ReadingViewBuilder {
    /// The cover and the icon the note's frontmatter names, each only when the configuration draws it. The frontmatter
    /// is parsed only when it holds the word `banner` or `icon`.
    func pageLook(inFrontmatter frontmatterText: String, note: VaultPath, root: URL, index: some ReadingFileLookup,
                  configuration: ReadingConfiguration) async -> ReadingPageLook {
        guard frontmatterText.range(of: NoteBanner.propertyKey, options: .caseInsensitive) != nil
                || frontmatterText.range(of: NoteIcon.propertyKey, options: .caseInsensitive) != nil,
              let yaml = try? MarkdownSemantics.parse(frontmatterText).frontmatter, // Frontmatter that does not parse shows nothing.
              let properties = NoteProperties.parse(yaml, declaredTypes: configuration.declaredPropertyTypes) else { return ReadingPageLook() }
        var pageLook = ReadingPageLook()
        if configuration.drawsCover, let banner = NoteBanner(properties: properties) {
            pageLook.cover = await cover(of: banner, note: note, root: root, index: index)
        }
        if configuration.drawsPageLook, let icon = NoteIconEditing.icon(in: properties) {
            pageLook.icon = await resolved(icon, note: note, root: root, index: index)
        }
        return pageLook
    }

    private func cover(of banner: NoteBanner, note: VaultPath, root: URL, index: some ReadingFileLookup) async -> ReadingCover? {
        switch banner.source {
        case .webAddress(let address):
            return ReadingCover(picture: .webAddress(address), verticalFocus: banner.verticalFocus)
        case .vaultFile(let linkTarget):
            guard let path = await resolve(linkTarget, isWiki: true, note: note, root: root, index: index), DocumentKind(path: path) == .image,
                  let location = try? path.url(in: root) else { return nil } // A path outside the vault names no cover.
            return ReadingCover(picture: .vaultFile(path: path, location: location), verticalFocus: banner.verticalFocus)
        }
    }

    /// A picture icon of the vault named by its path in the vault, found from the note as an embed is; nil when no
    /// picture answers it.
    private func resolved(_ icon: NoteIcon, note: VaultPath, root: URL, index: some ReadingFileLookup) async -> NoteIcon? {
        guard case .picture(.vaultFile(let linkTarget)) = icon else { return icon }
        guard let path = await resolve(linkTarget, isWiki: true, note: note, root: root, index: index), DocumentKind(path: path) == .image else { return nil }
        return .picture(.vaultFile(linkTarget: path.rawValue))
    }
}

/// The top of a note in the reading view, as Notion draws a page: the cover across the whole reading view, then the
/// note's icon, large, over the cover's lower left. Nothing for a note without either.
struct ReadingPageHeader: View {
    let pageLook: ReadingPageLook
    let notePath: VaultPath
    let textSize: Double
    /// How far the column's content starts below the reading view's top, which the cover reaches up to.
    let topInset: CGFloat
    /// Where the column starts in the reading view, which the cover reaches back to.
    @State private var columnMinX: CGFloat = 0

    /// Notion's page icon is 78 points beside 16-point text.
    static let iconSizeInEms = 4.9
    /// The part of the icon over the cover, Notion's 42 of 78 points.
    static let iconOverlapFraction = 0.54

    var body: some View {
        if pageLook.cover != nil || pageLook.icon != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let cover = pageLook.cover {
                    // The button ends where the column does, as the column is centred in the reading view.
                    ReadingCoverView(cover: cover, notePath: notePath, buttonTrailingInset: max(columnMinX, 8))
                        .containerRelativeFrame(.horizontal)
                        .offset(x: -columnMinX)
                        .padding(.top, -topInset)
                }
                if let icon = pageLook.icon {
                    let iconSize = CGFloat(textSize * Self.iconSizeInEms)
                    NoteIconImage(icon: icon, pointSize: iconSize)
                        .frame(width: iconSize, height: iconSize)
                        .padding(.top, pageLook.cover == nil ? 0 : -iconSize * Self.iconOverlapFraction)
                }
            }
            // Where the column starts in the reading view: the header is laid at the column's leading edge.
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.frame(in: .named(ReadingCoordinateSpace.name)).minX } action: { minX in
                columnMinX = minX
            }
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

/// The cover above the note's title: the picture cropped to a band across the reading view, with a button that folds
/// it to a strip and opens it again. A picture that cannot be read leaves no room.
struct ReadingCoverView: View {
    let cover: ReadingCover
    let notePath: VaultPath
    /// How far in from the cover's right edge its button sits: the note's column ends there.
    var buttonTrailingInset: CGFloat = 8
    @Environment(\.calloutFoldNote) private var foldNote
    @State private var loadedImage: CGImage?
    @State private var didFail = false
    /// Whether the cover is open, when no fold store keeps it (a note shown outside a pane).
    @State private var isExpandedWithoutStore = true

    /// Notion's cover takes 30% of the window's height; Graphite keeps it between these.
    static let viewHeightFraction: CGFloat = 0.3
    static let smallestExpandedHeightPoints: CGFloat = 140
    static let largestExpandedHeightPoints: CGFloat = 280
    static let collapsedHeightPoints: CGFloat = 22
    /// The key the cover is folded under in the note's fold store, beside its callouts' keys.
    static let foldKey = "graphite-cover"
    /// The widest the picture is decoded: the readable column at the largest display scale, with room to spare.
    static let maximumPixelWidth = 2400

    /// The open cover's height in a reading view `viewHeight` points high.
    static func expandedHeight(forViewHeight viewHeight: CGFloat) -> CGFloat {
        min(max(viewHeight * viewHeightFraction, smallestExpandedHeightPoints), largestExpandedHeightPoints)
    }

    private var isExpanded: Bool {
        guard let foldNote else { return isExpandedWithoutStore }
        return foldNote.store.isExpanded(notePath: foldNote.notePath, key: Self.foldKey, initially: true)
    }

    var body: some View {
        if !didFail {
            picture
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { viewHeight, _ in
                    isExpanded ? Self.expandedHeight(forViewHeight: viewHeight) : Self.collapsedHeightPoints
                }
                .clipped()
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
        .padding(.vertical, isExpanded ? 8 : 2)
        .padding(.trailing, buttonTrailingInset)
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
