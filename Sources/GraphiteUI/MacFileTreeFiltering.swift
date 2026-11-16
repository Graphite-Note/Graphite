/**
 * File: MacFileTreeFiltering.swift
 * --------------------------------
 * Layer: UI
 * Description: The Mac file tree's rows while the Files panel's filter narrows it: the matches, the folders above them,
 *              and a matching folder's whole content, made from the vault's names as the outline view asks for them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

/// What the Mac's outline shows while the filter narrows the tree, read from `FileTreeNameFilterResult` alone: no
/// folder is listed from disk. Its nodes are its own, so the tree's nodes, with the contents their folders listed, wait
/// unchanged for the filter to be cleared. A folder's nodes are made the first time the outline view asks for them.
@MainActor
final class FilteredFileTree {
    /// The filter as the sidebar shows it: its matches, and the folders it shows expanded.
    struct Filter: Equatable {
        var isFiltering = false
        /// Nil while the vault's names are being read: the tree is then empty.
        var result: FileTreeNameFilterResult?
        var expandedFolders: Set<VaultPath> = []
        var text = ""
    }

    let result: FileTreeNameFilterResult?
    private(set) var rootNodes: [FileTreeNode] = []
    private(set) var nodesByPath: [VaultPath: FileTreeNode] = [:]

    init(result: FileTreeNameFilterResult?) {
        self.result = result
        rootNodes = makeNodes(for: result?.shownChildren(of: .root) ?? [], parent: nil)
    }

    /// Shows the filter's expanded folders, outermost first: a folder's rows are made as it expands, and those inside it
    /// expand after. A new result reloads every row; otherwise only the folders closed since are folded.
    func show(_ expandedFolders: Set<VaultPath>, in outlineView: NSOutlineView, reloading: Bool, previouslyExpanded: Set<VaultPath>) {
        if reloading {
            outlineView.reloadData()
        } else {
            for path in previouslyExpanded.subtracting(expandedFolders) {
                if let node = nodesByPath[path] { outlineView.collapseItem(node) }
            }
        }
        for path in expandedFolders.sorted(by: { leftPath, rightPath in leftPath.rawValue.count < rightPath.rawValue.count }) {
            guard let node = nodesByPath[path], node.parent.map(outlineView.isItemExpanded) ?? true, !outlineView.isItemExpanded(node) else { continue }
            outlineView.expandItem(node)
        }
    }

    /// What a folder shows while filtering, made on first asking.
    func children(of node: FileTreeNode) -> [FileTreeNode] {
        if let children = node.children { return children }
        let children = makeNodes(for: result?.shownChildren(of: node.path) ?? [], parent: node)
        node.children = children
        return children
    }

    private func makeNodes(for entries: [VaultEntry], parent: FileTreeNode?) -> [FileTreeNode] {
        entries.map { entry in
            let node = FileTreeNode(entry: entry, parent: parent)
            nodesByPath[entry.path] = node
            return node
        }
    }
}

extension FileTreeController {
    /// The part of a row's title the filter matched, as a range of the title and extension drawn.
    static func filterHighlightRange(of text: String, inTitle title: String, extensionSuffix: String?) -> NSRange? {
        let drawnTitle = title + (extensionSuffix ?? "")
        guard let matchedRange = VaultNameMatching.matchedRange(of: text, in: drawnTitle) else { return nil }
        return NSRange(matchedRange, in: drawnTitle)
    }
}
#endif
