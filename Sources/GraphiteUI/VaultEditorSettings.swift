/**
 * File: VaultEditorSettings.swift
 * -------------------------------
 * Layer: UI
 * Description: The editor options Obsidian keeps in the vault's app.json, read from the vault when it sets them and from this device otherwise,
 *              and the note's line width switch.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 05/11/2026
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

/// A note's two line widths: Obsidian's "Readable line length" on and off. Narrow holds the
/// title, the properties, the text and every block to the readable column; wide gives them
/// all the editor's width inside its margins (HUNT-324).
enum NoteLineWidth: Hashable, CaseIterable {
    case narrow
    case wide

    var title: String {
        switch self {
        case .narrow: "Narrow"
        case .wide: "Wide"
        }
    }
}

extension WorkspaceModel {
    /// The note's line width, kept where Settings › Editor › Readable Line Length keeps it:
    /// the vault's `app.json` when a vault is open, so Obsidian shows the same choice.
    func lineWidthBinding(changes: VaultSettingsChanges) -> Binding<NoteLineWidth> {
        let usesReadableLineLength = binding(vaultOption: \.usesReadableLineLength, deviceOption: \.usesReadableLineLength, changes: changes)
        return Binding(get: { usesReadableLineLength.wrappedValue ? .narrow : .wide },
                       set: { lineWidth in usesReadableLineLength.wrappedValue = lineWidth == .narrow })
    }
}

/// "Line Width: Narrow / Wide", in the note's Format (Aa) menu while it is written and in its
/// More menu while it is read: the same switch as Readable Line Length in Settings.
struct NoteLineWidthPicker: View {
    /// The switch over the changes this picker keeps: `WorkspaceModel.lineWidthBinding(changes:)`.
    let lineWidth: @MainActor (VaultSettingsChanges) -> Binding<NoteLineWidth>
    @State private var vaultSettingsChanges = VaultSettingsChanges()

    var body: some View {
        Picker("Line Width", systemImage: "arrow.left.and.right.text.vertical", selection: lineWidth(vaultSettingsChanges)) {
            ForEach(NoteLineWidth.allCases, id: \.self) { lineWidth in Text(lineWidth.title).tag(lineWidth) }
        }
    }
}
