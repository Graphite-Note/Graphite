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

extension WorkspaceModel {
    /// A switch for an option that `app.json` can hold: it shows the vault's value, else the
    /// device's, and a change goes to the vault's file, or to the device when no vault is open.
    func binding(vaultOption: WritableKeyPath<ObsidianSettings, Bool?> & Sendable, deviceOption: ReferenceWritableKeyPath<GraphitePreferences, Bool>,
                 changes: VaultSettingsChanges) -> Binding<Bool> {
        Binding(get: { changes.settings(of: self)[keyPath: vaultOption] ?? self.preferences[keyPath: deviceOption] }, set: { isOn in
            if self.store == nil {
                self.preferences[keyPath: deviceOption] = isOn
            } else {
                changes.update(self) { settings in settings[keyPath: vaultOption] = isOn }
            }
        })
    }

    /// The view new notes open in, shown and changed the same way.
    func defaultNoteViewBinding(changes: VaultSettingsChanges) -> Binding<DefaultNoteView> {
        Binding(get: {
            let vaultMode = changes.settings(of: self).defaultViewMode
            return vaultMode.map { mode in mode == .preview ? DefaultNoteView.reading : .editing } ?? self.preferences.defaultNoteView
        }, set: { view in
            if self.store == nil {
                self.preferences.defaultNoteView = view
            } else {
                changes.update(self) { settings in settings.defaultViewMode = view == .reading ? .preview : .source }
            }
        })
    }

    /// The editing mode, shown and changed the same way.
    func defaultEditingModeBinding(changes: VaultSettingsChanges) -> Binding<EditingMode> {
        Binding(get: {
            let usesLivePreview = changes.settings(of: self).usesLivePreview
            return usesLivePreview.map { isOn in isOn ? EditingMode.livePreview : .source } ?? self.preferences.defaultEditingMode
        }, set: { mode in
            if self.store == nil {
                self.preferences.defaultEditingMode = mode
            } else {
                changes.update(self) { settings in settings.usesLivePreview = mode == .livePreview }
            }
        })
    }
}
