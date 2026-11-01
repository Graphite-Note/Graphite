/**
 * File: ThemeSettings.swift
 * -------------------------
 * Layer: UI
 * Description: Settings > Appearance > Obsidian Theme and CSS Snippets, and the page that chooses and installs themes.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.5
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// Settings › Appearance › Obsidian Theme and CSS Snippets: Obsidian's theme and snippet
/// settings, stored in the vault's `.obsidian/appearance.json`. They style notes and community
/// plugins' panels; Graphite's buttons, menus and Settings keep their look.
struct ThemeSettingsSection: View {
    @Bindable var workspace: WorkspaceModel
    @State private var snippets: [ObsidianSnippet] = []

    private var appearance: ObsidianAppearance { workspace.vaultAppearance }

    var body: some View {
        Section {
            NavigationLink {
                ThemeChoicePage(workspace: workspace)
            } label: {
                LabeledContent("Theme", value: appearance.cssTheme.isEmpty ? "Default" : appearance.cssTheme)
            }
            if !appearance.cssTheme.isEmpty || !appearance.enabledCssSnippets.isEmpty {
                Toggle(isOn: Binding(get: { workspace.preferences.usesVaultTheme }, set: { isOn in workspace.preferences.usesVaultTheme = isOn })) {
                    Text("Use the Vault's Obsidian Theme")
                    Text("Notes take the colors, headings, callouts and spacing of the theme and the snippets turned on below. Turn off to keep Graphite's look on this device.")
                }
            }
        } header: {
            Text("Obsidian Theme")
        } footer: {
            Text("Saved in the vault, so Obsidian uses the same theme. Buttons, menus and Settings keep Graphite's look.")
                .formFooterAlignment()
        }
        .task(id: "\(workspace.directoryVersion)-\(workspace.styleFilesVersion)-\(appearance.cssTheme)") { await reload() }
        if !snippets.isEmpty {
            Section {
                ForEach(snippets, id: \.name) { snippet in snippetToggle(snippet) }
            } header: {
                Text("CSS Snippets")
            } footer: {
                Text(snippetsFooter)
                    .formFooterAlignment()
            }
        }
    }

    private var snippetsFooter: String {
        let explanation = "Style files in the vault's .obsidian/snippets folder, each changing how part of your notes looks. The line under a name is the comment at the top of its file. This is Obsidian's list of CSS snippets: turning one on here turns it on in Obsidian too."
        return workspace.preferences.usesVaultTheme ? explanation : explanation + " Notes show them only while Use the Vault's Obsidian Theme is on."
    }

    private func snippetToggle(_ snippet: ObsidianSnippet) -> some View {
        Toggle(isOn: Binding(get: { appearance.enabledCssSnippets.contains(snippet.name) }, set: { isOn in
            workspace.updateVaultAppearance { appearance in
                appearance.enabledCssSnippets.removeAll { name in name == snippet.name }
                if isOn { appearance.enabledCssSnippets.append(snippet.name) }
            }
        })) {
            Text(snippet.name)
            Text(snippet.description ?? "Its file has no comment at the top saying what it does.")
        }
    }

    private func reload() async {
        guard let store = workspace.store else { return }
        snippets = await store.snippets()
    }
}

/// Obsidian's list of community themes as last loaded, for as long as the app runs, so the
/// page shows it at once each time it opens instead of downloading it again.
@MainActor
final class ThemeDirectoryCache {
    var entries: [ObsidianThemeDirectoryEntry] = []
}

/// The installed themes with Default first, and Obsidian's community themes to install.
struct ThemeChoicePage: View {
    @Bindable var workspace: WorkspaceModel
    @State private var installedThemes: [String] = []
    @State private var directory: [ObsidianThemeDirectoryEntry] = []
    @State private var themePendingDeletion: String?
    @State private var searchText = ""
    @State private var isLoadingDirectory = false
    @State private var installingTheme: String?
    @State private var directoryError: String?

    private var chosenTheme: String { workspace.vaultAppearance.cssTheme }

    var body: some View {
        List {
            installedThemesSection
            communityThemesSection
        }
        .searchable(text: $searchText, prompt: "Search Themes")
        .navigationTitle("Theme")
        .task { await reloadInstalled(); await loadDirectory() }
        .refreshable { await loadDirectory(reloading: true) }
        .confirmationDialog(themePendingDeletion.map { themeName in "Delete “\(themeName)”?" } ?? "",
                            isPresented: Binding(get: { themePendingDeletion != nil }, set: { isPresented in if !isPresented { themePendingDeletion = nil } }),
                            titleVisibility: .visible, presenting: themePendingDeletion) { themeName in
            Button("Delete Theme", role: .destructive) { Task { await delete(themeName) } }
            Button("Cancel", role: .cancel) {}
        } message: { themeName in
            Text(chosenTheme == themeName
                 ? "Its folder is removed from this vault the way the vault deletes files, and notes go back to the default look. Obsidian loses the theme too."
                 : "Its folder is removed from this vault the way the vault deletes files. Obsidian loses the theme too.")
        }
    }

    private var installedThemesSection: some View {
        Section {
            themeRow("Default", isChosen: chosenTheme.isEmpty) { choose("") }
            ForEach(installedThemes, id: \.self) { themeName in
                themeRow(themeName, isChosen: chosenTheme == themeName) { choose(themeName) }
                    .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { themePendingDeletion = themeName } }
                    .contextMenu { Button("Delete Theme…", systemImage: "trash", role: .destructive) { themePendingDeletion = themeName } }
            }
        } header: {
            Text("Installed Themes")
        } footer: {
            Text("A theme styles notes and community plugins' panels, and Style Settings and the theme's own settings plugin can change it. Buttons, menus and Settings keep Graphite's look.")
                .formFooterAlignment()
        }
    }

    private var communityThemesSection: some View {
        Section("Community Themes") {
            if isLoadingDirectory && directory.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let directoryError {
                Text(directoryError).foregroundStyle(.secondary)
                Button("Try Again") { Task { await loadDirectory() } }
            } else {
                ForEach(ObsidianThemeDirectoryEntry.search(directory, for: searchText).prefix(200)) { entry in
                    directoryRow(entry)
                }
            }
        }
    }

    private func themeRow(_ title: String, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                if isChosen { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func directoryRow(_ entry: ObsidianThemeDirectoryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(entry.modes.isEmpty ? "By \(entry.author)" : "By \(entry.author) · \(entry.modes.joined(separator: " and "))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if installingTheme == entry.name {
                ProgressView()
            } else if installedThemes.contains(entry.name) {
                Button(chosenTheme == entry.name ? "In Use" : "Use") { choose(entry.name) }
                    .buttonStyle(.bordered)
                    .disabled(chosenTheme == entry.name)
            } else {
                // One quiet button per row; a column of filled buttons would compete with the list.
                Button("Install and Use") { Task { await install(entry) } }
                    .buttonStyle(.bordered)
                    .disabled(installingTheme != nil)
            }
        }
        .frame(minHeight: 44)
    }

    private func choose(_ themeName: String) {
        workspace.updateVaultAppearance { appearance in appearance.cssTheme = themeName }
    }

    private func reloadInstalled() async {
        guard let store = workspace.store else { return }
        installedThemes = await store.installedThemeNames()
    }

    /// Obsidian's list of themes: the one loaded earlier in this run, else downloaded now.
    /// `reloading` downloads it again, as pulling the page down asks.
    private func loadDirectory(reloading: Bool = false) async {
        guard let store = workspace.store else { return }
        let cache = workspace.processServices.themeDirectoryCache
        if !reloading {
            if !directory.isEmpty { return }
            if !cache.entries.isEmpty { directory = cache.entries; return }
        }
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }
        do {
            directory = try await ObsidianThemeInstaller(store: store).directory()
            cache.entries = directory
        } catch { directoryError = "Obsidian's list of themes could not be loaded. " + error.localizedDescription }
    }

    private func delete(_ themeName: String) async {
        do {
            try await workspace.deleteInstalledTheme(named: themeName)
            await reloadInstalled()
        } catch {
            workspace.errorMessage = "“\(themeName)” could not be deleted. " + ((error as? GraphiteError)?.errorDescription ?? "Check that the vault's files can be changed.")
        }
    }

    private func install(_ entry: ObsidianThemeDirectoryEntry) async {
        guard let store = workspace.store else { return }
        installingTheme = entry.name
        defer { installingTheme = nil }
        do {
            try await ObsidianThemeInstaller(store: store).install(entry)
            await reloadInstalled()
            choose(entry.name)
            // The theme's file is new; the page reads it even when the choice was already this theme.
            workspace.communityPlugins.vaultStylesDidChange()
        } catch {
            workspace.errorMessage = "“\(entry.name)” could not be installed. " + error.localizedDescription
        }
    }
}

extension WorkspaceModel {
    /// Removes an installed theme's folder the way the vault deletes files. A theme in use is
    /// switched off first, as Obsidian does, so the vault is never left naming a theme it lacks.
    func deleteInstalledTheme(named themeName: String) async throws {
        guard let store else { return }
        let folder = try VaultPath(ObsidianStyleFiles.themesFolderPath).appending(themeName)
        if vaultAppearance.cssTheme == themeName {
            updateVaultAppearance { appearance in appearance.cssTheme = "" }
            await saveVaultAppearanceNow()
        }
        _ = try await store.delete(folder, method: vaultSettings.deletionMethod)
        communityPlugins.vaultStylesDidChange()
    }
}
