import SwiftUI
import GraphiteCore

/// Settings › Community plugins, laid out like Obsidian's: turning plugins on for the
/// vault, installing them, and each installed plugin with its switch, what it needs that
/// Graphite lacks, and its options.
struct CommunityPluginsSettingsPage: View {
    @Bindable var workspace: WorkspaceModel
    let showOptions: (String) -> Void
    @State private var isBrowsing = false
    @State private var repository = ""
    @State private var installationMessage: String?
    @State private var isInstalling = false
    @State private var pluginToRemove: InstalledCommunityPlugin?
    /// The plugins that would run, while the person is asked whether to turn plugins on.
    @State private var pluginsToConfirm: [InstalledCommunityPlugin]?

    private var host: CommunityPluginHost { workspace.communityPlugins }

    /// Turning plugins on runs the code of those the vault already enabled (a vault copied from
    /// Obsidian), so they are named first, as Obsidian asks before it leaves restricted mode.
    private func setTurnedOn(_ isTurnedOn: Bool) {
        Task {
            guard isTurnedOn else {
                await host.setTurnedOnForVault(false)
                return
            }
            await host.reloadInventory()
            let plugins = host.pluginsEnabledToRun
            if plugins.isEmpty { await host.setTurnedOnForVault(true) } else { pluginsToConfirm = plugins }
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Turn On Community Plugins", isOn: Binding(get: { host.isTurnedOnForVault }, set: setTurnedOn))
            } footer: {
                Text("Community plugins are made by other people, not by Graphite. A plugin runs code that can read and change every file in this vault and reach the internet. Turn on only plugins you trust. They are the same plugins Obsidian uses, and they keep their settings in the vault's .obsidian folder.")
                    .formFooterAlignment()
            }
            if host.isTurnedOnForVault {
                installSection
                installedSection
            }
        }
        .navigationTitle("Community Plugins")
        .task { await host.reloadInventory(readsPluginCode: true) }
        .confirmationDialog("Turn on community plugins?", isPresented: Binding(get: { pluginsToConfirm != nil }, set: { isPresented in if !isPresented { pluginsToConfirm = nil } }),
                            titleVisibility: .visible, presenting: pluginsToConfirm) { _ in
            Button("Turn On and Run Them") { Task { await host.setTurnedOnForVault(true) } }
            Button("Cancel", role: .cancel) {}
        } message: { plugins in
            Text(CommunityPluginTurningOn.question(naming: plugins.map(\.manifest.name)))
        }
        .sheet(isPresented: $isBrowsing) {
            CommunityPluginBrowser(workspace: workspace)
                .tint(workspace.preferences.accentColor)
        }
        .confirmationDialog("Remove plugin?", isPresented: Binding(get: { pluginToRemove != nil }, set: { isPresented in if !isPresented { pluginToRemove = nil } }),
                            presenting: pluginToRemove) { plugin in
            Button("Remove “\(plugin.manifest.name)”", role: .destructive) { Task { await host.uninstall(plugin) } }
        } message: { plugin in
            Text("Its folder, \(plugin.folder.rawValue), is removed the way this vault deletes files. Its settings go with it.")
        }
    }

    private var installSection: some View {
        Section {
            Button("Browse Community Plugins…", systemImage: "square.grid.2x2") { isBrowsing = true }
            HStack {
                TextField("GitHub repository, owner/name", text: $repository)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Install") { Task { await installFromRepository() } }
                    .disabled(isInstalling || !CommunityPluginInstaller.isUsableRepository(repository.trimmingCharacters(in: .whitespaces)))
            }
            if isInstalling { ProgressView() }
            if let installationMessage { Text(installationMessage).font(.callout).foregroundStyle(.secondary) }
            Button("Reload Plugins", systemImage: "arrow.clockwise") { Task { await host.restartPlugins() } }
        } header: {
            Text("Install")
        } footer: {
            Text("Plugins come from Obsidian's community directory or a GitHub repository's releases. A plugin copied into .obsidian/plugins by Obsidian or another app appears here too.")
                .formFooterAlignment()
        }
    }

    private var installedSection: some View {
        Section {
            if host.inventory.plugins.isEmpty {
                Text("No plugins are installed in this vault.").foregroundStyle(.secondary)
            }
            ForEach(host.inventory.plugins) { plugin in
                InstalledCommunityPluginRow(host: host, plugin: plugin, showOptions: { showOptions(plugin.id) }, remove: { pluginToRemove = plugin })
            }
            ForEach(host.inventory.unreadableFolders) { folder in
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.folder.name)
                    Text(folder.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Installed Plugins")
        }
    }

    private func installFromRepository() async {
        guard let store = workspace.store else { return }
        isInstalling = true
        defer { isInstalling = false }
        do {
            let installation = try await CommunityPluginInstaller(store: store).install(repository: repository.trimmingCharacters(in: .whitespaces), expectedIdentifier: nil)
            installationMessage = "Installed \(installation.manifest.name) \(installation.manifest.version)." + (installation.isOlderReleaseForCompatibility ? " This is an older release: the newest needs a newer plugin API than Graphite provides." : "") + " Turn it on below."
            repository = ""
            await host.reloadInventory()
        } catch {
            installationMessage = error.localizedDescription
        }
    }
}

/// One installed plugin: its switch, its state, and what it reached that Graphite lacks.
private struct InstalledCommunityPluginRow: View {
    let host: CommunityPluginHost
    let plugin: InstalledCommunityPlugin
    let showOptions: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { host.enabledList.isEnabled(plugin.id) }, set: { isEnabled in Task { await host.setEnabled(plugin, isEnabled) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.manifest.name)
                    Text([plugin.manifest.version.isEmpty ? nil : "Version \(plugin.manifest.version)", plugin.manifest.author.isEmpty ? nil : "by \(plugin.manifest.author)"]
                        .compactMap { part in part }.joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!plugin.compatibility.canLoad && !host.enabledList.isEnabled(plugin.id))
            if !plugin.manifest.summary.isEmpty {
                Text(plugin.manifest.summary).font(.callout).foregroundStyle(.secondary)
            }
            if let status = statusText {
                Label(status, systemImage: statusSymbol).font(.caption).foregroundStyle(statusColor)
            }
            if !desktopModules.isEmpty {
                Text("Parts that use " + desktopModules.joined(separator: ", ") + " work only in Obsidian's desktop app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !limitations.isEmpty {
                Text("Not available in Graphite: " + limitations.joined(separator: "; ") + ".")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(host.runtimeProblems[plugin.id] ?? [], id: \.self) { problem in
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if host.pluginsWithSettings.contains(plugin.id) {
                    Button("Options", systemImage: "gearshape", action: showOptions)
                }
                Spacer()
                Button("Remove", systemImage: "trash", role: .destructive, action: remove)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private var state: CommunityPluginLoadState { host.loadStates[plugin.id] ?? .notStarted }

    private var statusText: String? {
        switch state {
        case .notStarted: host.enabledList.isEnabled(plugin.id) ? "Starts when community plugins run." : nil
        case .loading: "Starting…"
        case .loaded: "Running"
        case .notLoadable(let reason): reason
        case .failed(let reason): "Did not start: " + reason
        }
    }

    private var statusSymbol: String {
        switch state {
        case .loaded: "checkmark.circle"
        case .failed, .notLoadable: "exclamationmark.triangle"
        default: "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch state {
        case .loaded: .green
        case .failed, .notLoadable: .orange
        default: .secondary
        }
    }

    /// The Node.js and Electron modules the plugin's code mentions, once each. Plugins built for
    /// desktop and mobile load without them; only what uses them stops working.
    private var desktopModules: [String] {
        var names: [String] = []
        for module in plugin.compatibility.missingModules where module.kind == .desktopOnly {
            let name = module.name.hasPrefix("node:") ? String(module.name.dropFirst("node:".count)) : module.name
            if !names.contains(name) { names.append(name) }
        }
        return names.map { name in "“\(name)”" }
    }

    /// What the plugin's code asks for, and what it reached while running, that Graphite lacks.
    private var limitations: [String] {
        let modules = plugin.compatibility.missingModules.filter { module in module.kind != .desktopOnly }.map { module in "“\(module.name)”" }
        let reachedModules = Set(plugin.compatibility.missingModules.map { module in "Module “\(module.name)”" })
        return modules + (host.unsupportedFeatures[plugin.id] ?? []).filter { feature in !reachedModules.contains(feature) }
    }
}

/// A plugin's own settings tab, drawn by the plugin on the plugin panel, inline here.
struct CommunityPluginOptionsPage: View {
    let host: CommunityPluginHost
    let pluginIdentifier: String
    @State private var hasSettings = true

    var body: some View {
        Group {
            if hasSettings {
                CommunityPluginWebViewContainer(host: host)
            } else {
                ContentUnavailableView("No Options", systemImage: "puzzlepiece.extension", description: Text("This plugin has no settings, or it is not running."))
            }
        }
        .navigationTitle(host.pluginName(of: pluginIdentifier) ?? pluginIdentifier)
        .task(id: pluginIdentifier) {
            host.isPanelShownInline = true
            hasSettings = await host.showSettings(of: pluginIdentifier)
        }
        .onDisappear {
            host.isPanelShownInline = false
            host.panelDidClose()
        }
    }
}

/// Obsidian's community directory, searchable, with installation.
struct CommunityPluginBrowser: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [CommunityPluginDirectoryEntry] = []
    @State private var query = ""
    @State private var loadingProblem: String?
    @State private var isLoading = true
    @State private var installingIdentifier: String?
    @State private var outcomes: [String: String] = [:]

    private var host: CommunityPluginHost { workspace.communityPlugins }

    private var matchingEntries: [CommunityPluginDirectoryEntry] {
        Array(CommunityPluginDirectoryEntry.search(entries, for: query).prefix(300))
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading { ProgressView() }
                if let loadingProblem { Text(loadingProblem).foregroundStyle(.secondary) }
                ForEach(matchingEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).font(.headline)
                                Text("by \(entry.author)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            installButton(for: entry)
                        }
                        Text(entry.description).font(.callout).foregroundStyle(.secondary)
                        if let outcome = outcomes[entry.id] { Text(outcome).font(.caption) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .searchable(text: $query, prompt: "Search community plugins")
            .navigationTitle("Community Plugins")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await loadDirectory() }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    @ViewBuilder private func installButton(for entry: CommunityPluginDirectoryEntry) -> some View {
        let isInstalled = host.inventory.plugins.contains { plugin in plugin.id == entry.id }
        if installingIdentifier == entry.id {
            ProgressView()
        } else {
            Button(isInstalled ? "Update" : "Install") { Task { await install(entry) } }
                .buttonStyle(.bordered)
                .disabled(installingIdentifier != nil)
        }
    }

    private func loadDirectory() async {
        guard let store = workspace.store else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await CommunityPluginInstaller(store: store).directory()
            loadingProblem = nil
        } catch {
            loadingProblem = "Obsidian's plugin directory could not be loaded. " + error.localizedDescription
        }
    }

    private func install(_ entry: CommunityPluginDirectoryEntry) async {
        guard let store = workspace.store else { return }
        installingIdentifier = entry.id
        defer { installingIdentifier = nil }
        do {
            let installation = try await CommunityPluginInstaller(store: store).install(repository: entry.repo, expectedIdentifier: entry.id)
            await host.reloadInventory()
            let compatibility = host.inventory.plugins.first { plugin in plugin.id == entry.id }?.compatibility
            var outcome = "Installed version \(installation.manifest.version)."
            if installation.isOlderReleaseForCompatibility { outcome += " An older release, because the newest needs a newer plugin API than Graphite provides." }
            outcomes[entry.id] = CommunityPluginTurningOn.installationOutcome(outcome, compatibility: compatibility, isTurnedOn: host.enabledList.isEnabled(entry.id), isRunning: host.loadStates[entry.id] == .loaded)
        } catch {
            outcomes[entry.id] = error.localizedDescription
        }
    }
}

/// What Settings says when a plugin starts to run or changes.
@MainActor enum CommunityPluginTurningOn {
    static func question(naming pluginNames: [String]) -> String {
        "These plugins, made by other people, will run now, and can read and change every file in this vault and reach the internet: " + pluginNames.joined(separator: ", ") + "."
    }

    /// After installing or updating: a plugin already running keeps its old code until plugins reload.
    static func installationOutcome(_ installed: String, compatibility: CommunityPluginCompatibility?, isTurnedOn: Bool, isRunning: Bool) -> String {
        if let compatibility, !compatibility.canLoad { return installed + " " + CommunityPluginHost.describe(compatibility) }
        if isRunning { return installed + " The old version keeps running until you tap Reload Plugins." }
        return installed + (isTurnedOn ? " It runs the next time plugins start." : " Turn it on in Community Plugins.")
    }
}
