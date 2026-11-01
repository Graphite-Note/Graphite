import Foundation
import GraphiteCore
import GraphiteIndex

/// Keeping the file lists up to date: a change touches the folder it names and no other.
///
/// Listing a root of 24,712 files reads each file's metadata and sorts them, about 360,000 name
/// comparisons; so a change to a named file reads that one file and places it in the listing
/// already sorted. The root is listed in full only when a vault opens, when Graphite's own
/// command may have moved anything, and when another app changed what cannot be named.
extension WorkspaceModel {
    /// How long a window can be away before coming back lists the root whatever its date says:
    /// the date moves when a name is added or removed, not when a file is edited, and a sort by
    /// date reads those too.
    static let awayTimeBeforeListingAgain = Duration.seconds(300)

    /// Lists the root, and has every expanded folder list itself: for a change of Graphite's
    /// own that may have moved anything.
    func refreshDirectory() async {
        await listRoot()
        directoryVersion += 1
    }

    /// Lists the root off the main actor and adopts the result when it differs. A listing asked
    /// for later wins, whichever ends first.
    func listRoot() async {
        guard let store else { return }
        rootListingNumber += 1
        let listingNumber = rootListingNumber
        let listing = Task { await readRootListing(from: store, listingNumber: listingNumber) }
        rootListingInFlight = listing
        await listing.value
        if listingNumber == rootListingNumber { rootListingInFlight = nil }
    }

    private func readRootListing(from store: VaultStore, listingNumber: Int) async {
        let sortOrder = vaultSettings.fileSortOrder
        do {
            let rootDate = await store.listingDate(of: .root)
            let entries = try await store.children(of: .root, sortedBy: sortOrder)
            guard store === self.store, listingNumber == rootListingNumber else { return }
            rootDateAtLastListing = rootDate
            adoptRootListing(entries)
        } catch {
            guard store === self.store, listingNumber == rootListingNumber else { return }
            hasListedRoot = true
            errorMessage = error.localizedDescription
        }
        // The vault's settings arrived with another order while this one was being sorted.
        if store === self.store, listingNumber == rootListingNumber, vaultSettings.fileSortOrder != sortOrder { await listRoot() }
    }

    private func adoptRootListing(_ entries: [VaultEntry]) {
        hasListedRoot = true
        // An unchanged listing asks the file provider about nothing again, and no row is drawn.
        guard entries != rootEntries else { return }
        rootEntries = entries
        checkConflictVersions(ofListedFiles: entries.lazy.filter { entry in !entry.isDirectory }.map(\.path))
    }

    /// A file or folder Graphite just made at `path`: it shows in the listings of the folders
    /// above it, which may be new as well.
    func showInListings(_ path: VaultPath) async {
        var foldersAbove: Set<VaultPath> = []
        var folder = path.parent
        while !folder.rawValue.isEmpty {
            foldersAbove.insert(folder)
            folder = folder.parent
        }
        await refreshListings(changedItems: [path], foldersToListAgain: foldersAbove.union([.root]))
    }

    /// Brings the listings up to date with changes to these items and leaves everything else
    /// alone: each top-level item they are in is read and placed in the root's sorted listing,
    /// and only `foldersToListAgain` list themselves.
    func refreshListings(changedItems: [VaultPath], foldersToListAgain: Set<VaultPath>) async {
        guard let store else { return }
        // Read after a listing under way, so it cannot bring back what changed since it read.
        await rootListingInFlight?.value
        guard store === self.store else { return }
        let topLevelItems = Set(changedItems.compactMap(Self.topLevelItem))
        let changes = await store.entries(at: topLevelItems)
        guard store === self.store else { return }
        await placeInRootListing(changes)
        guard store === self.store, !foldersToListAgain.isEmpty else { return }
        var versions = folderListingVersions
        for folder in foldersToListAgain { versions[folder, default: 0] += 1 }
        folderListingVersions = versions
    }

    /// The item directly in the vault's root that holds `path`, or is it.
    nonisolated static func topLevelItem(of path: VaultPath) -> VaultPath? {
        guard let firstComponent = path.rawValue.split(separator: "/", maxSplits: 1).first else { return nil }
        return try? VaultPath(String(firstComponent))
    }

    /// Takes the comparisons off the main actor, where a sync's many reports would add up. The
    /// root's listing may change meanwhile, and the changes are then placed in the new one.
    private func placeInRootListing(_ changes: [VaultPath: VaultEntry?]) async {
        let sortOrder = vaultSettings.fileSortOrder
        while true {
            let listedEntries = rootEntries
            let placedEntries = await Task.detached(priority: .utility) { () -> [VaultEntry] in
                // A folder's listed date moves with each file added to it, and no list draws it:
                // a folder already listed stays as it is, and so do the root's rows. Folders
                // come first in every order.
                let listedFolders = Set(listedEntries.prefix { entry in entry.isDirectory }.map(\.path))
                let shownChanges = changes.filter { path, entry in entry?.isDirectory != true || !listedFolders.contains(path) }
                return sortOrder.applying(shownChanges, to: listedEntries)
            }.value
            guard listedEntries == rootEntries else { continue }
            if placedEntries != listedEntries { rootEntries = placedEntries }
            return
        }
    }

    /// Refreshes what other apps' reported changes touch.
    func applyExternalChanges(_ refresh: ExternalChangeRefresh) async {
        switch refresh {
        case .nothingShown:
            break
        case .items(let files, let folders):
            // Only the open documents another app is known to have changed are read again;
            // with a whole folder reported, any open document may be inside it.
            await checkOpenDocumentsForExternalChanges(limitedTo: folders.isEmpty ? Set(files) : nil)
            // A provider reports a version it gained or lost as a change to the file.
            checkConflictVersions(of: files)
            var foldersToListAgain = Set((files + folders).map(\.parent))
            foldersToListAgain.formUnion(folders)
            foldersToListAgain.formUnion(expandedFolders.filter { expandedFolder in folders.contains { folder in expandedFolder.isInside(folder) } })
            await refreshListings(changedItems: files + folders, foldersToListAgain: foldersToListAgain)
            if await changeShowsInOpenDocuments(files: files, folders: folders) { drawingVersion += 1 }
            refreshIndex(for: files)
            for folder in folders { startIndexing(.folder(folder)) }
        case .wholeVault:
            await checkOpenDocumentsForExternalChanges()
            checkConflictVersions(of: tabDocuments.values.compactMap(\.loadedPath))
            await refreshDirectory()
            drawingVersion += 1
            startIndexing(.spaced)
        }
    }

    /// Whether a scan of this launch has finished, after waiting for the one under way when the
    /// index is complete from an earlier launch, for as long as a person would wait on a tap.
    func isIndexCompleteAfterRunningScan() async -> Bool {
        guard isIndexUsable else { return hasCompletedIndexScan }
        let deadline = Date.now.addingTimeInterval(Self.longestWaitForRunningScan)
        while !hasCompletedIndexScan, isIndexing, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return hasCompletedIndexScan
    }

    private static let longestWaitForRunningScan: TimeInterval = 10

    // MARK: Coming back to the front

    /// The window stopped being in front.
    func noteLeftFront() {
        timeLeftFront = clock.now
    }

    /// The window came back: the files open in it are checked, then the root is listed and the
    /// settings read only if something says they changed. On a Mac this happens at every switch
    /// between apps, and the file presenter reports changes while the window is behind others.
    func refreshAfterComingToFront() async {
        await checkOpenDocumentsForExternalChanges()
        guard let store else { return }
        let wasAwayLong = timeLeftFront.map { timeLeft in clock.now - timeLeft >= Self.awayTimeBeforeListingAgain } ?? false
        timeLeftFront = nil
        // A vault still opening has its first listing under way.
        if rootListingInFlight == nil {
            var listsAgain = wasAwayLong || rootDateAtLastListing == nil
            if !listsAgain { listsAgain = await store.listingDate(of: .root) != rootDateAtLastListing }
            if listsAgain { await refreshDirectory() }
        }
        guard store === self.store else { return }
        if await store.settingsFilesRevision() != settingsFilesRevisionAtLastReading { await reloadVaultSettings() }
    }

    // MARK: What a change means for the documents shown

    /// Whether what changed can show in an open document, which is rebuilt with every picture
    /// in it when it does. A note syncing elsewhere in the vault cannot, unless an open note
    /// embeds it, directly or through another note, or an open canvas may have a card of it.
    private func changeShowsInOpenDocuments(files: [VaultPath], folders: [VaultPath]) async -> Bool {
        guard folders.isEmpty else { return true }
        if files.contains(where: Self.isShownAsContent) { return true }
        return await changedNotesShow(files.filter { path in DocumentKind(path: path) == .markdown })
    }

    private static func isShownAsContent(_ path: VaultPath) -> Bool {
        switch DocumentKind(path: path) {
        case .image, .pdf, .canvas, .media: true
        case .markdown, .base, .other: false
        }
    }

    private func changedNotesShow(_ changedNotes: [VaultPath]) async -> Bool {
        guard !changedNotes.isEmpty else { return false }
        let openDocuments = tabDocuments.values
        if openDocuments.contains(where: { document in document.canvasSession != nil }) { return true }
        let openNotes = openDocuments.compactMap(\.markdownSession).map { session in (path: session.path, text: session.text) }
        // The text as it is now, which the index may not have read yet.
        let embedsNamedInOpenNotes = await Task.detached(priority: .utility) { () -> Bool in
            openNotes.contains { note in EmbeddedNoteNames.anyEmbed(in: note.text, names: changedNotes) }
        }.value
        if embedsNamedInOpenNotes { return true }
        guard let index else { return false }
        let openNotePaths = Set(openNotes.map(\.path))
        guard !openNotePaths.isEmpty else { return false }
        // A note embedded through another note: the index knows who embeds whom.
        let notesEmbeddingThem = (try? await index.notesEmbedding(changedNotes, throughLevels: EmbeddedNoteNames.levelsFollowed)) ?? [] // Not known: treated as not embedded; the note reloads when opened.
        return !notesEmbeddingThem.isDisjoint(with: openNotePaths)
    }
}

/// Finds, in a note's text, embeds that name one of the changed notes. A simple text check,
/// since a miss here only delays a redraw of the embed until the next change it sees.
enum EmbeddedNoteNames {
    /// Embeds inside embeds followed from an open note.
    static let levelsFollowed = 4

    static func anyEmbed(in text: String, names notes: [VaultPath]) -> Bool {
        guard text.contains("![") else { return false }
        guard let semantics = try? MarkdownSemantics.parse(text) else { return false } // Text that cannot be parsed shows no embed.
        let embedTargets = semantics.links.lazy.filter(\.isEmbed).map { link in normalized(WikiLinkResolver.pathPart(link.target)) }
        guard !embedTargets.isEmpty else { return false }
        return embedTargets.contains { target in
            notes.contains { note in
                let notePath = normalized(note.rawValue)
                return notePath == target || notePath.hasSuffix("/" + target)
            }
        }
    }

    private static func normalized(_ linkText: String) -> String {
        var text = WikiLinkResolver.comparisonKey(linkText.removingPercentEncoding ?? linkText).lowercased()
        while text.hasPrefix("./") || text.hasPrefix("../") || text.hasPrefix("/") {
            text = String(text.drop { character in character == "." || character == "/" })
        }
        if text.hasSuffix(".md") { text.removeLast(3) }
        return text
    }
}

/// What a batch of changes reported by other apps needs refreshed.
enum ExternalChangeRefresh: Equatable {
    /// Only files the vault does not show changed, such as Obsidian's own `.obsidian` files.
    case nothingShown
    /// These files changed, and are refreshed one by one, and these folders, which are
    /// listed and scanned on their own.
    case items(files: [VaultPath], folders: [VaultPath])
    /// Many files, or places that cannot be named changed; one reconciling scan finds what they were.
    case wholeVault

    init(changedLocations: Set<URL>, root: URL, maximumFileCount: Int) {
        // Resolving a path touches the file system for each of its folders, so the root is
        // resolved once, and each location at most once.
        let rootPath = WorkspaceModel.comparablePath(of: root)
        var changedFiles: [VaultPath] = []
        var changedFolders: [VaultPath] = []
        var hasItemLocation = false
        // Every answer other than refreshing items one by one is a whole-vault scan, so the
        // first location that calls for one decides, and the rest are not resolved.
        for location in changedLocations {
            let locationPath = WorkspaceModel.comparablePath(of: location)
            // The vault folder itself is reported along with the items that changed in it,
            // and those items tell what changed.
            guard locationPath != rootPath else { continue }
            hasItemLocation = true
            guard let path = WorkspaceModel.vaultPath(forComparablePath: locationPath, rootPath: rootPath) else {
                self = .wholeVault
                return
            }
            // Hidden folders and files, like `.obsidian` and `.trash`, are neither listed
            // nor indexed, as in Obsidian.
            guard !path.isHidden else { continue }
            if (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                changedFolders.append(path)
            } else {
                changedFiles.append(path)
            }
            if changedFiles.count + changedFolders.count > maximumFileCount {
                self = .wholeVault
                return
            }
        }
        // The vault folder reported alone gives no way to tell what changed.
        guard hasItemLocation else {
            self = .wholeVault
            return
        }
        // A folder reported with others inside it is scanned once, from the outermost.
        let outermostFolders = changedFolders.filter { folder in !changedFolders.contains { otherFolder in otherFolder != folder && folder.isInside(otherFolder) } }
        self = changedFiles.isEmpty && outermostFolders.isEmpty ? .nothingShown : .items(files: changedFiles.sorted(), folders: outermostFolders.sorted())
    }
}
