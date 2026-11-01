/**
 * File: EditorSettingsPage.swift
 * ------------------------------
 * Layer: UI
 * Description: Settings > Editor: how notes open and look while they are written, and how typing behaves.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// Settings › Editor: how notes open and look while they are written, and how typing behaves.
struct EditorSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var preferences: GraphitePreferences
    let vaultSettingsChanges: VaultSettingsChanges

    private var vaultSettings: ObsidianSettings { vaultSettingsChanges.settings(of: workspace) }

    /// A setting stored in the vault's `.obsidian/app.json`.
    private func vaultSetting<Value>(_ keyPath: WritableKeyPath<ObsidianSettings, Value> & Sendable) -> Binding<Value> {
        Binding(get: { vaultSettings[keyPath: keyPath] }, set: { newValue in
            vaultSettingsChanges.update(workspace) { settings in settings[keyPath: keyPath] = newValue }
        })
    }

    /// An option `app.json` can hold, shown from the vault when it sets it and from this device otherwise.
    private func deviceOrVaultSetting(_ vaultOption: WritableKeyPath<ObsidianSettings, Bool?> & Sendable,
                                      device deviceOption: ReferenceWritableKeyPath<GraphitePreferences, Bool>) -> Binding<Bool> {
        workspace.binding(vaultOption: vaultOption, deviceOption: deviceOption, changes: vaultSettingsChanges)
    }

    private static var typingFooter: String {
        let pasting = " Pasting a web page or rich text writes it as Markdown. Shared with Obsidian in .obsidian/app.json."
        #if canImport(UIKit)
        return "Return continues a list, a task list, or a quote, and Tab indents it. Brackets and quotes are typed in pairs, and *, _, ~, =, ` or $ wrap "
            + "selected text." + pasting
        #else
        return "Indent and Outdent insert a tab, or this many spaces." + pasting
        #endif
    }

    var body: some View {
        Form {
            behaviorSection
            displaySection
            codeSection
            typingSection
        }
        .navigationTitle("Editor")
    }

    private var behaviorSection: some View {
        Section {
            Picker("Default View for New Notes", selection: workspace.defaultNoteViewBinding(changes: vaultSettingsChanges)) {
                ForEach(DefaultNoteView.allCases) { view in Text(view.title).tag(view) }
            }
            Picker("Default Editing Mode", selection: workspace.defaultEditingModeBinding(changes: vaultSettingsChanges)) {
                ForEach(EditingMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Picker("Remember View", selection: $preferences.noteViewMemory) {
                ForEach(NoteViewMemory.allCases) { memory in Text(memory.title).tag(memory) }
            }
        } header: {
            Text("Behavior")
        } footer: {
            Text("Live Preview hides Markdown syntax except where your cursor is and shows tables, math, properties, and embeds in place. Source "
                + "mode shows every character. Per Note opens each note in the view you left it in; Per Vault opens every note in the view you last "
                + "chose in this vault. The default view and editing mode are stored in the vault's .obsidian/app.json, as Obsidian does; Remember "
                + "View is kept on this device.")
                .formFooterAlignment()
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Readable Line Length", isOn: deviceOrVaultSetting(\.usesReadableLineLength, device: \.usesReadableLineLength))
            Toggle("Spellcheck", isOn: deviceOrVaultSetting(\.usesSpellChecking, device: \.usesSpellChecking))
            if workspace.store != nil {
                Toggle("Strict Line Breaks", isOn: vaultSetting(\.usesStrictLineBreaks))
            }
        } header: {
            Text("Display")
        } footer: {
            Text("With strict line breaks off, a single line break starts a new line when reading, as in Obsidian. Readable line length, spellcheck "
                + "and strict line breaks are stored in the vault's .obsidian/app.json, shared with Obsidian; before a vault sets one, and while no "
                + "vault is open, the choice made on this device applies.")
                .formFooterAlignment()
        }
    }

    private var codeSection: some View {
        Section {
            Picker("Code Theme", selection: $preferences.codeColorTheme) {
                ForEach(CodeColorTheme.allCases) { codeTheme in Text(codeTheme.title).tag(codeTheme) }
            }
            CodeThemePreview(codeTheme: preferences.codeColorTheme, noteTheme: workspace.noteTheme)
            Toggle("Format Code Blocks", isOn: $preferences.formatsCodeBlocks)
        } header: {
            Text("Code")
        } footer: {
            Text("The code theme and code formatting are kept on this device. Each code theme has a light and a dark version that follow the "
                + "appearance; Obsidian's follows the vault's theme. When you leave a code block you edited, its indentation and spacing are tidied "
                + "for its language. Undo puts it back.")
                .formFooterAlignment()
        }
    }

    @ViewBuilder private var typingSection: some View {
        if workspace.store != nil {
                Toggle("Strict Line Breaks", isOn: vaultSetting(\.usesStrictLineBreaks))
            }
        } header: {
            Text("Display")
        } footer: {
            Text("With strict line breaks off, a single line break starts a new line when reading, as in Obsidian. Readable line length, spellcheck "
                + "and strict line breaks are stored in the vault's .obsidian/app.json, shared with Obsidian; before a vault sets one, and while no "
                + "vault is open, the choice made on this device applies.")
                .formFooterAlignment()
        }
        Section {
            Picker("Code Theme", selection: $preferences.codeColorTheme) {
                ForEach(CodeColorTheme.allCases) { codeTheme in Text(codeTheme.title).tag(codeTheme) }
            }
            CodeThemePreview(codeTheme: preferences.codeColorTheme, noteTheme: workspace.noteTheme)
            Toggle("Format Code Blocks", isOn: $preferences.formatsCodeBlocks)
        } header: {
            Text("Code")
        } footer: {
            Text("The code theme and code formatting are kept on this device. Each code theme has a light and a dark version that follow the "
                + "appearance; Obsidian's follows the vault's theme. When you leave a code block you edited, its indentation and spacing are tidied "
                + "for its language. Undo puts it back.")
                .formFooterAlignment()
        }
        if workspace.store != nil {
            Section {
                // Only the iPad editor continues lists and pairs characters as you type;
                // the Mac editor has neither, so they would do nothing there.
                #if canImport(UIKit)
                Toggle("Smart Indent Lists", isOn: vaultSetting(\.continuesLists))
                Toggle("Auto Pair Brackets", isOn: vaultSetting(\.pairsBrackets))
                Toggle("Auto Pair Markdown Syntax", isOn: vaultSetting(\.pairsMarkdown))
                #endif
                Toggle("Indent Using Tabs", isOn: vaultSetting(\.indentsWithTabs))
                if !vaultSettings.indentsWithTabs {
                    Stepper("Tab indent size: \(vaultSettings.tabSize)", value: vaultSetting(\.tabSize), in: 1...8)
                }
                Toggle("Auto Convert HTML on Paste", isOn: vaultSetting(\.convertsPastedHTML))
            } header: {
                Text("Typing")
            } footer: {
                Text(Self.typingFooter)
                    .formFooterAlignment()
            }
        } else {
            SettingsNeedAVault(what: "typing settings")
        }
    }
}
