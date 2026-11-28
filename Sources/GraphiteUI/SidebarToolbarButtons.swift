/**
 * File: SidebarToolbarButtons.swift
 * ---------------------------------
 * Layer: UI
 * Description: The sidebar's Graph View button and the Mac's New Note menu, which the documents' toolbar shows instead
 *              while the Mac's sidebar is hidden.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import SwiftUI

/// One click from the window to the whole vault's graph, in a tab of its own.
struct GraphViewButton: View {
    let showGraph: @MainActor () -> Void

    var body: some View {
        Button("Graph View", systemImage: "point.3.connected.trianglepath.dotted", action: showGraph)
            .tint(.primary)
            .help("Graph View")
    }
}

/// What the Mac's New Note menu does, read from the workspace where the menu is placed.
struct NewDocumentMenuActions {
    let isEnabled: @MainActor (CorePlugin) -> Bool
    /// Names the new file in the Mac's file tree when it is on screen, or asks for the creation sheet.
    let create: @MainActor (CreationKind) -> Void
    let openDailyNote: @MainActor () -> Void
    let newFolder: @MainActor () -> Void
    let importFiles: @MainActor () -> Void
    /// Nil while the Notion Import core plugin is off.
    let importFromNotion: (@MainActor () -> Void)?
}

extension WorkspaceModel {
    func newDocumentMenuActions(creation: Binding<CreationRequest?>) -> NewDocumentMenuActions {
        NewDocumentMenuActions(isEnabled: { [self] plugin in preferences.isEnabled(plugin) },
                               create: { [self] kind in creation.wrappedValue = creationSheet(kind) },
                               openDailyNote: { [self] in Task { await openDailyNote() } },
                               newFolder: { [self] in requestNewFolder(in: newFileDirectory(nil)) },
                               importFiles: { [self] in isChoosingFilesToImport = true },
                               importFromNotion: notionImportOpener)
    }
}

extension WorkspaceModel {
    /// The documents' toolbar's Graph View and New Note while the sidebar is hidden (`HiddenSidebarToolbarButtons`).
    func hiddenSidebarToolbarButtons(isSidebarHidden: Bool, showsNewNote: Bool, creation: Binding<CreationRequest?>) -> HiddenSidebarToolbarButtons {
        HiddenSidebarToolbarButtons(isSidebarHidden: isSidebarHidden, showsGraph: preferences.isEnabled(.graph), showsNewNote: showsNewNote,
                                    showGraph: { [self] in showGraph() }, newDocumentActions: newDocumentMenuActions(creation: creation))
    }
}

/// A click makes a note, as Notes' compose button does; the arrow beside it offers the other kinds.
struct NewDocumentMenuButton: View {
    let actions: NewDocumentMenuActions

    var body: some View {
        Menu { newDocumentMenuItems } label: {
            Label("New Note", systemImage: "square.and.pencil")
        } primaryAction: {
            actions.create(.note)
        }
        .tint(.primary)
        .help("New Note")
    }

    @ViewBuilder private var newDocumentMenuItems: some View {
        Button("New Note", systemImage: "doc.text") { actions.create(.note) }
        Button("New Notebook", systemImage: "book.closed") { actions.create(.notebook) }
        if actions.isEnabled(.bases) {
            Button("New Base", systemImage: "tablecells") { actions.create(.base) }
            Button("New Course", systemImage: "graduationcap") { actions.create(.course) }
        }
        if actions.isEnabled(.canvas) { Button("New Canvas", systemImage: "rectangle.3.group") { actions.create(.canvas) } }
        if actions.isEnabled(.dailyNotes) { Button("Today's Daily Note", systemImage: "calendar", action: actions.openDailyNote) }
        Divider()
        Button("New Folder", systemImage: "folder.badge.plus", action: actions.newFolder)
        ImportMenuButtons(importFiles: actions.importFiles, importFromNotion: actions.importFromNotion)
    }
}

/// The hidden sidebar's Graph View and New Note in the documents' toolbar, before Back and Forward. On the Mac a hidden
/// sidebar's own toolbar items stay in its part of the window's toolbar, which AppKit squeezes beside the window's
/// buttons and empties into the overflow menu (») however wide the window, the sidebar's toggle with them; the sidebar
/// leaves the bar then (`VaultSidebar.showsToolbarButtons`). The iPad and iPhone keep the sidebar's items.
struct HiddenSidebarToolbarButtons: ToolbarContent {
    /// Hidden, by its toggle or by Library mode, and not in Focus, which hides the rest of the bar.
    let isSidebarHidden: Bool
    let showsGraph: Bool
    /// False while the library's home, which has a New button of its own, is shown.
    let showsNewNote: Bool
    let showGraph: @MainActor () -> Void
    let newDocumentActions: NewDocumentMenuActions

    private var isShown: Bool {
        #if os(macOS)
        isSidebarHidden
        #else
        false
        #endif
    }

    var body: some ToolbarContent {
        if isShown && showsGraph { ToolbarItem(placement: .navigation) { GraphViewButton(showGraph: showGraph) } }
        if isShown && showsNewNote { ToolbarItem(placement: .navigation) { NewDocumentMenuButton(actions: newDocumentActions) } }
    }
}
