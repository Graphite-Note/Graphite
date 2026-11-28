/**
 * File: MacFileTreeNaming.swift
 * -----------------------------
 * Layer: UI
 * Description: The Mac file tree names new items and renames in its own rows, as VSCodium's explorer does: a field in
 *              the row, the problem with a typed name in a small popover under it, Return to keep, Escape to cancel.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

/// The row the tree adds inside a folder while a new item is named, before the item exists. New folders go first, as
/// folders list first; new files go after the folder's folders.
@MainActor
final class FileTreeNewItemRow {
    let kind: FileTreeCreatableKind
    /// The folder's node, or nil for the vault's root.
    let folder: FileTreeNode?
    /// Its place among the folder's listed items.
    let index: Int

    init(kind: FileTreeCreatableKind, folder: FileTreeNode?, index: Int) {
        self.kind = kind
        self.folder = folder
        self.index = index
    }
}

/// Where the tree is in naming a row.
@MainActor
enum FileTreeNamingPhase {
    case idle
    /// A new item asked for in `directory` while `folder`, the directory or a folder above it, is being listed: the
    /// folders open one level at a time, and the row appears once the directory's contents are listed.
    case waitingForListing(FileTreeCreatableKind, directory: VaultPath, folder: FileTreeNode)
    case editing(FileTreeNameEditor)
}

/// One name being typed in a row: the field, which the row shows over its title, and the popover that says why a
/// typed name cannot be used. It tells its owner, the tree, once the field is left.
@MainActor
final class FileTreeNameEditor: NSObject, NSTextFieldDelegate {
    let draft: FileTreeNameDraft
    /// The new item's row, or nil for a rename.
    let newItemRow: FileTreeNewItemRow?
    /// The renamed item's node, or nil for a new item.
    let renamedNode: FileTreeNode?
    let field = FileTreeNameField()
    private weak var owner: FileTreeController?
    private let problemPopover = NSPopover()
    private let problemLabel = NSTextField(wrappingLabelWithString: "")
    private let problemIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
    private let problemContent = NSView()
    private(set) var hasEnded = false

    init(draft: FileTreeNameDraft, newItemRow: FileTreeNewItemRow?, renamedNode: FileTreeNode?, font: NSFont, owner: FileTreeController) {
        self.draft = draft
        self.newItemRow = newItemRow
        self.renamedNode = renamedNode
        self.owner = owner
        super.init()
        field.stringValue = draft.initialText
        field.placeholderString = draft.placeholder
        field.font = font
        field.delegate = self
        field.setAccessibilityLabel(newItemRow == nil ? "Name" : "New name")
        problemLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        problemLabel.textColor = .labelColor
        problemIcon.contentTintColor = .systemRed
        problemContent.addSubview(problemIcon)
        problemContent.addSubview(problemLabel)
        let problemController = NSViewController()
        problemController.view = problemContent
        problemPopover.contentViewController = problemController
        // Shown and closed by the field as it is typed in: a click elsewhere ends the naming, not only the popover.
        problemPopover.behavior = .applicationDefined
        problemPopover.animates = false
    }

    /// Puts the keyboard in the field with the whole name selected, so typing replaces it.
    func takeKeyboard() {
        guard let window = field.window, window.makeFirstResponder(field) else { return }
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (field.stringValue as NSString).length)
        showProblem()
    }

    /// Ends the naming as the person left the field, unless Return found a name that cannot be used.
    func end(_ end: FileTreeNamingEnd) {
        guard !hasEnded, let outcome = draft.outcome(typed: field.stringValue, endedBy: end) else { return }
        hasEnded = true
        problemPopover.close()
        owner?.endNaming(with: outcome, returningKeyboard: end != .focusLeft)
    }

    private func showProblem() {
        guard !hasEnded, let problem = draft.problem(typed: field.stringValue) else { return problemPopover.close() }
        problemLabel.stringValue = problem
        layOutProblem()
        guard !problemPopover.isShown, field.window != nil else { return }
        // Under the field: its bottom edge is maxY in the field's flipped coordinates.
        problemPopover.show(relativeTo: field.bounds, of: field, preferredEdge: field.isFlipped ? .maxY : .minY)
    }

    /// The icon, then the text wrapped at a popover's width, sized by hand: a stack view's fitting size leaves a
    /// wrapping label out.
    private func layOutProblem() {
        let margin: CGFloat = 10, iconSide: CGFloat = 16, spacing: CGFloat = 6, widestText: CGFloat = 240
        let textSize = problemLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: widestText, height: .greatestFiniteMagnitude)) ?? .zero
        let textWidth = ceil(min(widestText, textSize.width)), textHeight = ceil(textSize.height)
        let contentHeight = max(iconSide, textHeight) + 2 * 8
        problemIcon.frame = NSRect(x: margin, y: contentHeight - 8 - iconSide, width: iconSide, height: iconSide)
        problemLabel.frame = NSRect(x: margin + iconSide + spacing, y: contentHeight - 8 - textHeight, width: textWidth, height: textHeight)
        problemPopover.contentSize = NSSize(width: margin + iconSide + spacing + textWidth + margin, height: contentHeight)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        showProblem()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            end(.returnKey)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            end(.escapeKey)
            return true
        default:
            return false
        }
    }

    /// Left by a click on another row, the field ends once the click is handled: the new item's row going away
    /// within the click would move the rows under the pointer, and the row below the one clicked would open.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !hasEnded else { return }
        DispatchQueue.main.async { [weak self] in self?.end(.focusLeft) }
    }
}

/// The name field of a row: the system's text field with its focus ring, single line, scrolling when the name is long.
final class FileTreeNameField: NSTextField {
    init() {
        super.init(frame: .zero)
        isBezeled = true
        bezelStyle = .squareBezel
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        focusRingType = .exterior
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.isScrollable = true
        cell?.wraps = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension FileTreeController: FileTreeNaming {
    /// Starts naming in a row: the renamed item's row when it is listed, or a new row in the folder, which opens,
    /// together with the folders above it. False when the tree is not on screen, is filtered, or does not list the item.
    func beginNaming(_ request: FileTreeNamingRequest) -> Bool {
        guard let outlineView, isOnScreen(outlineView), !isFiltering else { return false }
        if case .editing(let editor) = namingPhase { editor.end(.escapeKey) }
        namingPhase = .idle
        switch request {
        case .rename(let path):
            guard let node = nodesByPath[path] else { return false }
            expandFoldersAbove(node)
            guard outlineView.row(forItem: node) >= 0 else { return false }
            let siblings = node.parent?.children ?? rootNodes
            let draft = FileTreeNameDraft(subject: .existingItem(path, isFolder: node.entry.isDirectory), namesInFolder: siblings.map(\.path.name))
            startEditing(FileTreeNameEditor(draft: draft, newItemRow: nil, renamedNode: node, font: rowFont, owner: self), item: node)
        case .create(let kind, let directory):
            guard !directory.rawValue.isEmpty else {
                addNewItemRow(kind, in: nil)
                return true
            }
            // A folder that is not there yet (the vault's folder for new notes, made with the note) has no row.
            guard workspace.isDirectory(directory), let folder = nearestListedFolder(toward: directory) else { return false }
            expandFoldersAbove(folder)
            openFolders(from: folder, toward: directory, forNew: kind)
        }
        return true
    }

    /// The directory's node when it is listed, else the listed folder nearest above it.
    private func nearestListedFolder(toward directory: VaultPath) -> FileTreeNode? {
        var path = directory
        while !path.rawValue.isEmpty {
            if let node = nodesByPath[path], node.entry.isDirectory { return node }
            path = path.parent
        }
        return nil
    }

    /// Opens `folder`, then each folder below it toward `directory` as its contents are listed, and adds the new item's
    /// row in `directory`.
    private func openFolders(from folder: FileTreeNode, toward directory: VaultPath, forNew kind: FileTreeCreatableKind) {
        guard let outlineView else { return }
        if !outlineView.isItemExpanded(folder) { outlineView.expandItem(folder) }
        guard let children = folder.children else {
            namingPhase = .waitingForListing(kind, directory: directory, folder: folder)
            return
        }
        guard folder.path != directory else { return addNewItemRow(kind, in: folder) }
        guard let next = children.first(where: { child in child.entry.isDirectory && directory.isInside(child.path) }) else {
            // Gone while it was being opened: nothing is named.
            namingPhase = .idle
            return
        }
        openFolders(from: next, toward: directory, forNew: kind)
    }

    /// The new item's row, while one is named.
    var newItemRow: FileTreeNewItemRow? {
        guard case .editing(let editor) = namingPhase else { return nil }
        return editor.newItemRow
    }

    /// Called by the editor once its field is left: the row gets its title back, what the tree held back while the name
    /// was typed is shown, and the workspace does what the field asked for.
    func endNaming(with outcome: FileTreeNamingOutcome, returningKeyboard: Bool) {
        guard case .editing(let editor) = namingPhase, let outlineView else { return }
        namingPhase = .idle
        // The field leaves its cell first: the cell is kept for the next row of its kind.
        let namedItem: AnyObject? = editor.newItemRow ?? editor.renamedNode
        let row = namedItem.map { item in outlineView.row(forItem: item) } ?? -1
        if row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileTreeCellView { cell.removeNameField() }
        if let newItemRow = editor.newItemRow {
            outlineView.removeItems(at: IndexSet(integer: newItemRow.index), inParent: newItemRow.folder, withAnimation: [])
        }
        if returningKeyboard { outlineView.window?.makeFirstResponder(outlineView) }
        applyChangesHeldWhileNaming()
        Task { await workspace.finishNaming(outcome) }
    }

    /// A folder's contents arrived: a new item waiting for them gets its row.
    func startNamingWaitingFor(_ folder: FileTreeNode) {
        guard case .waitingForListing(let kind, let directory, let waitingFolder) = namingPhase, waitingFolder === folder else { return }
        namingPhase = .idle
        openFolders(from: folder, toward: directory, forNew: kind)
    }

    /// The field for the row's item while it is named, which the row shows over its title.
    func nameField(for item: AnyObject) -> (field: FileTreeNameField, extensionSuffix: String?)? {
        guard case .editing(let editor) = namingPhase, editor.newItemRow === item || editor.renamedNode === item else { return nil }
        return (editor.field, editor.draft.keptExtensionSuffix)
    }

    private func addNewItemRow(_ kind: FileTreeCreatableKind, in folder: FileTreeNode?) {
        guard let outlineView else { return }
        let siblings = folder?.children ?? rootNodes
        let index = kind == .folder ? 0 : siblings.firstIndex { sibling in !sibling.entry.isDirectory } ?? siblings.count
        let row = FileTreeNewItemRow(kind: kind, folder: folder, index: index)
        let draft = FileTreeNameDraft(subject: .newItem(kind, in: folder?.path ?? .root), namesInFolder: siblings.map(\.path.name))
        let editor = FileTreeNameEditor(draft: draft, newItemRow: row, renamedNode: nil, font: rowFont, owner: self)
        namingPhase = .editing(editor)
        outlineView.insertItems(at: IndexSet(integer: index), inParent: folder, withAnimation: [])
        startEditing(editor, item: row)
    }

    private func startEditing(_ editor: FileTreeNameEditor, item: AnyObject) {
        guard let outlineView else { return }
        namingPhase = .editing(editor)
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return editor.end(.escapeKey) }
        outlineView.scrollRowToVisible(row)
        guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileTreeCellView else { return editor.end(.escapeKey) }
        cell.showNameField(editor.field, extensionSuffix: editor.draft.keptExtensionSuffix)
        editor.takeKeyboard()
    }

    /// The folders above the node open, outermost first, so its row shows.
    private func expandFoldersAbove(_ node: FileTreeNode) {
        var folders: [FileTreeNode] = []
        var ancestor = node.parent
        while let folder = ancestor {
            folders.append(folder)
            ancestor = folder.parent
        }
        for folder in folders.reversed() where outlineView?.isItemExpanded(folder) == false { outlineView?.expandItem(folder) }
    }

    /// Hidden behind a folded sidebar, in another sidebar panel, or in a window that is gone, the tree names nothing.
    private func isOnScreen(_ outlineView: NSOutlineView) -> Bool {
        outlineView.window != nil && !outlineView.isHiddenOrHasHiddenAncestor && outlineView.visibleRect.width >= Self.narrowestNamingWidth
    }

    /// Narrower than this, a sidebar is folding away and leaves no room to type a name.
    private static let narrowestNamingWidth: CGFloat = 80
}
#endif
