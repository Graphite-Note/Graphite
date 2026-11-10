/**
 * File: EditorMenuEntries.swift
 * -----------------------------
 * Layer: UI
 * Description: The editor's Format and Insert menus as SwiftUI menus (toolbar and Mac menu bar), drawn from the
 *              same entries as the context menu, and the place the focused note leaves them for the menu bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import Observation

/// Draws `EditorContextMenuEntry` values as the items of a SwiftUI menu: actions as buttons,
/// submenus as menus, and groups set apart from what comes before them by a divider.
struct EditorMenuEntriesView: View {
    let entries: [EditorContextMenuEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { entryIndex, entry in
            switch entry.content {
            case .action(let isEnabled, let perform):
                Button(action: perform) {
                    if let systemImage = entry.systemImage { MenuItemLabel(title: entry.title, systemImage: systemImage) } else { Text(entry.title) }
                }
                .disabled(!isEnabled)
            case .submenu(let submenuEntries):
                Menu {
                    EditorMenuEntriesView(entries: submenuEntries)
                } label: {
                    if let systemImage = entry.systemImage { MenuItemLabel(title: entry.title, systemImage: systemImage) } else { Text(entry.title) }
                }
            case .group(let groupEntries):
                if entryIndex > 0 { Divider() }
                EditorMenuEntriesView(entries: groupEntries)
            }
        }
    }
}

/// The items of the Format and Insert menus of the menu bar, made for the note being edited.
struct EditorMenuEntries {
    let format: [EditorContextMenuEntry]
    let insert: [EditorContextMenuEntry]
}

/// The note being edited in the focused side of the window. The menu bar, which sits outside
/// every pane, asks it for the Format and Insert menus; nothing is registered while the focused
/// side shows no note or reads one, which dims both menus.
@MainActor
@Observable
final class EditorMenuRegistry {
    private struct Registration {
        let tabID: UUID
        let makeEntries: () -> EditorMenuEntries
    }

    private var registration: Registration?

    /// The menus' items for the registered note; nil when no note is being edited.
    var entries: EditorMenuEntries? { registration?.makeEntries() }

    /// A tab's note pane takes over, as it is focused and shows the note for editing.
    func register(tabID: UUID, makeEntries: @escaping () -> EditorMenuEntries) {
        registration = Registration(tabID: tabID, makeEntries: makeEntries)
    }

    /// A tab's pane lets go; another pane that registered since keeps its menus.
    func unregister(tabID: UUID) {
        guard registration?.tabID == tabID else { return }
        registration = nil
    }
}

/// What the Format and Insert menus of the menu bar depend on in a note's pane: when it changes,
/// the pane makes them again.
struct EditorMenuRegistrationKey: Equatable {
    var isEditingInFocusedSide: Bool
    var session: ObjectIdentifier
    var colors: [PaletteColor]?
    var offersTemplates: Bool
}
