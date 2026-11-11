/**
 * File: PictureActions.swift
 * --------------------------
 * Layer: UI
 * Description: What a picture shown in a note offers wherever it is drawn: zooming into it over the window,
 *              and opening it in a tab of its own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// One command a picture shown in a note offers, declared once here (`FR-23`): its menu (a
/// long press, a secondary click), its buttons while the pointer rests on it and VoiceOver's
/// actions are all made from these.
enum PictureCommand: CaseIterable, Hashable {
    /// The picture fitted to the window over the note (`ImageZoomOverlay`).
    case zoomIn
    /// The picture's file in a tab of its own (`ImagePane`), the note's tab left as it is.
    case openInNewTab
    /// The picture's file on the other side of the split.
    case openOnOtherSide

    /// `otherSideTitle` is the window's own wording for the other side of its split.
    func title(otherSideTitle: String) -> String {
        switch self {
        case .zoomIn: "Zoom In"
        case .openInNewTab: VaultEntryAction.openInNewTab.title(otherSideTitle: otherSideTitle)
        case .openOnOtherSide: VaultEntryAction.openOnOtherSide.title(otherSideTitle: otherSideTitle)
        }
    }

    var systemImage: String {
        switch self {
        case .zoomIn: "plus.magnifyingglass"
        case .openInNewTab: VaultEntryAction.openInNewTab.systemImage
        case .openOnOtherSide: VaultEntryAction.openOnOtherSide.systemImage
        }
    }

    /// The two a picture shows as buttons while the pointer rests on it, as Obsidian shows
    /// its magnifier; the menu has them all.
    static let hoverButtons: [PictureCommand] = [.zoomIn, .openInNewTab]
}

/// Opening a picture of the vault as a tab of its own, which a window with tabs provides.
struct PictureTabOpening {
    /// Opens the picture's file where `TabPlacement` says, as a link to it opens.
    let open: (VaultPath, TabPlacement) -> Void
    /// The window's wording for the other side of its split, such as "Open to the Right".
    let otherSideTitle: String

    /// Where a click on a picture with `modifiers` held opens it, as for a link: ⌘ a new tab,
    /// ⌥⌘ the other side, ⇧⌥⌘ a new window; nil without ⌘, which zooms.
    static func placement(forClickWith modifiers: EventModifiers) -> TabPlacement? {
        guard modifiers.contains(.command) else { return nil }
        return TabPlacement.forLink(command: true, option: modifiers.contains(.option), shift: modifiers.contains(.shift))
    }
}

/// What a note's pictures can do, in reading view, in Live Preview's rendered blocks and on a
/// canvas's cards. Closures cannot be compared, so two values are equal when the same
/// workspace provides them with the same abilities; views that read them then do not
/// update each time the note is drawn again.
struct ReadingImageActions: Equatable {
    let providerIdentity: ObjectIdentifier
    /// Zooms into a picture over the window (`ImageZoomOverlay`).
    let viewImage: (VaultPath) -> Void
    /// Opens a Graphite drawing in the drawing editor; nil where drawings cannot be edited.
    let editDrawing: ((VaultPath) -> Void)?
    /// Opens the drawing editor over an image; nil where drawings are off.
    var drawOnImage: ((VaultPath) -> Void)? = nil
    /// Opens a picture in a tab of its own; nil where there are no tabs to open it in.
    var tabOpening: PictureTabOpening? = nil

    static func == (leftActions: ReadingImageActions, rightActions: ReadingImageActions) -> Bool {
        leftActions.providerIdentity == rightActions.providerIdentity && (leftActions.editDrawing == nil) == (rightActions.editDrawing == nil)
            && (leftActions.drawOnImage == nil) == (rightActions.drawOnImage == nil)
            && leftActions.tabOpening?.otherSideTitle == rightActions.tabOpening?.otherSideTitle
    }

    /// The commands a picture offers, in menu order: zooming always, tabs where the window has them.
    var offeredCommands: [PictureCommand] { tabOpening == nil ? [.zoomIn] : PictureCommand.allCases }

    func title(of command: PictureCommand) -> String {
        command.title(otherSideTitle: tabOpening?.otherSideTitle ?? "")
    }

    func perform(_ command: PictureCommand, on path: VaultPath) {
        switch command {
        case .zoomIn: viewImage(path)
        case .openInNewTab: tabOpening?.open(path, .newTab)
        case .openOnOtherSide: tabOpening?.open(path, .otherGroup)
        }
    }

    /// Opens a picture clicked or tapped with `modifiers` held where they say; false without
    /// ⌘ or tabs, which leaves the click to zoom.
    func open(_ path: VaultPath, clickedWith modifiers: EventModifiers) -> Bool {
        guard let tabOpening, let placement = PictureTabOpening.placement(forClickWith: modifiers) else { return false }
        tabOpening.open(path, placement)
        return true
    }

    /// The picture's commands as items of a rendered block's menu in Live Preview.
    func blockMenuItems(for path: VaultPath) -> [RenderedBlockMenuItem] {
        offeredCommands.map { command in
            RenderedBlockMenuItem(title: title(of: command), symbolName: command.systemImage, action: { perform(command, on: path) })
        }
    }
}

extension EnvironmentValues {
    @Entry var readingImageActions: ReadingImageActions? = nil
}

/// VoiceOver's actions for a picture: each of its commands by name, so a picture inside a
/// sentence or a table cell, which the text draws, can be zoomed and opened like any other.
struct PictureAccessibilityActions: ViewModifier {
    let path: VaultPath?
    let actions: ReadingImageActions?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let path, let actions {
                ForEach(actions.offeredCommands, id: \.self) { command in
                    Button(actions.title(of: command)) { actions.perform(command, on: path) }
                }
            }
        }
    }
}

/// A picture of the vault drawn inside text, in a sentence or a table cell. The text takes
/// its taps and clicks (its run links to its zoom), so the picture adds only VoiceOver's
/// actions and the frame a rendered block's own tap target and menu need.
struct InlinePictureView: View {
    let image: CGImage
    let description: String
    /// The picture's path in the vault; nil outside it.
    let path: VaultPath?
    @Environment(\.readingImageActions) private var imageActions

    var body: some View {
        Image(image, scale: 1, label: Text(description)).resizable().scaledToFit()
            // Where it is drawn, for a table's cell editor in Live Preview, whose tap target
            // covers the table and leaves a tap on a picture to its zoom, and for the block's menu.
            .background {
                if let path {
                    GeometryReader { geometry in
                        let frameInBlock = geometry.frame(in: .named(LivePreviewTableEditor.blockCoordinateSpaceName))
                        Color.clear.preference(key: ZoomablePictureFrame.Key.self, value: [ZoomablePictureFrame(path: path, frame: frameInBlock)])
                    }
                }
            }
            .modifier(PictureAccessibilityActions(path: path, actions: imageActions))
    }
}
