/**
 * File: LibraryHome.swift
 * -----------------------
 * Layer: UI
 * Description: The library as the window's home in Library mode: the house button of the tab bar, the sidebar folding away,
 *              and what the library's top row offers of the window.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 05/11/2026
 */

import SwiftUI
import GraphiteCore

/// The library as the window's home in Library mode on the iPad and the Mac: a house
/// button leads the first side's tab bar, and the library covers that side until a tab
/// is chosen. Documents stay open beneath it.
struct LibraryHomeButton: View {
    let library: LibraryModel
    @Environment(\.accent) private var accent

    var body: some View {
        Button {
            Task { await library.showHome() }
        } label: {
            Image(systemName: library.isShownAsHome ? "house.fill" : "house")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(library.isShownAsHome ? accent : Color.secondary)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library")
        .accessibilityAddTraits(library.isShownAsHome ? .isSelected : [])
        .help("Library")
    }
}

/// Folds the sidebar away when the library takes over files, so the window is either a
/// library and tabs or Obsidian's tree and tabs, as the switch in each chooses. Search in
/// all files may still open it, for its results; nothing else does.
struct LibraryModeSidebarVisibility: ViewModifier {
    let presentation: LibraryPresentation
    let isCompactWidth: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    /// The presentation this modifier last answered. The column folds in the change that follows a switch to Library,
    /// after one update of the window in which the switch is made and the column still shown.
    @State private var answeredPresentation: LibraryPresentation?

    func body(content: Content) -> some View {
        content
            .environment(\.sidebarFilesPlace, sidebarFilesPlace)
            .onChange(of: presentation, initial: true) { previousPresentation, presentation in
                answeredPresentation = presentation
                guard !isCompactWidth else { return }
                switch presentation {
                case .library: columnVisibility = .detailOnly
                // Switching to List opens the file tree it switched to; a launch in List keeps
                // the window's own choice, which its first shape made (`GraphiteRootView`).
                case .list: if previousPresentation == .library { columnVisibility = .all }
                }
            }
    }

    /// Where the sidebar's files are, counting the update in which the switch to Library is made and the column is about to
    /// fold: the sidebar then builds no list it would drop again at once (the Tags view of 3,000 tags in the owner's vault).
    private var sidebarFilesPlace: SidebarFilesPlace {
        guard presentation == .library, !isCompactWidth else { return .fileTree }
        return answeredPresentation != .library || columnVisibility == .detailOnly ? .foldedByLibrary : .besideLibrary
    }
}

/// What the sidebar does with the vault's files, which Library mode shows in the library on a window wider than a phone.
enum SidebarFilesPlace {
    /// List mode, or a phone, whose sidebar lists the files (a phone's as the library itself).
    case fileTree
    /// Library mode has folded the sidebar out of the window, where nothing of it is seen: it keeps the file tree it had
    /// rather than building another list behind the library, so the switch back to List finds the tree as it was.
    case foldedByLibrary
    /// A search opened the sidebar beside the library, which is the file browser: the sidebar offers its other panels.
    case besideLibrary
}

extension EnvironmentValues {
    /// Set by the window's root view (`LibraryModeSidebarVisibility`); a sidebar shown alone lists its files.
    @Entry var sidebarFilesPlace = SidebarFilesPlace.fileTree
}

/// What the library's top row offers of the window once the sidebar is gone: finding a
/// file, the vaults, and Settings.
struct LibraryWindowActions {
    let showSearch: () -> Void
    let showSettings: () -> Void
    let showVaults: () -> Void
    /// What the window's navigation bar held, moved into the library's own row where that bar is hidden over the library (the
    /// iPad); nil where the window keeps its bar.
    var navigationControls: LibraryNavigationControls?
}

/// Back and Forward through the files seen, and the recording control: the controls of the iPad's navigation bar, which the
/// library draws in its own row instead of leaving a band above it with a small capsule of buttons in it.
struct LibraryNavigationControls {
    let goBack: () -> Void
    let goForward: () -> Void
    let canGoBack: Bool
    let canGoForward: Bool
    /// The window's recording control, nil when it offers none.
    let recordingControl: AnyView?
}

extension EnvironmentValues {
    /// Nil outside a window that provides them; the library then offers none of them.
    @Entry var libraryWindowActions: LibraryWindowActions?
}

extension WorkspaceModel {
    /// Where a file chosen in the library opens: in the active tab when it is empty, as
    /// there is nothing to keep there, else in a tab of its own.
    var libraryOpeningPlacement: TabPlacement {
        layout.activeTab.path == nil && layout.activeTab.coreView == nil && activeDocument.pluginViewIdentifier == nil ? .currentTab : .newTab
    }
}

/// The window's buttons at the start of the library's controls, which the sidebar and the navigation bar offered before the
/// library replaced them: Back, Forward and recording where the navigation bar is hidden over the library, then Settings and
/// the quick switcher. A phone's sidebar still has Settings and the quick switcher.
struct LibraryWindowButtons: View {
    @Environment(\.libraryWindowActions) private var windowActions
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if let navigationControls = windowActions?.navigationControls, horizontalSizeClass != .compact {
            Button("Back", systemImage: "chevron.backward", action: navigationControls.goBack)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(!navigationControls.canGoBack)
            Button("Forward", systemImage: "chevron.forward", action: navigationControls.goForward)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(!navigationControls.canGoForward)
            if let recordingControl = navigationControls.recordingControl {
                recordingControl
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        if let windowActions, horizontalSizeClass != .compact {
            Button("Settings", systemImage: "gearshape", action: windowActions.showSettings)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .help("Settings")
            Button("Find a File", systemImage: "magnifyingglass", action: windowActions.showSearch)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .help("Find a file (⌘O)")
        }
    }
}
