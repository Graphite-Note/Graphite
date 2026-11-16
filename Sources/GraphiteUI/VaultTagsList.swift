/**
 * File: VaultTagsList.swift
 * -------------------------
 * Layer: UI
 * Description: The left sidebar's Tags view: every tag in the vault, nested or flat, with the
 *              notes using it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 10/11/2026
 */

import SwiftUI
import GraphiteCore

/// Obsidian's Tags view: every tag in the vault with the notes using it. Tapping a tag
/// searches for it, nested tags included.
struct VaultTagsList: View {
    @Bindable var workspace: WorkspaceModel
    let overview: VaultOverviewModel
    @AppStorage(SidebarPanelSettingKey.tagSortOrder) private var sortOrder = VaultListSortOrder.frequencyDescending
    @AppStorage(SidebarPanelSettingKey.showsNestedTags) private var showsNestedTags = true
    @State private var expandedTags: Set<String> = []

    /// Opens the graph filtered to a tag's notes, nested tags included; nil while the graph is off.
    private var showInGraph: ((String) -> Void)? {
        guard workspace.preferences.isEnabled(.graph) else { return nil }
        return { [workspace] tag in workspace.showGraph(filteredBy: "tag:#" + tag) }
    }

    var body: some View {
        Section {
            if showsNestedTags {
                // One flat row per tag shown, not disclosure groups (`TagTree.visibleRows`).
                ForEach(TagTree.visibleRows(of: overview.tagTree(sortedBy: sortOrder), expandedTags: expandedTags)) { row in
                    NestedTagRow(row: row, isExpanded: expandedTags.contains(row.id), toggleExpansion: { toggleExpansion(of: row) },
                                 search: workspace.searchForTag, showInGraph: showInGraph)
                }
            } else {
                ForEach(sortOrder.sorted(overview.tagCounts, name: \.tag, count: \.fileCount), id: \.tag) { count in
                    TagRowLabel(title: count.tag, fileCount: count.fileCount, showInGraph: showInGraph.map { show in { show(count.tag) } }) {
                        workspace.searchForTag(count.tag)
                    }
                }
            }
            if !overview.hasLoadedTags {
                ProgressView().frame(maxWidth: .infinity)
            } else if overview.tagCounts.isEmpty && workspace.isIndexUsable {
                Text("No tags in this vault yet. Write #tag in a note, or add it to the note's tags property.").foregroundStyle(.secondary)
            }
        } footer: {
            if !workspace.isIndexUsable { Text("Still reading the vault; more tags may appear.") }
        }
    }

    private func toggleExpansion(of row: TagTreeVisibleRow) {
        withAnimation(GraphiteMotion.animation(.snappy)) {
            if expandedTags.contains(row.id) { expandedTags.remove(row.id) } else { expandedTags.insert(row.id) }
        }
    }
}

/// A tag of the nested Tags view: indented by its depth, with a chevron that shows or hides
/// the tags nested under it, as the file tree's folders have.
private struct NestedTagRow: View {
    let row: TagTreeVisibleRow
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    let search: (String) -> Void
    let showInGraph: ((String) -> Void)?

    private static let indentWidth: CGFloat = 14
    private static let chevronWidth: CGFloat = 16

    var body: some View {
        HStack(spacing: 4) {
            if row.hasNestedTags {
                Button(action: toggleExpansion) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: Self.chevronWidth, height: Self.chevronWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.name)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows or hides the tags nested in this tag")
            } else {
                // An empty slot where a tag with nested tags has its chevron, so names line up.
                Color.clear.frame(width: Self.chevronWidth, height: 1)
            }
            TagRowLabel(title: row.name, fileCount: row.fileCount, showInGraph: showInGraph.map { show in { show(row.tag) } }) { search(row.tag) }
        }
        .padding(.leading, CGFloat(row.depth) * Self.indentWidth)
    }
}

private struct TagRowLabel: View {
    let title: String
    let fileCount: Int
    /// Opens the graph filtered to the tag; nil while the graph is off.
    let showInGraph: (() -> Void)?
    let search: () -> Void

    var body: some View {
        Button(action: search) {
            HStack {
                Label(title, systemImage: "number").lineLimit(1)
                Spacer(minLength: 8)
                Text(fileCount, format: .number).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Searches for notes with this tag")
        .contextMenu {
            Button("Search for Tag", systemImage: "magnifyingglass", action: search)
            if let showInGraph { Button("Show in Graph", systemImage: "point.3.connected.trianglepath.dotted", action: showInGraph) }
        }
    }
}
