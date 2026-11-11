/**
 * File: ReadingPictureHover.swift
 * -------------------------------
 * Layer: UI
 * Description: The magnifier and "Open in New Tab" buttons over a picture inside the reading view's text (in a
 *              sentence, a table cell, a callout or an embedded note) while the pointer rests on it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// Which picture inside the reading view's text the pointer rests on. The text says when the
/// pointer comes onto a picture and leaves it (its run links to its zoom, and Textual reports
/// the links under the pointer, one recognizer per text and none per picture); the buttons
/// say when the pointer is on them. Leaving the picture for its buttons, which are drawn over
/// it, is not leaving it: the buttons stay for `hideDelay` after the pointer leaves either.
@MainActor @Observable
final class ReadingPictureHover {
    /// A picture the pointer rests on, and where it is drawn in the window's own coordinates.
    struct HoveredPicture: Equatable {
        let path: VaultPath
        let windowFrame: CGRect
    }

    /// How long the buttons stay once the pointer left the picture and them, which leaves
    /// time to move from one to the other.
    static let hideDelay: Duration = .milliseconds(250)

    private(set) var hoveredPicture: HoveredPicture?
    @ObservationIgnored private var isPointerOnButtons = false
    @ObservationIgnored private var hiding: Task<Void, Never>?
    @ObservationIgnored private let clock: any ApplicationClock

    init(clock: any ApplicationClock = LiveApplicationClock()) {
        self.clock = clock
    }

    /// The pointer came onto a link of the text: the picture's buttons show at once when it
    /// links to a picture's zoom; another link hides them.
    func pointerEntered(_ location: URL, frame windowFrame: CGRect) {
        stopHiding()
        guard let path = GraphiteOpenLink.zoomedImagePath(of: location) else { return hide() }
        let picture = HoveredPicture(path: path, windowFrame: windowFrame)
        if hoveredPicture != picture { hoveredPicture = picture }
    }

    func pointerLeftLink() {
        guard hoveredPicture != nil, !isPointerOnButtons else { return }
        hideAfterDelay()
    }

    func pointerEnteredButtons() {
        isPointerOnButtons = true
        stopHiding()
    }

    func pointerLeftButtons() {
        isPointerOnButtons = false
        hideAfterDelay()
    }

    /// Hides the buttons at once: the note scrolled, or a button was used.
    func hide() {
        stopHiding()
        isPointerOnButtons = false
        if hoveredPicture != nil { hoveredPicture = nil }
    }

    private func hideAfterDelay() {
        stopHiding()
        hiding = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.hideDelay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.hiding = nil
            self.hoveredPicture = nil
        }
    }

    private func stopHiding() {
        hiding?.cancel()
        hiding = nil
    }
}

/// The buttons of the picture `hover` says the pointer rests on, at the picture's top-right
/// corner, over the reading view. Nothing is drawn, and nothing takes a touch or a click,
/// while the pointer rests on no picture.
struct ReadingPictureHoverLayer: View {
    let hover: ReadingPictureHover
    let actions: ReadingImageActions
    @State private var windowSpace = LinkPreviewWindowSpace()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let picture = hover.hoveredPicture, let frame = windowSpace.overlayRect(fromWindowRect: picture.windowFrame) {
                PictureHoverButtons(zoom: { run(.zoomIn, on: picture.path) },
                                    openInNewTab: actions.tabOpening == nil ? nil : { run(.openInNewTab, on: picture.path) })
                    .onHover { isOnButtons in isOnButtons ? hover.pointerEnteredButtons() : hover.pointerLeftButtons() }
                    .frame(width: frame.width, alignment: .topTrailing)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinkPreviewWindowSpaceReader(space: windowSpace))
    }

    private func run(_ command: PictureCommand, on path: VaultPath) {
        hover.hide()
        actions.perform(command, on: path)
    }
}
