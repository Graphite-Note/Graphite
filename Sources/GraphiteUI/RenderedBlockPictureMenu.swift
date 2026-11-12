/**
 * File: RenderedBlockPictureMenu.swift
 * ------------------------------------
 * Layer: UI
 * Description: Puts the commands of a picture inside a Live Preview table or callout ("Zoom In", "Open in New
 *              Tab", the other side) first in the block's menu when the menu opens on the picture.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// Where the pictures of one rendered block are drawn, kept out of the view's state: only
/// the menu reads them, when it opens.
@MainActor
final class RenderedBlockPictures {
    var frames: [ZoomablePictureFrame] = []

    /// The picture drawn at `point`, in the block's coordinates; the last drawn wins where
    /// two overlap, as it is the one on top.
    func picture(at point: CGPoint) -> ZoomablePictureFrame? {
        frames.last { picture in picture.frame.contains(point) }
    }
}

/// A rendered block's menu (a long press on the iPad, a secondary click on the Mac) opened
/// on one of its pictures starts with that picture's commands. Each picture inside the
/// block's text reports where it is drawn (`InlinePictureView`), and so does a picture that
/// is the block (`EmbeddedImageView`); a block without pictures adds nothing.
struct RenderedBlockPictureMenu: ViewModifier {
    @Environment(\.renderedBlockMenuContext) private var menuContext
    @Environment(\.readingImageActions) private var imageActions
    @State private var pictures = RenderedBlockPictures()

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ZoomablePictureFrame.Key.self) { frames in pictures.frames = frames }
            .onChange(of: imageActions, initial: true) { _, newActions in install(newActions) }
    }

    private func install(_ actions: ReadingImageActions?) {
        guard let menuContext else { return }
        guard let actions else {
            menuContext.pictureItemsAtPoint = nil
            return
        }
        menuContext.pictureItemsAtPoint = { [pictures] point in
            guard let picture = pictures.picture(at: point) else { return [] }
            return actions.blockMenuItems(for: picture)
        }
    }
}
