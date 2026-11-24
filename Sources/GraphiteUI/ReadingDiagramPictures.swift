/**
 * File: ReadingDiagramPictures.swift
 * ----------------------------------
 * Layer: UI
 * Description: The reading view's diagrams on the iPad and the iPhone as pictures, painted away from the main actor by
 *              the package's Core Graphics painter and kept, within a budget, while the reading view is open.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit
import MermaidDiagrams

/// What a diagram's picture is painted from: one scene, in one set of the note's colors in one appearance, at one number
/// of pixels a point.
struct ReadingDiagramPictureKey: Hashable, Sendable {
    /// Where the scene's items are stored. A scene is never changed once made, and each kept picture holds its scene, so
    /// while a picture is kept no other scene's items are stored there.
    private let sceneItems: UInt
    private let sceneWidth: CGFloat
    private let sceneHeight: CGFloat
    let appearance: ReadingDiagramPictureAppearance
    let pixelsPerPoint: CGFloat

    init(scene: DiagramScene, appearance: ReadingDiagramPictureAppearance, pixelsPerPoint: CGFloat) {
        sceneItems = scene.itemStorage
        sceneWidth = scene.size.width
        sceneHeight = scene.size.height
        self.appearance = appearance
        self.pixelsPerPoint = pixelsPerPoint
    }

    /// Whether `other` paints the same scene, in whatever colors.
    func paintsTheSameScene(as other: ReadingDiagramPictureKey) -> Bool {
        sceneItems == other.sceneItems && sceneWidth == other.sceneWidth && sceneHeight == other.sceneHeight
    }
}

/// The note's colors for diagrams and the appearance they are resolved in.
struct ReadingDiagramPictureAppearance: Hashable, Sendable {
    let colors: ReadingDiagramColors
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast
}

/// The pictures of one reading view's diagrams. A diagram drawn as SwiftUI views, a path or a text for each of its items,
/// took 6 to 11 ms of the main thread to come on screen in the iPad simulator (`ReadingTextBlockCostHostedTests`), so a
/// scroll that brought one in dropped a frame; its picture is painted on another thread by the package's own painter
/// (`DiagramSceneRenderer`, the one `ReadingDiagramScenePainting` is held to by `ReadingDiagramScenePaintingTests`) and
/// shown as one image. The pictures painted last are kept up to `budgetBytes`, so a diagram scrolled back to is shown at
/// once; all go on a memory warning, and with the reading view.
@MainActor
final class ReadingDiagramPictures {
    /// About a dozen diagrams of a column's width, painted at two pixels a point.
    static let budgetBytes = 32 * 1_048_576

    private struct KeptPicture {
        /// Held so that its items' storage, which the key names, is not given to another scene.
        let scene: DiagramScene
        let picture: CGImage
        var lastUse: Int
    }

    private var keptPictures: [ReadingDiagramPictureKey: KeptPicture] = [:]
    private var keptBytes = 0
    private var useCount = 0
    private var paintings: [ReadingDiagramPictureKey: Task<CGImage?, Never>] = [:]
    private var palettes: [ReadingDiagramPictureAppearance: DiagramPalette] = [:]
    /// The note's drawn diagrams in reading order, whose pictures are painted ahead of a scroll (`paintNeighbors`).
    private var noteDiagrams: [PreparedMermaidDiagram] = []
    /// How many diagrams before and after one shown have their pictures painted ahead: a scroll brings them in next.
    static let diagramsPaintedAhead = 2
    /// Listens for memory warnings from the first picture kept: a reading view's state makes one of these at each of its
    /// updates, and keeps only the first.
    private var memoryWarningObserver: (any NSObjectProtocol)?

    init() {}

    isolated deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    /// The kept picture for `key`, or nil until it is painted.
    func picture(for key: ReadingDiagramPictureKey) -> CGImage? {
        guard var kept = keptPictures[key] else { return nil }
        useCount += 1
        kept.lastUse = useCount
        keptPictures[key] = kept
        return kept.picture
    }

    /// The picture of `scene` for `key`, painted off the main actor unless it is kept or being painted already; its
    /// colors resolved in `environment`, the one the key's appearance was read from.
    func paint(_ scene: DiagramScene, for key: ReadingDiagramPictureKey, resolvingColorsIn environment: EnvironmentValues) async -> CGImage? {
        if let kept = picture(for: key) { return kept }
        if let painting = paintings[key] { return await painting.value }
        let palette = palette(for: key.appearance, resolvedIn: environment)
        let pixelsPerPoint = key.pixelsPerPoint
        let painting = Task.detached(priority: .userInitiated) { Self.picture(of: scene, in: palette, pixelsPerPoint: pixelsPerPoint) }
        paintings[key] = painting
        let picture = await painting.value
        paintings[key] = nil
        if let picture { keep(picture, of: scene, for: key) }
        return picture
    }

    /// The note's drawn diagrams, in reading order: those of `blocks`, of their callouts and of the notes they embed.
    func showNote(_ blocks: [RenderedBlock]) {
        noteDiagrams = Self.drawnDiagrams(in: blocks)
    }

    private static func drawnDiagrams(in blocks: [RenderedBlock]) -> [PreparedMermaidDiagram] {
        blocks.flatMap { block -> [PreparedMermaidDiagram] in
            switch block {
            case .diagram(_, .drawn(let prepared, _)): [prepared]
            case .callout(_, _, _, _, let body), .transclusion(_, _, _, let body): drawnDiagrams(in: body)
            case .properties, .markdown, .displayMath, .heading, .video, .webVideo, .audio, .pdf, .base, .baseFile, .missingEmbed,
                 .missingSection, .image, .footnotes, .pluginCodeBlock, .pluginSection, .diagram(_, .unreadable), .webFrame: []
            }
        }
    }

    /// Paints the pictures of the diagrams read just before and after the one whose picture is `key`, as they would be
    /// shown in the same column: a scroll brings them on screen with their pictures ready, as one that comes on screen
    /// before its picture is painted is empty for a frame or two.
    func paintNeighbors(of key: ReadingDiagramPictureKey, placement: ReadingDiagramPlacement, resolvingColorsIn environment: EnvironmentValues) async {
        guard let index = noteDiagrams.firstIndex(where: { prepared in prepared.scene.itemStorage == placement.diagramSceneItems }) else { return }
        let nearest = (1...Self.diagramsPaintedAhead).flatMap { distance in [index + distance, index - distance] }
        for neighbor in nearest where noteDiagrams.indices.contains(neighbor) {
            let prepared = noteDiagrams[neighbor]
            let scene = ReadingScaledDiagram<EmptyView>.shownScene(of: prepared, inColumnWidth: placement.columnWidth,
                                                                   scaleAtNaturalWidth: CGFloat(placement.textSize) / prepared.scene.font.size)
            _ = await paint(scene, for: ReadingDiagramPictureKey(scene: scene, appearance: key.appearance, pixelsPerPoint: key.pixelsPerPoint),
                            resolvingColorsIn: environment)
        }
    }

    func removeAllPictures() {
        keptPictures = [:]
        keptBytes = 0
        palettes = [:]
    }

    /// The colors resolved once for each appearance: resolving the ten colors took about half a millisecond.
    private func palette(for appearance: ReadingDiagramPictureAppearance, resolvedIn environment: EnvironmentValues) -> DiagramPalette {
        if let palette = palettes[appearance] { return palette }
        let palette = appearance.colors.palette(in: environment)
        palettes[appearance] = palette
        return palette
    }

    /// Keeps the picture, letting go of the least recently shown ones beyond the budget; the newest always stays.
    private func keep(_ picture: CGImage, of scene: DiagramScene, for key: ReadingDiagramPictureKey) {
        if memoryWarningObserver == nil {
            memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                                           queue: .main) { [weak self] _ in
                Task { @MainActor in self?.removeAllPictures() }
            }
        }
        useCount += 1
        if let replaced = keptPictures.updateValue(KeptPicture(scene: scene, picture: picture, lastUse: useCount), forKey: key) {
            keptBytes -= Self.bytes(of: replaced.picture)
        }
        keptBytes += Self.bytes(of: picture)
        while keptBytes > Self.budgetBytes, keptPictures.count > 1,
              let oldest = keptPictures.min(by: { first, second in first.value.lastUse < second.value.lastUse }) {
            keptPictures[oldest.key] = nil
            keptBytes -= Self.bytes(of: oldest.value.picture)
        }
    }

    private static func bytes(of picture: CGImage) -> Int { picture.bytesPerRow * picture.height }

    /// `scene` painted over a clear page, `pixelsPerPoint` pixels a point, its first row at the top.
    nonisolated static func picture(of scene: DiagramScene, in palette: DiagramPalette, pixelsPerPoint: CGFloat) -> CGImage? {
        let width = Int((scene.size.width * pixelsPerPoint).rounded(.up)), height = Int((scene.size.height * pixelsPerPoint).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // The painter's y runs down from the top; a bitmap context's runs up.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelsPerPoint, y: -pixelsPerPoint)
        DiagramSceneRenderer.draw(scene, in: context, palette: palette)
        return context.makeImage()
    }
}

/// Where a diagram is shown: the column's width and the note's text size, which say which of its scenes is shown and
/// how far it is shrunk (`ReadingScaledDiagram`), and which diagram it is (where its regular scene's items are stored).
struct ReadingDiagramPlacement: Equatable {
    let columnWidth: CGFloat
    let textSize: Double
    let diagramSceneItems: UInt
}

extension DiagramScene {
    /// Where the scene's items are stored: the same for every copy of one scene, which is never changed once made.
    var itemStorage: UInt {
        items.withUnsafeBufferPointer { items in UInt(bitPattern: items.baseAddress) }
    }
}

extension EnvironmentValues {
    /// Where the diagram being painted is shown; zero wide before its column is measured.
    @Entry var readingDiagramPlacement = ReadingDiagramPlacement(columnWidth: 0, textSize: 0, diagramSceneItems: 0)

    /// The reading view's pictures of its diagrams; nil where diagrams are painted as SwiftUI views (Live Preview, paper,
    /// the Mac).
    @Entry var readingDiagramPictures: ReadingDiagramPictures? = nil
}

/// A scene shown as its picture (`ReadingDiagramPictures`), at the scene's size; empty until the picture is painted, the
/// first time, and the picture of the same scene in the colors before while it is painted in new ones.
struct ReadingDiagramScenePicture: View {
    let scene: DiagramScene
    let colors: ReadingDiagramColors
    let pictures: ReadingDiagramPictures
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.readingDiagramPlacement) private var placement
    /// What the colors are resolved in when the picture is painted: the appearance, its contrast and the rest.
    @Environment(\.self) private var environment
    /// The picture last painted for this view, shown while a picture in new colors is painted.
    @State private var painted: (key: ReadingDiagramPictureKey, picture: CGImage)?

    var body: some View {
        let appearance = ReadingDiagramPictureAppearance(colors: colors, colorScheme: colorScheme, contrast: contrast)
        let key = ReadingDiagramPictureKey(scene: scene, appearance: appearance, pixelsPerPoint: displayScale)
        let picture = pictures.picture(for: key) ?? painted.flatMap { painted in painted.key.paintsTheSameScene(as: key) ? painted.picture : nil }
        ZStack {
            if let picture {
                Image(decorative: picture, scale: key.pixelsPerPoint).resizable()
            }
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .task(id: key) {
            // Shown already by the body when kept.
            if pictures.picture(for: key) == nil {
                guard let picture = await pictures.paint(scene, for: key, resolvingColorsIn: environment), !Task.isCancelled else { return }
                painted = (key, picture)
            }
            guard placement.columnWidth > 0 else { return }
            await pictures.paintNeighbors(of: key, placement: placement, resolvingColorsIn: environment)
        }
    }
}
#endif
