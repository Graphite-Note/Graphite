/**
 * File: NotionImporterPluginOffer.swift
 * -------------------------------------
 * Layer: UI
 * Description: Import from Notion's offer of the same importer as a community plugin: its release named with its size
 *              and source, and installed into the vault's plugins only on the person's yes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import SwiftUI
import GraphiteCore

/// Import from Notion's offer of the Notion Importer plugin (`graphite-notion-importer`, Graphite's own plugin, which
/// Browse lists too). Nothing is downloaded before the person says yes to a question naming the plugin, its version,
/// its size and where it comes from, and the release named is the one installed. Import from Notion stays either way:
/// it needs no WebAssembly, which Lockdown Mode turns off.
@MainActor @Observable
final class NotionImporterPluginOffer {
    enum State: Equatable {
        /// The offer's button.
        case offered
        /// The release is being read, before anything is asked.
        case reading
        /// The question before the download.
        case asking(Question)
        case installing
        /// What became of it: installed, already there, or why not.
        case finished(String)
    }

    /// What the question before the download names.
    struct Question: Equatable {
        let release: CommunityPluginInstaller.Release
        /// The bytes downloaded, nil when GitHub did not give them.
        let byteCount: Int?
        /// The plugin's version in the vault now, nil when it is not there.
        let installedVersion: String?
    }

    static let repository = "Graphite-Note/Importer"
    static let identifier = "graphite-notion-importer"

    private(set) var state: State = .offered
    private let installer: CommunityPluginInstaller
    /// The plugin's version in the vault now, nil when it is not there.
    private let installedVersion: @MainActor () async -> String?
    /// Reloads the vault's plugins after an install and says what became of the plugin.
    private let pluginsDidChange: @MainActor (CommunityPluginInstaller.Installation) async -> String

    init(installer: CommunityPluginInstaller, installedVersion: @escaping @MainActor () async -> String?,
         pluginsDidChange: @escaping @MainActor (CommunityPluginInstaller.Installation) async -> String) {
        self.installer = installer
        self.installedVersion = installedVersion
        self.pluginsDidChange = pluginsDidChange
    }

    /// Reads the release the plugin's repository names and asks about it, or says that the vault has it already.
    func ask() async {
        switch state {
        case .offered, .finished: break
        case .reading, .asking, .installing: return
        }
        state = .reading
        do {
            let release = try await installer.release(repository: Self.repository, expectedIdentifier: Self.identifier)
            let installed = await installedVersion()
            if installed == release.version {
                state = .finished(NotionImportWording.pluginIsInstalled(name: release.currentManifest.name, version: release.version))
                return
            }
            let byteCount = await installer.downloadSize(of: release)
            state = .asking(Question(release: release, byteCount: byteCount, installedVersion: installed))
        } catch {
            state = .finished(NotionImportWording.pluginReleaseUnreadable(because: error))
        }
    }

    /// The person's no: the offer is back as it was, and nothing was downloaded.
    func decline() {
        guard case .asking = state else { return }
        state = .offered
    }

    /// The person's yes: the release asked about is installed. The state is `installing` when this returns, so that an
    /// alert closing after its button sees the yes already given.
    @discardableResult
    func install() -> Task<Void, Never>? {
        guard case .asking(let question) = state else { return nil }
        state = .installing
        return Task { [installer, pluginsDidChange] in
            do {
                let installation = try await installer.install(question.release)
                self.state = .finished(await pluginsDidChange(installation))
            } catch {
                self.state = .finished(NotionImportWording.pluginNotInstalled(because: error))
            }
        }
    }
}

/// The offer in Import from Notion's sheet: its button, what it is doing, or what came of it, and the question before
/// the download.
struct NotionImporterPluginOfferSection: View {
    let offer: NotionImporterPluginOffer

    var body: some View {
        Section {
            switch offer.state {
            case .offered:
                Button("Get the Notion Importer Plugin…", systemImage: "puzzlepiece.extension") { Task { await offer.ask() } }
                    .frame(minHeight: 44)
            case .reading, .asking:
                ProgressView { Text("Reading the plugin's release…") }
            case .installing:
                ProgressView { Text("Downloading the plugin…") }
            case .finished(let outcome):
                Text(outcome)
                Button("Get the Notion Importer Plugin…", systemImage: "puzzlepiece.extension") { Task { await offer.ask() } }
                    .frame(minHeight: 44)
            }
        } header: {
            Text("As a Plugin")
        } footer: {
            Text(NotionImportWording.pluginOffer)
        }
        .alert(question.map(NotionImportWording.pluginQuestionTitle) ?? "", isPresented: Binding(get: { question != nil }, set: { _ in }),
               presenting: question) { _ in
            Button("Download") { offer.install() }
            Button("Cancel", role: .cancel) { offer.decline() }
        } message: { question in
            Text(NotionImportWording.pluginQuestion(question))
        }
    }

    private var question: NotionImporterPluginOffer.Question? {
        if case .asking(let question) = offer.state { question } else { nil }
    }
}
