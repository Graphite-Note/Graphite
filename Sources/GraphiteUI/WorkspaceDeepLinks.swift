/**
 * File: WorkspaceDeepLinks.swift
 * ------------------------------
 * Layer: UI
 * Description: `graphite://` links from other apps, with Obsidian's actions (see `VaultURI`).
 *
 * Authors: Bahey Shalash
 * Version: 0.10
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

/// `graphite://` links from other apps, with Obsidian's actions (see `VaultURI`).
extension WorkspaceModel {
    func handle(_ url: URL) async {
        guard let link = VaultURI(url: url) else {
            errorMessage = "Graphite can't open this link: \(url.absoluteString)"
            return
        }
        if case .open(_, let path?) = link.action {
            if let vaultPath = await vaultPathShowingFileSystemPath(path) { await open(vaultPath) }
            return
        }
        // `new?path=`: the note's full path decides the vault and the note, as for `open`.
        if case .new(_, _, let path?, let content, let opensNote, let mode) = link.action {
            if let vaultPath = await vaultPathShowingFileSystemPath(path) {
                await createNoteFromLink(name: nil, file: vaultPath.rawValue, content: content, opensNote: opensNote, mode: mode)
            }
            return
        }
        if let vaultName = link.vault, !isCurrentVault(named: vaultName), await !openVaultOfLink(named: vaultName) { return }
        guard store != nil else {
            errorMessage = "Open a vault first, then try the link again."
            return
        }
        switch link.action {
        case .open(let file, _):
            if let file { await openLinkedFile(file) }
        case .search(let query):
            searchQuery = query
            searchFocusRequest += 1
        case .new(let name, let file, _, let content, let opensNote, let mode):
            await createNoteFromLink(name: name, file: file, content: content, opensNote: opensNote, mode: mode)
        case .daily:
            await openDailyNote()
        case .read(let file):
            let openedPath = await openLinkedFile(file)
            guard preferences.isEnabled(.readAloud) else {
                errorMessage = "Read Aloud is turned off. Turn it on in Settings › Core Plugins."
                return
            }
            // Only the file the link named is read, never the note that happened to be open.
            guard let openedPath else { return }
            await startReadingAloud(openedPath, resumeLocation: nil)
        case .plugin(let action, let parameters):
            if !(await communityPlugins.openPluginLink(action: action, parameters: parameters)) {
                errorMessage = "No community plugin in this vault opens “\(action)” links."
            }
        }
    }

    /// Obsidian's "Copy Obsidian URL": a link that opens this file from any app.
    /// The link names the vault by its folder's name, as Obsidian's do, unless another known
    /// vault has the same name; then it names the vault by its identifier, which only this
    /// vault has.
    func openingLink(to path: VaultPath) -> String {
        let sharesNameWithAnotherVault = vaultLibrary.vaults.contains { vault in vault.name == title && vault.id != currentVaultIdentifier }
        let vaultReference = sharesNameWithAnotherVault ? (currentVaultIdentifier?.uuidString ?? title) : title
        return VaultURI.openingLink(to: path, inVaultNamed: vaultReference)
    }

    // MARK: Private

    /// Whether a link's vault is the one that is open: its identifier, or its name, which the
    /// open vault answers to before another vault of the same name.
    func isCurrentVault(named name: String) -> Bool {
        guard let currentVaultIdentifier else { return false }
        if currentVaultIdentifier.uuidString.caseInsensitiveCompare(name) == .orderedSame || title == name { return true }
        return knownVault(named: name)?.id == currentVaultIdentifier
    }

    /// The vault a link names: by identifier, then by its folder's name, then ignoring capitals.
    private func knownVault(named name: String) -> KnownVault? {
        let vaults = vaultLibrary.vaults
        return vaults.first { vault in vault.id.uuidString.caseInsensitiveCompare(name) == .orderedSame }
            ?? vaults.first { vault in vault.name == name }
            ?? vaults.first { vault in vault.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Opens a note given as `file=`, resolved as a link from the vault's top: a name, a
    /// path, with a heading or block. It is never created, unlike following a link. Returns
    /// the file the link opened, now shown in a tab on either side, or nil when it opened nothing.
    @discardableResult
    private func openLinkedFile(_ file: String) async -> VaultPath? {
        guard let index, let topLevelSource = try? VaultPath("Link.md") else { return nil }
        do {
            var matches = try await index.resolve(file, from: topLevelSource)
            // A link that starts Graphite may arrive before the vault is read.
            var waited = 0
            while matches.isEmpty && !hasCompletedIndexScan && waited < 40 {
                try await Task.sleep(for: .milliseconds(250))
                waited += 1
                matches = try await index.resolve(file, from: topLevelSource)
            }
            guard !matches.isEmpty else {
                errorMessage = "No file in “\(title)” matches “\(WikiLinkResolver.pathPart(file))”."
                return nil
            }
            let linkedPath = await resolveLink(file, from: topLevelSource)
            await follow(file, from: topLevelSource)
            // A file already open on the other side is shown there without taking focus.
            if let linkedPath, layout.tabID(showing: linkedPath) != nil { return linkedPath }
        } catch is CancellationError {
        } catch { errorMessage = error.localizedDescription }
        return nil
    }

    /// `open?path=` and `new?path=`: the vault path of a full file system path, inside the
    /// vault that is open or another known vault, which is opened first. Nil, with the reason
    /// shown, when no vault holds it or its vault cannot be opened.
    private func vaultPathShowingFileSystemPath(_ fileSystemPath: String) async -> VaultPath? {
        let standardized = URL(fileURLWithPath: fileSystemPath).standardizedFileURL.resolvingSymlinksInPath().path
        func vaultPath(inside root: String) -> VaultPath? {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            guard standardized.hasPrefix(prefix) else { return nil }
            return try? VaultPath(String(standardized.dropFirst(prefix.count)))
        }
        if let root = folderAccess?.root.standardizedFileURL.resolvingSymlinksInPath().path, let path = vaultPath(inside: root) { return path }
        guard let vault = vaultLibrary.vaults.first(where: { vault in vaultPath(inside: vault.lastKnownPath) != nil }),
              let path = vaultPath(inside: vault.lastKnownPath) else {
            errorMessage = "“\(fileSystemPath)” is not in a vault Graphite knows."
            return nil
        }
        do {
            try await openVault(vault)
            guard currentVaultIdentifier == vault.id else {
                reportLinkNotFollowed(into: vault)
                return nil
            }
            return path
        } catch {
            errorMessage = "Graphite couldn't open “\(vault.name)”. " + error.localizedDescription
            return nil
        }
    }

    /// Opens the vault a link names. False, with the reason shown, when it is not open afterwards.
    private func openVaultOfLink(named vaultName: String) async -> Bool {
        guard let vault = knownVault(named: vaultName) else {
            errorMessage = "No vault named “\(vaultName)” is in Graphite's vault list. Open its folder once from the vault list, then try the link again."
            return false
        }
        do { try await openVault(vault) } catch {
            errorMessage = "Graphite couldn't open “\(vault.name)”. " + error.localizedDescription
            return false
        }
        guard currentVaultIdentifier == vault.id else {
            reportLinkNotFollowed(into: vault)
            return false
        }
        return true
    }

    /// A newer choice of vault replaced the switch a link waited for: the link acts in nothing,
    /// above all not in the vault that happens to be open, and what it carried is not lost silently.
    private func reportLinkNotFollowed(into vault: KnownVault) {
        errorMessage = "Another vault was chosen while a link waited for “\(vault.name)” to open, so the link was not followed. Try it again."
    }

    private func createNoteFromLink(name: String?, file: String?, content: String, opensNote: Bool, mode: VaultURI.NewNoteMode) async {
        guard let store else { return }
        do {
            var path: VaultPath
            if let file {
                path = try VaultPath(file.lowercased().hasSuffix(".md") ? file : file + ".md")
                if let problem = FileNameRules.problem(with: path.stem, isNote: true) { throw GraphiteError.unavailable(problem) }
            } else {
                let noteName = name ?? "Untitled"
                if let problem = FileNameRules.problem(with: noteName, isNote: true) { throw GraphiteError.unavailable(problem) }
                path = try newFileDirectory(nil).appending(noteName + ".md")
            }
            if try await store.fileExists(path) {
                switch mode {
                case .unique:
                    path = try await store.uniquePath(directory: path.parent, stem: path.stem, extension: "md")
                    _ = try await store.save(Data(content.utf8), at: path, expecting: .absent)
                    await showInListings(path)
                case .append, .overwrite:
                    try await replaceText(of: path, keepingCopy: mode == .overwrite) { existing in
                        mode == .append ? VaultURI.appending(content, to: existing) : content
                    }
                }
            } else {
                try await store.createDirectory(path.parent)
                _ = try await store.save(Data(content.utf8), at: path, expecting: .absent)
                await showInListings(path)
            }
            refreshIndex(for: [path])
            if opensNote { await open(path) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Changes a note's text through its editor when it is open, so it can be undone, and
    /// otherwise in the file if it has not changed since it was read.
    private func replaceText(of path: VaultPath, keepingCopy: Bool, _ change: (String) -> String) async throws {
        guard let store else { return }
        if let session = openMarkdownSession(at: path) {
            if keepingCopy, let fileRecovery { _ = try? fileRecovery.takeSnapshot(of: session.text, for: path, minimumInterval: 0) }
            let changed = change(session.text)
            session.apply(MarkdownTextEdit(range: NSRange(location: 0, length: (session.text as NSString).length), replacement: changed,
                                           selectionAfter: NSRange(location: (changed as NSString).length, length: 0)))
            if !session.isEditorAttached { try await session.save() }
            return
        }
        let snapshot = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
        guard let existing = String(data: snapshot.data, encoding: .utf8) else { throw GraphiteError.invalidFile("“\(path.name)” is not UTF-8 text.") }
        if keepingCopy, let fileRecovery { _ = try? fileRecovery.takeSnapshot(of: existing, for: path, minimumInterval: 0) }
        _ = try await store.save(Data(change(existing).utf8), at: path, expecting: .revision(snapshot.revision))
    }
}
