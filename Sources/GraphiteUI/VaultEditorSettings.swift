/**
 * File: VaultEditorSettings.swift
 * -------------------------------
 * Layer: UI
 * Description: The editor options Obsidian keeps in the vault's app.json, read from the vault when it sets them and from this device otherwise.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// The editor options Obsidian keeps in the vault's `.obsidian/app.json` and Graphite used to
/// keep only on the device. A vault whose file sets one uses it, as in Obsidian; until it
/// does, the choice made on this device applies, and choosing one writes the key into the
/// file. Without a vault open the device's choice is the one changed.
extension WorkspaceModel {
    var usesReadableLineLength: Bool { vaultSettings.usesReadableLineLength ?? preferences.usesReadableLineLength }

    var showsInlineTitle: Bool { vaultSettings.showsInlineTitle ?? preferences.showsInlineTitle }

    var usesSpellChecking: Bool { vaultSettings.usesSpellChecking ?? preferences.usesSpellChecking }

    var defaultNoteView: DefaultNoteView {
        vaultSettings.defaultViewMode.map { mode in mode == .preview ? DefaultNoteView.reading : .editing } ?? preferences.defaultNoteView
    }

    var defaultEditingMode: EditingMode {
        vaultSettings.usesLivePreview.map { usesLivePreview in usesLivePreview ? EditingMode.livePreview : .source } ?? preferences.defaultEditingMode
    }

    /// The view a note opens in when none was remembered for it, from "Default view for new
    /// tabs" and the editing mode.
    var initialNoteViewMode: NoteViewMode {
        defaultNoteView == .reading ? .reading : (defaultEditingMode == .livePreview ? .livePreview : .source)
    }
}

extension VaultSettingsChanges {
    /// A switch for an option that `app.json` can hold: it shows the vault's value, else the
    /// device's, and a change goes to the vault's file, or to the device when no vault is open.
    func binding(for workspace: WorkspaceModel, vaultOption: WritableKeyPath<ObsidianSettings, Bool?> & Sendable,
                 deviceOption: ReferenceWritableKeyPath<GraphitePreferences, Bool>) -> Binding<Bool> {
        Binding(get: { self.settings(of: workspace)[keyPath: vaultOption] ?? workspace.preferences[keyPath: deviceOption] }, set: { isOn in
            if workspace.store == nil {
                workspace.preferences[keyPath: deviceOption] = isOn
            } else {
                self.update(workspace) { settings in settings[keyPath: vaultOption] = isOn }
            }
        })
    }

    /// The view new notes open in, shown and changed the same way.
    func defaultNoteViewBinding(for workspace: WorkspaceModel) -> Binding<DefaultNoteView> {
        Binding(get: {
            self.settings(of: workspace).defaultViewMode.map { mode in mode == .preview ? DefaultNoteView.reading : .editing } ?? workspace.preferences.defaultNoteView
        }, set: { view in
            if workspace.store == nil {
                workspace.preferences.defaultNoteView = view
            } else {
                self.update(workspace) { settings in settings.defaultViewMode = view == .reading ? .preview : .source }
            }
        })
    }

    /// The editing mode, shown and changed the same way.
    func defaultEditingModeBinding(for workspace: WorkspaceModel) -> Binding<EditingMode> {
        Binding(get: {
            self.settings(of: workspace).usesLivePreview.map { usesLivePreview in usesLivePreview ? EditingMode.livePreview : .source } ?? workspace.preferences.defaultEditingMode
        }, set: { mode in
            if workspace.store == nil {
                workspace.preferences.defaultEditingMode = mode
            } else {
                self.update(workspace) { settings in settings.usesLivePreview = mode == .livePreview }
            }
        })
    }
}
