/**
 * File: DocumentModeToggle.swift
 * ------------------------------
 * Layer: UI
 * Description: The Write toggle, the control row, and where a document puts Write, Undo and Redo and the Pencil
 *              tools.
 *
 * Authors: Bahey Shalash, Claude, felixchvl
 * Version: 0.7
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// The same reading/writing switch for notes, PDF notebooks and canvases: one pencil that
/// is picked up to write and put down to read, as Obsidian's view toggle, rather than a
/// wide segmented control. Writing is marked by the accent and a faint fill, not by color
/// alone, and VoiceOver reads the state. A toolbar too narrow for it moves it into its
/// overflow menu as a checked item, where a segmented control was not offered at all.
struct DocumentModeToggle: View {
    @Binding var isWriting: Bool
    /// Drawn by Graphite, for rows outside the window's toolbar such as the tab bar; the
    /// toolbar draws its own toggles.
    var drawsOwnBackground = false
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if drawsOwnBackground {
                Button { isWriting.toggle() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: isWriting ? .semibold : .regular))
                        .foregroundStyle(isWriting ? accent : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background(isWriting ? accent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write")
                .accessibilityValue(isWriting ? "On" : "Off")
                .accessibilityAddTraits(isWriting ? .isSelected : [])
            } else {
                Toggle(isOn: $isWriting) {
                    Label("Write", systemImage: "pencil")
                }
                .toggleStyle(.button)
                // The toolbar's buttons are neutral; the toggle in use takes the accent.
                .tint(accent)
            }
        }
        .help(isWriting ? "Writing. Choose to read." : "Reading. Choose to write.")
        .accessibilityIdentifier("documentModePicker")
    }
}

/// A row of its own for Write, Undo, and Redo, when neither the window's toolbar nor the
/// tab bar has room for them (`DocumentToolbarLayout`): quiet, in the page's color, with
/// the controls at its trailing end in the toolbar's order.
struct DocumentControlRow<TrailingControls: View>: View {
    @Binding var isWriting: Bool
    @ViewBuilder var trailingControls: TrailingControls

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 8)
            // Neutral, as in the toolbar; the accent marks selection and links.
            trailingControls
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.secondary)
            DocumentModeToggle(isWriting: $isWriting, drawsOwnBackground: true)
        }
        .padding(.horizontal, 12)
        .frame(height: GraphiteChrome.barHeight)
        .background(GraphiteChrome.barBackground)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Where a document puts its Write toggle, Undo, and Redo.
enum DocumentToolbarLayout {
    /// The window's toolbar holds the navigation buttons, the title, recording, the
    /// document's own tools, Undo, Redo, Write and More. Narrower than this, iPadOS moves
    /// the last buttons into an overflow menu, where Undo and Redo would be a menu away,
    /// so they move below the toolbar instead: to the end of the tab bar, or to a row of
    /// their own where that has no room either.
    static let minimumDetailWidthForToolbarControls: CGFloat = 1_100

    /// The narrowest tab bar that holds the controls and still shows two tabs. Its own
    /// buttons and the controls take about 250 points.
    static let minimumTabBarWidthForControls: CGFloat = 480

    /// Whether the controls leave the window's toolbar for the tab bar or a row below it.
    /// A compact width never does: there, as on a phone, the navigation bar holds only the
    /// document's controls, and moving between files happens in the bottom bar.
    /// Nor does a window of compact height: a Plus or Max phone held sideways is a regular
    /// width but has 430 points of height, and a row of 44 points for three controls is a
    /// tenth of it; its navigation bar holds them.
    /// - Parameters:
    ///   - detailWidth: The width of the documents area, nil when unknown.
    ///   - verticalSizeClass: The window's vertical size class, nil when unknown.
    static func usesControlRow(detailWidth: CGFloat?, horizontalSizeClass: UserInterfaceSizeClass?,
                               verticalSizeClass: UserInterfaceSizeClass? = nil) -> Bool {
        if horizontalSizeClass == .compact || verticalSizeClass == .compact { return false }
        guard let detailWidth else { return false }
        return detailWidth < minimumDetailWidthForToolbarControls
    }

    /// Whether the navigation bar and the tab bar give way while the keyboard is up: in a window of compact height, a
    /// phone held sideways, where the keyboard and its format toolbar leave the note about 40 of 400 points otherwise.
    static func hidesChromeWhileTyping(verticalSizeClass: UserInterfaceSizeClass?, isKeyboardShown: Bool) -> Bool {
        verticalSizeClass == .compact && isKeyboardShown
    }

    /// Narrower than this, a document's secondary toolbar actions (a PDF's pages, find and
    /// adding pages) go to its More menu, as in a compact width: a window this narrow beside
    /// another app also shows the window's own controls in its toolbar, and the actions
    /// pushed the title and More out of it (reported by the owner, 2026-10-13).
    static let minimumDetailWidthForSecondaryActions: CGFloat = 760

    static func foldsSecondaryActions(detailWidth: CGFloat?, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        if horizontalSizeClass == .compact { return true }
        guard let detailWidth else { return false }
        return detailWidth < minimumDetailWidthForSecondaryActions
    }

    /// Whether the controls the toolbar has no room for go to the end of a side's tab bar.
    /// A row of their own would take a strip of the page for three controls; the tab bar is
    /// there anyway and mostly empty.
    /// - Parameter tabBarWidth: The width of that side, nil when unknown.
    static func showsControlsInTabBar(usesControlRow: Bool, showsTabBar: Bool, tabBarWidth: CGFloat?) -> Bool {
        guard usesControlRow, showsTabBar, let tabBarWidth else { return false }
        return tabBarWidth >= minimumTabBarWidthForControls
    }

    /// What a tab bar keeps for its tabs beside the tools: one tab at least.
    static let minimumTabsWidthBesidePencilTools: CGFloat = 160
    /// The tab bar's own buttons: the tab overview with the tab group menu, New Tab, and
    /// Split Right, 36 points each with their spacing and the bar's end.
    static let tabBarButtonsWidth: CGFloat = 122
    /// Undo, Redo and Write, when the tab bar holds them, with room to spare for larger
    /// Dynamic Type.
    static let documentControlsWidth: CGFloat = 160

    /// Whether a side's tab bar holds the fixed bar's tools, so they take no row of their
    /// own above the page: when what is left beside the tabs, the tab bar's buttons and the
    /// document's controls holds the tools' compact row, counted from the tools the bar has
    /// (`PencilToolRowLayout.compactRowWidth`), not from a constant that a fourth ink would
    /// make wrong. A row of their own never scrolls either (`PencilToolRow`), so this only
    /// decides where they stand.
    /// - Parameters:
    ///   - tabBarWidth: The width of that side, nil when unknown.
    ///   - toolCount: How many tools the bar shows (`PencilToolRowLayout.tools`).
    static func showsPencilToolsInTabBar(showsTabBar: Bool, tabBarWidth: CGFloat?, showsDocumentControls: Bool, toolCount: Int) -> Bool {
        guard showsTabBar, let tabBarWidth else { return false }
        let widthBesideTools = minimumTabsWidthBesidePencilTools + tabBarButtonsWidth + (showsDocumentControls ? documentControlsWidth : 0)
        return tabBarWidth - widthBesideTools >= PencilToolRowLayout.compactRowWidth(toolCount: toolCount)
    }
}

extension EnvironmentValues {
    /// Whether documents show Write, Undo, and Redo below the navigation bar, in the tab
    /// bar or a row of their own (`DocumentControlRow`); nil where no workspace measured
    /// its width, which then keeps them in the toolbar.
    @Entry var usesDocumentControlRow: Bool? = nil
    /// True where the side's tab bar shows those controls (`TabBarDocumentControls`), so
    /// the document shows no row for them.
    @Entry var showsDocumentControlsInTabBar = false
    /// True where the side's tab bar has room for the fixed bar's tools
    /// (`TabBarPencilTools`), so a PDF written on shows no row for them.
    @Entry var showsPencilToolsInTabBar = false
    /// True where the window shows two sides at once, so the system's Pencil palette, which
    /// hangs from the window, gives way to the fixed bar (`PencilToolbarStyle.inEffect`).
    @Entry var sharesWindowWithOtherSide = false
    /// False for the panes of a stacked side that are not its active tab, which share the
    /// side's controls and show no row of their own for them. A side's panes show the row
    /// whether or not the side is focused, so tapping the other side moves nothing.
    @Entry var isActiveInItsSide = true
    /// True where a document's secondary toolbar actions go to its More menu
    /// (`DocumentToolbarLayout.foldsSecondaryActions`).
    @Entry var foldsSecondaryToolbarActions = false
}

/// Undo, Redo and Write of a side's active document, at the end of its tab bar.
struct TabBarDocumentControls: View {
    let tab: WorkspaceTab
    let document: TabDocument
    let defaultEditingMode: EditingMode
    /// Whether this side is focused, and so shows the Pencil palette of a PDF written on.
    var isFocused = true
    #if canImport(UIKit)
    @AppStorage(PDFAnnotationPreferenceKey.showsToolPicker) private var showsPencilTools = true
    @AppStorage(PencilToolbarStyle.preferenceKey) private var chosenPencilToolbarStyle = PencilToolbarStyle.floating
    @Environment(\.sharesWindowWithOtherSide) private var sharesWindowWithOtherSide
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        // A tab whose file is still loading has the sessions of the file before it.
        if tab.path != nil, document.loadedPath == tab.path {
            if let session = document.markdownSession {
                let isEditing = session.viewMode != .reading
                controls(isWriting: Binding(get: { session.viewMode != .reading }, set: { shouldWrite in
                    if shouldWrite != (session.viewMode != .reading) { session.toggleReadingView(editingMode: defaultEditingMode) }
                })) {
                    #if canImport(UIKit)
                    if isEditing { UndoRedoButtons(availability: session.undoAvailability) }
                    #endif
                }
            } else {
                #if canImport(UIKit)
                if let session = document.canvasSession {
                    controls(isWriting: Binding(get: { session.isWriting }, set: { isWriting in session.isWriting = isWriting })) {
                        if session.isWriting { UndoRedoButtons(availability: session.undoAvailability) }
                    }
                }
                if let session = document.pdfSession, !session.isProtected {
                    controls(isWriting: Binding(get: { session.isWriting }, set: { isWriting in session.isWriting = isWriting })) {
                        // The floating palette has Undo and Redo of its own.
                        if !session.showsFloatingPencilPalette(style: chosenPencilToolbarStyle.inEffect(sharesWindowWithOtherSide: sharesWindowWithOtherSide),
                                                                showsTools: showsPencilTools,
                                                                horizontalSizeClass: horizontalSizeClass, isFocused: isFocused) {
                            UndoRedoButtons(availability: session.undoAvailability)
                        }
                    }
                }
                #endif
            }
        }
    }

    /// The same order as in the window's toolbar: the document's buttons, then Write.
    private func controls<Buttons: View>(isWriting: Binding<Bool>, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 12) {
            buttons()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.secondary)
            DocumentModeToggle(isWriting: isWriting, drawsOwnBackground: true)
        }
    }
}
