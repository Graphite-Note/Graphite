/**
 * File: EmbeddedImageView.swift
 * -----------------------------
 * Layer: UI
 * Description: A picture or drawing on a line of its own in a note, in reading view and Live Preview: a tap
 *              zooms into it or edits the drawing, and its menu and hover buttons open it in a tab.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

import SwiftUI
import GraphiteCore

/// An image embedded in a note. A Graphite drawing opens for editing when tapped, as in
/// Goodnotes, and carries an Edit button so that is visible; any other image zooms in over
/// the window when tapped, and opens in a new tab when ⌘-clicked on the Mac, as a link does. While the
/// pointer or Apple Pencil rests on it, it shows a magnifier and an "Open in New Tab"
/// button; its menu has those and the rest.
struct EmbeddedImageView: View {
    /// What the embed was given to show.
    private enum ImageSource {
        /// Pixels already decoded away from the main thread, drawn as they are.
        case decoded(CGImage)
        /// Encoded image data, which the view decodes away from the main thread once.
        case encoded(Data)
    }

    private let imageSource: ImageSource
    let aspectRatio: CGFloat
    let displayWidth: CGFloat?
    /// Opens the drawing editor; nil for an image that is not an editable drawing.
    let edit: (() -> Void)?
    /// Zooms into the image over the window.
    let view: (() -> Void)?
    /// Opens the drawing editor over the image; nil for drawings and where drawings are off.
    let drawOnImage: (() -> Void)?
    /// The picture's file in the vault, which opens in a tab; nil with no tabs to open it in.
    private let tabbedPicture: (path: VaultPath, opening: PictureTabOpening)?
    /// The picture's file in the vault, which a Live Preview block's menu lists the commands of.
    private let picturePath: VaultPath?
    /// Set in a Live Preview block, whose own menu takes the long press and the secondary click.
    @Environment(\.renderedBlockMenuContext) private var blockMenuContext
    @State private var decodedImages = DecodedImageCache()
    /// Whether the pointer or Apple Pencil rests over the image, which shows its buttons.
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    /// A drawing is saved as it looks on white paper, and a drawing without paper of its
    /// own is transparent: on a dark note its black ink would vanish, so it is shown on
    /// white, as it looks in every other app.
    private var showsDrawingOnWhite: Bool { edit != nil && colorScheme == .dark }

    /// Shows pixels already decoded at the size they are shown, off the main thread, so no
    /// evaluation of the body decodes anything and every one draws the same image.
    /// - Parameter path: The picture's file, which `tabOpening` opens in a tab.
    init(image: CGImage, aspectRatio: CGFloat, displayWidth: CGFloat?, edit: (() -> Void)?, view: (() -> Void)?, drawOnImage: (() -> Void)? = nil,
         path: VaultPath? = nil, tabOpening: PictureTabOpening? = nil) {
        self.init(imageSource: .decoded(image), aspectRatio: aspectRatio, displayWidth: displayWidth, edit: edit, view: view, drawOnImage: drawOnImage,
                  tabbedPicture: path.flatMap { path in tabOpening.map { opening in (path, opening) } }, picturePath: path)
    }

    /// Shows encoded image data, decoded away from the main thread when the view appears.
    init(imageData: Data, aspectRatio: CGFloat, displayWidth: CGFloat?, edit: (() -> Void)?, view: (() -> Void)?, drawOnImage: (() -> Void)? = nil) {
        self.init(imageSource: .encoded(imageData), aspectRatio: aspectRatio, displayWidth: displayWidth, edit: edit, view: view, drawOnImage: drawOnImage,
                  tabbedPicture: nil, picturePath: nil)
    }

    private init(imageSource: ImageSource, aspectRatio: CGFloat, displayWidth: CGFloat?, edit: (() -> Void)?, view: (() -> Void)?,
                 drawOnImage: (() -> Void)?, tabbedPicture: (path: VaultPath, opening: PictureTabOpening)?, picturePath: VaultPath?) {
        self.imageSource = imageSource
        self.aspectRatio = aspectRatio
        self.displayWidth = displayWidth
        self.edit = edit
        self.view = view
        self.drawOnImage = edit == nil ? drawOnImage : nil
        self.tabbedPicture = tabbedPicture
        self.picturePath = picturePath
    }

    var body: some View {
        image
            .overlay(alignment: .topTrailing) {
                if let edit {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil.tip.crop.circle")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Edit Drawing")
                } else if let view, isHovered {
                    PictureHoverButtons(zoom: view, openInNewTab: tabbedPicture.map { picture in { picture.opening.open(picture.path, .newTab) } })
                }
            }
            .contentShape(Rectangle())
            .onHover { isPointerOver in isHovered = isPointerOver }
            .onTapGesture { (edit ?? view)?() }
            #if os(macOS)
            // ⌘-click opens the picture in a new tab, as for a link; the gesture waits for ⌘.
            // SwiftUI gives the iPad no modifier keys on a tap; its menu has the command.
            .highPriorityGesture(TapGesture().modifiers(.command).onEnded { open(at: .newTab) }, including: tabbedPicture == nil ? .none : .all)
            #endif
            .modifier(PictureMenu(blockPicture: blockPicture) { menuItems })
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(edit != nil ? "Opens the drawing to edit" : "Opens the image to zoom")
            .accessibilityActions {
                if let drawOnImage { Button("Draw on Image", action: drawOnImage) }
                // Zooming is the image's own action; the tabs are named.
                ForEach(offeredCommands.filter { command in command != .zoomIn }, id: \.self) { command in
                    Button(command.title(otherSideTitle: otherSideTitle)) { perform(command) }
                }
            }
    }

    /// In a Live Preview block, the picture as the block's menu lists it: the block's view
    /// carries its own menu, which took the long press and the secondary click from the picture's,
    /// so a picture offered only "Edit Source" there (HUNT-330). Nil outside a block.
    private var blockPicture: ZoomablePictureFrame? {
        guard blockMenuContext != nil, let picturePath else { return nil }
        let shownImage: CGImage? = if case .decoded(let decodedImage) = imageSource { decodedImage } else { nil }
        return ZoomablePictureFrame(path: picturePath, frame: .zero, isEditableDrawing: edit != nil, shownImage: shownImage)
    }

    @ViewBuilder private var menuItems: some View {
        if let edit { Button("Edit Drawing", systemImage: "pencil.tip.crop.circle", action: edit) }
        if let drawOnImage { Button("Draw on Image", systemImage: "pencil.tip.crop.circle.badge.plus", action: drawOnImage) }
        ForEach(offeredCommands, id: \.self) { command in
            Button(command.title(otherSideTitle: otherSideTitle), systemImage: command.systemImage) { perform(command) }
        }
        #if canImport(UIKit)
        Button("Copy Image", systemImage: "doc.on.doc") { copyImage() }
        #endif
    }

    /// The picture's commands for its menu: zooming where it zooms, tabs where it has them.
    private var offeredCommands: [PictureCommand] {
        PictureCommand.allCases.filter { command in
            switch command {
            case .zoomIn: view != nil
            case .openInNewTab, .openOnOtherSide: tabbedPicture != nil
            }
        }
    }

    private var otherSideTitle: String { tabbedPicture?.opening.otherSideTitle ?? "" }

    private func perform(_ command: PictureCommand) {
        switch command {
        case .zoomIn: view?()
        case .openInNewTab: open(at: .newTab)
        case .openOnOtherSide: open(at: .otherGroup)
        }
    }

    private func open(at placement: TabPlacement) {
        guard let tabbedPicture else { return }
        tabbedPicture.opening.open(tabbedPicture.path, placement)
    }

    #if canImport(UIKit)
    /// Copies the image as shown, so it can be pasted into another note or app.
    private func copyImage() {
        switch imageSource {
        case .decoded(let decodedImage):
            UIPasteboard.general.image = UIImage(cgImage: decodedImage)
        case .encoded(let imageData):
            guard let image = decodedImages.image(for: imageData) else { return }
            UIPasteboard.general.image = image
        }
    }
    #endif

    @ViewBuilder private var image: some View {
        switch imageSource {
        case .decoded(let decodedImage):
            sized(Image(decodedImage, scale: 1, label: Text("Image")).resizable())
        case .encoded(let imageData):
            decodingImage(from: imageData)
        }
    }

    /// The last decoded image stays on screen while changed data decodes, so an edited
    /// drawing does not blink; data that does not decode shows nothing.
    @ViewBuilder private func decodingImage(from imageData: Data) -> some View {
        if let decodedImage = decodedImages.latestImage {
            #if canImport(UIKit)
            decoding(imageData, in: sized(Image(uiImage: decodedImage).resizable()))
            #else
            decoding(imageData, in: sized(Image(nsImage: decodedImage).resizable()))
            #endif
        } else if !decodedImages.hasDecoded(imageData) {
            // Takes the image's place while it decodes, at its size, so the note does not
            // move when the image appears.
            decoding(imageData, in: sized(Rectangle().fill(.quaternary.opacity(0.4))))
        } else {
            // Takes no space, but stays to decode the next data the embed is given.
            decoding(imageData, in: Color.clear.frame(width: 0, height: 0))
        }
    }

    private func decoding(_ imageData: Data, in content: some View) -> some View {
        content.task(id: imageData) { await decodedImages.prepareImage(for: imageData) }
    }

    private func sized(_ content: some View) -> some View {
        content
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background { if showsDrawingOnWhite { Color.white } }
            .clipShape(RoundedRectangle(cornerRadius: showsDrawingOnWhite ? 6 : 0))
            .frame(maxWidth: displayWidth ?? .infinity, alignment: .leading)
    }
}

/// The buttons at a picture's top-right corner while the pointer or Apple Pencil rests on
/// it: Obsidian's magnifier, then "Open in New Tab" where the window has tabs. They exist
/// only while the pointer is there.
struct PictureHoverButtons: View {
    let zoom: () -> Void
    let openInNewTab: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            button(.zoomIn, help: "Zoom in", action: zoom)
            if let openInNewTab { button(.openInNewTab, help: "Open in new tab", action: openInNewTab) }
        }
        .padding(8)
    }

    private func button(_ command: PictureCommand, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: command.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(command.title(otherSideTitle: ""))
    }
}

/// A picture's own menu, or, in a Live Preview block, the place its commands take in the
/// block's menu (`RenderedBlockPictureMenu`): reported where the picture is drawn, in the
/// block's coordinates. A block's picture stays in its block, so the choice never changes for
/// a view.
private struct PictureMenu<MenuItems: View>: ViewModifier {
    let blockPicture: ZoomablePictureFrame?
    @ViewBuilder let menuItems: () -> MenuItems

    func body(content: Content) -> some View {
        if let blockPicture {
            content.background {
                GeometryReader { geometry in
                    let frameInBlock = geometry.frame(in: .named(LivePreviewTableEditor.blockCoordinateSpaceName))
                    Color.clear.preference(key: ZoomablePictureFrame.Key.self, value: [ZoomablePictureFrame(
                        path: blockPicture.path, frame: frameInBlock, isEditableDrawing: blockPicture.isEditableDrawing, shownImage: blockPicture.shownImage)])
                }
            }
        } else {
            content.contextMenu { menuItems() }
        }
    }
}
