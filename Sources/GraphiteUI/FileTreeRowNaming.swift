/**
 * File: FileTreeRowNaming.swift
 * -----------------------------
 * Layer: UI
 * Description: The iPad's and the iPhone's file list name a new note, base, canvas or folder in a row of its folder and
 *              rename in the item's row, as the Files app renames in place and as the Mac's file tree does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import SwiftUI
import GraphiteCore

/// The name field of the iPad's and the iPhone's file list (`FileTreeRows`): which item it names, where its row is,
/// and what leaving it does, with the decisions of `FileTreeNameDraft` the Mac's tree takes too. The list registers it
/// with the workspace while it is on screen; the sheets stand in otherwise.
@MainActor @Observable final class FileTreeRowNaming: FileTreeNaming {
    /// The field shown: what it names, and the text typed so far.
    struct Field: Equatable {
        let subject: FileTreeNamingSubject
        var text: String
        /// This field's own. A new item's row had one identifier for every field, so the list kept the row of a field
        /// Escape had dropped for the next new item, with the name typed into it and the keyboard, and a change of
        /// focus made that name; a row now speaks only for its own field.
        let instance = UUID()

        /// The identifier of the list's row the field is in: the renamed item's, or the new item's own, which no item's
        /// path can be, so the field keeps its row, and the keyboard, as listings arrive.
        var rowIdentifier: String { renamedPath?.rawValue ?? "\u{0}new-item-field-\(instance.uuidString)" }

        /// The folder the named item is in.
        var folder: VaultPath {
            switch subject {
            case .newItem(_, let directory): directory
            case .existingItem(let path, _): path.parent
            }
        }

        var renamedPath: VaultPath? {
            if case .existingItem(let path, _) = subject { path } else { nil }
        }
    }

    private(set) var field: Field?

    /// The identifier of the list's row the field is in.
    var scrollTarget: String? { field?.rowIdentifier }
    /// Set when the field asks to be focused again: Return on a name that cannot be used keeps the field open, as the
    /// keyboard's Return otherwise takes the focus away.
    private(set) var refocusRequest = 0
    /// What naming needs of the workspace; nil until the list is shown.
    @ObservationIgnored private var vault: FileTreeRowNamingVault?
    private var contents: FileTreeContents? { vault?.contents }
    /// Whether the list is on screen and shows the vault's tree (not a search, another panel or an empty vault): a
    /// sidebar folded away has slid off the window's left edge.
    @ObservationIgnored var isTreeOnScreen: () -> Bool = { false }

    init() {
        isTreeOnScreen = { [unowned self] in
            showsTree && listFrame.width > 1 && listFrame.height > 1 && listFrame.maxX > 1 && listFrame.minX > -1
        }
    }
    /// Return ends the keyboard's focus right after asking for the outcome; that loss is not a click elsewhere.
    @ObservationIgnored private var ignoresNextFocusLoss = false
    @ObservationIgnored var showsTree = false
    /// The list's frame in the window.
    @ObservationIgnored var listFrame = CGRect.zero

    func attach(to vault: FileTreeRowNamingVault) {
        self.vault = vault
    }

    func beginNaming(_ request: FileTreeNamingRequest) -> Bool {
        guard let vault, let contents = vault.contents, isTreeOnScreen(), !contents.filter.isFiltering else { return false }
        switch request {
        case .rename(let path):
            guard let row = contents.rows.first(where: { row in row.entry.path == path }) else { return false }
            let subject = FileTreeNamingSubject.existingItem(path, isFolder: row.entry.isDirectory)
            field = Field(subject: subject, text: draft(for: subject).initialText)
        case .create(let kind, let directory):
            // A folder that is not there yet (the vault's folder for new notes, made with the note) has no row.
            guard directory.rawValue.isEmpty || vault.isFolder(directory) else { return false }
            // The folder and the folders above it open; each lists its contents as it opens.
            var folder = directory
            while !folder.rawValue.isEmpty {
                vault.expandFolder(folder)
                folder = folder.parent
            }
            field = Field(subject: .newItem(kind, in: directory), text: "")
        }
        ignoresNextFocusLoss = false
        return true
    }

    /// The decisions for the field, against the names its folder's rows hold now (a folder opened for a new item may
    /// still be listing).
    func draft(for subject: FileTreeNamingSubject) -> FileTreeNameDraft {
        let folder: VaultPath = switch subject {
        case .newItem(_, let directory): directory
        case .existingItem(let path, _): path.parent
        }
        let names = contents?.rows.lazy.filter { row in row.entry.path.parent == folder }.map(\.entry.path.name) ?? []
        return FileTreeNameDraft(subject: subject, namesInFolder: Array(names))
    }

    func setText(_ text: String) {
        field?.text = text
    }

    /// Why the typed name cannot be used, for the line under the field.
    var problem: String? {
        guard let field else { return nil }
        return draft(for: field.subject).problem(typed: field.text)
    }

    /// Leaves the field as `end` asks, or keeps it open (Return on a name that cannot be used).
    func end(_ end: FileTreeNamingEnd) {
        guard let field, let vault else { return }
        if end == .focusLeft && ignoresNextFocusLoss {
            ignoresNextFocusLoss = false
            return
        }
        guard let outcome = draft(for: field.subject).outcome(typed: field.text, endedBy: end) else {
            ignoresNextFocusLoss = true
            refocusRequest += 1
            return
        }
        self.field = nil
        ignoresNextFocusLoss = false
        Task { await vault.finish(outcome) }
    }

    /// Where the new item's field goes among `rows`: first in its folder for a folder, where the folder's files begin
    /// for a file, at the depth of the folder's contents; nil while the folder's row is not listed.
    static func newItemPlace(in rows: [FileTreeRow], folder: VaultPath, isFolder: Bool) -> (index: Int, depth: Int)? {
        var start = 0, depth = 0
        if !folder.rawValue.isEmpty {
            guard let folderIndex = rows.firstIndex(where: { row in row.entry.path == folder }) else { return nil }
            start = folderIndex + 1
            depth = rows[folderIndex].depth + 1
        }
        var index = start
        while index < rows.count, rows[index].depth >= depth {
            let row = rows[index]
            if row.depth == depth && (isFolder || !row.entry.isDirectory) { break }
            index += 1
        }
        return (isFolder ? start : index, depth)
    }
}

/// What the list's naming needs of the workspace: its rows, whether a folder is there, opening folders, and doing what
/// a finished field asks for; and registering the list as the one that names rows.
struct FileTreeRowNamingVault {
    /// Held weakly: the rows own the naming, which keeps this.
    weak var contents: FileTreeContents?
    let isFolder: (VaultPath) -> Bool
    let expandFolder: (VaultPath) -> Void
    let finish: (FileTreeNamingOutcome) async -> Void
    let register: (FileTreeRowNaming) -> Void
}

extension WorkspaceModel {
    /// The list shows the vault's tree of files, where a name can be typed in a row: no search, a vault with files.
    var showsFileTree: Bool { store != nil && searchQuery.isEmpty && hasListedRoot && !rootEntries.isEmpty }

    /// The list's naming in its rows; `showsTree` says the sidebar shows its Files panel.
    func fileTreeRowNamingList(showsTree: Bool) -> FileTreeRowNamingList {
        FileTreeRowNamingList(naming: fileTreeContents.rowNaming, vault: fileTreeRowNamingVault, showsTree: showsTree && showsFileTree)
    }

    var fileTreeRowNamingVault: FileTreeRowNamingVault {
        FileTreeRowNamingVault(contents: fileTreeContents, isFolder: { [weak self] path in self?.isDirectory(path) ?? false },
                               expandFolder: { [weak self] folder in self?.expandedFolders.insert(folder) },
                               finish: { [weak self] outcome in await self?.finishNaming(outcome) },
                               register: { [weak self] naming in self?.registerFileTreeNaming(naming) })
    }
}

/// Makes the iPad's and the iPhone's file list name items in its rows: registers its naming with the workspace while
/// the list is on screen and shows the tree, else the sheets stand in, and scrolls the name field into view. Whether
/// the list is on screen is read from its own frame in the window (a folded sidebar slides off the left edge), as a
/// view behind or over a list is not put in the window's views. The Mac's tree is AppKit's outline view, which names
/// its own rows.
struct FileTreeRowNamingList: ViewModifier {
    let naming: FileTreeRowNaming
    let vault: FileTreeRowNamingVault
    /// The list shows the vault's tree: the Files panel, no search, a vault with files.
    let showsTree: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        ScrollViewReader { scrollProxy in
            content
                .onGeometryChange(for: CGRect.self) { proxy in proxy.frame(in: .global) } action: { frame in
                    naming.listFrame = frame
                    registerIfOnScreen()
                }
                .onAppear(perform: registerIfOnScreen)
                .onChange(of: showsTree, initial: true) { _, shows in
                    naming.showsTree = shows
                    registerIfOnScreen()
                }
                // A field below or above the screen is brought into view, so the keyboard has it to type into; a new
                // item's row comes once its folder has listed its contents, which changes the rows.
                .task(id: "\(naming.scrollTarget ?? "")|\(vault.contents?.rows.count ?? 0)") {
                    guard let target = naming.scrollTarget else { return }
                    scrollProxy.scrollTo(target, anchor: .center)
                }
        }
        #endif
    }

    /// A window can draw more than one sidebar, and a list can stay in the window while hidden (a context menu's
    /// preview, a sidebar sliding away), so the list on screen registers, not the last to appear: the workspace holds
    /// the naming weakly and asks it whether its list is on screen.
    private func registerIfOnScreen() {
        naming.attach(to: vault)
        if naming.isTreeOnScreen() { vault.register(naming) }
    }
}

/// The name field in a row of the list: the item's marker, a field holding the name (a file's kept extension muted
/// after it), and why a typed name cannot be used under it.
struct FileTreeNameFieldRow: View {
    let naming: FileTreeRowNaming
    let field: FileTreeRowNaming.Field
    let depth: Int
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var selection: TextSelection?

    private var draft: FileTreeNameDraft { naming.draft(for: field.subject) }

    private var isFolder: Bool {
        switch field.subject {
        case .newItem(let kind, _): kind == .folder
        case .existingItem(_, let isFolder): isFolder
        }
    }

    var body: some View {
        FileTreeRowLabel(depth: depth) {
            if isFolder {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            } else {
                Color.clear.frame(height: 1)
            }
        } title: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    nameField
                    if let suffix = draft.keptExtensionSuffix {
                        Text(suffix).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                    }
                }
                if let problem = draft.problem(typed: text) {
                    Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            text = field.text
            isFocused = true
            // The whole name selected, as the Files app and the Mac's tree start a rename: on the next turn, once the
            // field holds the text, or the selection is dropped and the cursor goes to the end. A new item's empty
            // field has nothing to select, and letters a hardware keyboard typed before that turn keep their place:
            // a selection put on them moved the cursor to the start and lost the letters after it.
            let name = field.text
            guard !name.isEmpty else { return }
            Task { @MainActor in
                guard text == name else { return }
                selection = TextSelection(range: text.startIndex..<text.endIndex)
            }
        }
        .onChange(of: naming.refocusRequest) { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            if !focused { end(.focusLeft) }
        }
    }

    /// Typed into the row's own text, handed to the naming only when the field ends: a binding into the naming, and
    /// then each key's text passed on to it, redrew the list at each key, which wrote older text back over letters the
    /// field had just taken, and fast typing lost them (a hardware keyboard made "Week 3 drft" of "Week 3 draft").
    private var nameField: some View {
        TextField(draft.placeholder, text: $text, selection: $selection)
            .focused($isFocused)
            #if canImport(UIKit)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { end(.returnKey) }
            .onKeyPress(.escape) {
                end(.escapeKey)
                return .handled
            }
            .accessibilityLabel(field.renamedPath == nil ? "New item name" : "Name")
    }

    /// Hands the naming the text typed, which it decides the field's end with.
    private func end(_ end: FileTreeNamingEnd) {
        // A row left after another field began speaks for nothing, even one naming the same new item.
        guard naming.field?.instance == field.instance else { return }
        naming.setText(text)
        naming.end(end)
    }
}
