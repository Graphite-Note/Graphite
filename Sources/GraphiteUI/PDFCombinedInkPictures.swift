/**
 * File: PDFCombinedInkPictures.swift
 * ----------------------------------
 * Layer: UI
 * Description: On the iPad, keeps the picture of each combined ink group of the pages shown at the screen's
 *              resolution, drawn off the main thread from a separate copy of the file, and drawn again after a zoom or
 *              an erasure.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */
#if os(iOS)
import UIKit
import PDFKit
import GraphiteApple

/// Draws the pictures of the combined ink groups (`PDFCombinedInkGroup`) of the pages PDFKit shows.
///
/// A densely written page's ink group is one annotation on the shown page, which draws its group's picture
/// (`PDFShownInkCombining`). The picture is drawn here, off the main thread, from a separate copy of the file
/// (`PDFPageInkRenderer`), at the page's size on screen times the screen's scale, at most `maximumPixelsPerPicture`; it
/// comes a few frames after the page, as PDFKit's own tiles do, and is drawn again when a zoom ends, when strokes of
/// the group are erased, or when the page is turned. The page's overlay shows it as a layer's contents
/// (`PDFPageOverlayView.showCombinedInk`), hidden while the page's canvas shows the ink. A page leaving the screen lets its pictures go; its canvas, kept
/// for scrolling back, shows its ink meanwhile.
@MainActor
final class PDFCombinedInkPictures {
    /// A picture holds at most this many pixels (64 MB); a page zoomed in further is drawn at that size and magnified.
    static let maximumPixelsPerPicture = 16 * 1_048_576
    /// A picture within this fraction of the size wanted is not drawn again.
    private static let sizeTolerance: CGFloat = 0.2
    private static let redrawDelayAfterZoom: TimeInterval = 0.15

    private struct ShownPage {
        weak var page: PDFPage?
        var drawing: Task<Void, Never>?
    }

    private weak var view: PDFView?
    private let changeVersion: () -> Int
    /// Shows a page's pictures in its overlay, `isShown` false while its canvas shows the page's ink.
    private let showPictures: (_ page: PDFPage, _ pictures: [CGImage], _ isShown: Bool) -> Void
    private let renderer = PDFPageInkRenderer()
    private var shownPages: [ObjectIdentifier: ShownPage] = [:]
    private var redrawTimer: Timer?

    init(view: PDFView, changeVersion: @escaping () -> Int,
         showPictures: @escaping (_ page: PDFPage, _ pictures: [CGImage], _ isShown: Bool) -> Void) {
        self.view = view
        self.changeVersion = changeVersion
        self.showPictures = showPictures
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRedraw), name: .PDFViewScaleChanged, object: view)
        observeEdits()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        redrawTimer?.invalidate()
        redrawTimer = nil
        for shownPage in shownPages.values { shownPage.drawing?.cancel() }
        shownPages.removeAll()
    }

    /// PDFKit shows the page: its combined groups' pictures are drawn if they are missing or out of date.
    func pageAppeared(_ page: PDFPage) {
        guard Self.combinedGroups(on: page).isEmpty == false else { return }
        let identifier = ObjectIdentifier(page)
        if shownPages[identifier] == nil { shownPages[identifier] = ShownPage(page: page) }
        draw(page)
    }

    /// PDFKit no longer shows the page: its pictures go.
    func pageLeft(_ page: PDFPage) {
        guard let shownPage = shownPages.removeValue(forKey: ObjectIdentifier(page)) else { return }
        shownPage.drawing?.cancel()
        for combinedGroup in Self.combinedGroups(on: page) { combinedGroup.show(nil) }
        showPictures(page, [], false)
    }

    /// Shows or hides the page's pictures as its groups' annotations are shown or hidden under its canvas.
    func updateShownPictures(of page: PDFPage) {
        guard shownPages[ObjectIdentifier(page)] != nil else { return }
        let holders = page.annotations.filter { annotation in annotation.combinedInkGroup != nil }
        let pictures = holders.compactMap { annotation in annotation.combinedInkGroup.flatMap(Self.upToDatePicture(of:)) }
        showPictures(page, pictures, holders.contains(where: \.shouldDisplay))
    }

    private static func upToDatePicture(of combinedGroup: PDFCombinedInkGroup) -> CGImage? {
        combinedGroup.picture.flatMap { picture in picture.version == combinedGroup.version ? picture.image : nil }
    }

    /// Pages whose groups' pictures are all drawn and up to date, which a test asks.
    var pagesWithPictures: [PDFPage] {
        shownPages.values.compactMap(\.page).filter { page in
            Self.combinedGroups(on: page).allSatisfy { combinedGroup in combinedGroup.picture?.version == combinedGroup.version }
        }
    }

    private static func combinedGroups(on page: PDFPage) -> [PDFCombinedInkGroup] {
        page.annotations.compactMap(\.combinedInkGroup)
    }

    private func draw(_ page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        guard shownPages[identifier] != nil, let view else { return }
        let groups = Self.combinedGroups(on: page)
        let shownSize = view.convert(page.bounds(for: .cropBox), from: page).size
        let screenScale = view.window?.screen.scale ?? view.traitCollection.displayScale
        var pixelSize = CGSize(width: (shownSize.width * screenScale).rounded(), height: (shownSize.height * screenScale).rounded())
        let pixelCount = pixelSize.width * pixelSize.height
        if pixelCount > CGFloat(Self.maximumPixelsPerPicture) {
            let shrink = (CGFloat(Self.maximumPixelsPerPicture) / pixelCount).squareRoot()
            pixelSize = CGSize(width: (pixelSize.width * shrink).rounded(.down), height: (pixelSize.height * shrink).rounded(.down))
        }
        let cropBox = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let groupsToDraw = groups.filter { combinedGroup in
            guard let picture = combinedGroup.picture, picture.version == combinedGroup.version, picture.cropBox == cropBox,
                  picture.rotation == rotation else { return true }
            return abs(CGFloat(picture.image.width) - pixelSize.width) > pixelSize.width * Self.sizeTolerance
        }
        guard !groupsToDraw.isEmpty else {
            updateShownPictures(of: page)
            return
        }
        shownPages[identifier]?.drawing?.cancel()
        let renderer = renderer
        shownPages[identifier]?.drawing = Task { [weak self, weak page] in
            for combinedGroup in groupsToDraw {
                guard let page, !Task.isCancelled else { return }
                let picture = await PDFPageInkRenderer.picture(of: combinedGroup, on: page, pixelSize: pixelSize, with: renderer)
                guard !Task.isCancelled, let picture else { continue }
                combinedGroup.show(picture)
            }
            guard !Task.isCancelled, let self, let page else { return }
            self.shownPages[ObjectIdentifier(page)]?.drawing = nil
            self.updateShownPictures(of: page)
        }
    }

    @objc private func scheduleRedraw() {
        redrawTimer?.invalidate()
        // A timer rather than a task, so it runs while a pinch keeps the run loop in tracking mode.
        let timer = Timer(timeInterval: Self.redrawDelayAfterZoom, target: self, selector: #selector(redrawShownPages), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        redrawTimer = timer
    }

    @objc private func redrawShownPages() {
        redrawTimer = nil
        for shownPage in shownPages.values { if let page = shownPage.page { draw(page) } }
    }

    /// An erasure or a turn of a shown page draws its pictures again.
    private func observeEdits() {
        withObservationTracking {
            _ = changeVersion()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.redrawShownPages()
                self.observeEdits()
            }
        }
    }
}
#endif
