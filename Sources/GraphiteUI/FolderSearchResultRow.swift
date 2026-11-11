/**
 * File: FolderSearchResultRow.swift
 * ---------------------------------
 * Layer: UI
 * Description: A folder the search's folder: found, listed above the notes: choosing it reveals the folder in the file
 *              tree, and its menu has the folder's actions.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// A folder among the search's results: its name, with the folder symbol, and its path under it. Choosing it shows the
/// folder in the file tree, expanded and marked, in place of the results; its menu offers the same, then `menu`, the
/// actions of the folder's menu in the tree.
struct FolderSearchResultRow<Menu: View>: View {
    let folder: VaultPath
    let reveal: () -> Void
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).lineLimit(1).interfaceFont(.body)
                    if !folder.parent.rawValue.isEmpty {
                        Text(folder.parent.rawValue).interfaceFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not a file the list's selection could open.
        .selectionDisabled()
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.parent.rawValue)
        .accessibilityHint("Folder. Reveals it in the file tree")
        .contextMenu {
            Button("Reveal in File Tree", systemImage: "scope", action: reveal)
            Divider()
            menu()
        }
    }
}
