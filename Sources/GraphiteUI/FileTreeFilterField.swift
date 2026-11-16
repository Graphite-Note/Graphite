/**
 * File: FileTreeFilterField.swift
 * -------------------------------
 * Layer: UI
 * Description: The Files panel's filter field above the tree, what the tree says while it filters, and the matched part
 *              of a name highlighted in a row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// The field at the top of the Files panel that narrows the tree to the folders and files whose name holds what is
/// typed, as Obsidian's file explorer filter does: a magnifier, "Filter", and a clear button at its end once it holds
/// text. Escape empties it too. The sidebar's search field above, with its full-text results, is a different thing.
struct FileTreeFilterField: View {
    @Bindable var filter: FileTreeFilter
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter", text: $filter.text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .focused($isFocused)
                .onKeyPress(.escape) {
                    guard !filter.text.isEmpty else { return .ignored }
                    filter.clear()
                    return .handled
                }
                #if os(macOS)
                // The Mac's field editor takes Escape as Cancel before a key press reaches the field.
                .onExitCommand { filter.clear() }
                #endif
                .accessibilityLabel("Filter Files")
            if !filter.text.isEmpty {
                Button("Clear Filter", systemImage: "xmark.circle.fill") { filter.clear() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear Filter")
            }
        }
        .interfaceFont(.body)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        // A command asked for the field before it showed (the Files panel was not chosen), or while it shows.
        .onChange(of: filter.focusRequest, initial: true) {
            if filter.takePendingFocus() { isFocused = true }
        }
        .onChange(of: isFocused) { filter.isFieldFocused = isFocused }
    }
}

/// Reads the vault's names for the filter while it is in use, again when the vault, its files or the sort order change,
/// and shows the folder chosen while filtering once the filter is cleared.
struct FileTreeFilterLoading: ViewModifier {
    let filter: FileTreeFilter
    /// Whether the tree shows, so its status shows: not over the other panels' lists.
    let isTreeShown: Bool
    /// Changes when the names to read change: another vault, files added or removed, a folder listed, the sort order.
    let namesVersion: String
    let fileEntries: @Sendable () async throws -> [VaultEntry]
    let listedEntries: () -> [VaultEntry]
    let sortOrder: FileSortOrder
    let revealFolder: (VaultPath) -> Void

    func body(content: Content) -> some View {
        content
            .task(id: "\(filter.needsNameIndex)|\(sortOrder.rawValue)|\(namesVersion)") {
                await filter.loadNameIndex(fileEntries: fileEntries, listedEntries: filter.needsNameIndex ? listedEntries() : [], sortOrder: sortOrder)
            }
            .onChange(of: filter.isFiltering) { _, isFiltering in
                guard !isFiltering, let folder = filter.takeChosenFolder() else { return }
                revealFolder(folder)
            }
            .overlay { if isTreeShown { FileTreeFilterStatus(filter: filter) } }
    }
}

/// What the tree says in place of rows while it filters: that the names are being read, or that none matched.
private struct FileTreeFilterStatus: View {
    let filter: FileTreeFilter

    var body: some View {
        if filter.isFiltering {
            if filter.result == nil {
                ProgressView().controlSize(.small)
            } else if filter.result?.matchCount == 0 {
                Text("No Matching Files or Folders")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}

/// A name with the part the filter matched marked in the accent color, as search marks its matches.
enum FileTreeFilterHighlight {
    static func highlighted(_ name: String, matching text: String, accent: Color) -> AttributedString {
        var attributedName = AttributedString(name)
        guard let matchedRange = VaultNameMatching.matchedRange(of: text, in: name),
              let lowerBound = AttributedString.Index(matchedRange.lowerBound, within: attributedName),
              let upperBound = AttributedString.Index(matchedRange.upperBound, within: attributedName) else { return attributedName }
        attributedName[lowerBound..<upperBound].backgroundColor = accent.opacity(0.28)
        return attributedName
    }
}
