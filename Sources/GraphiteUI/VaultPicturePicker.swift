/**
 * File: VaultPicturePicker.swift
 * ------------------------------
 * Layer: UI
 * Description: The sheet that picks a picture from the vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import CoreGraphics
import GraphiteCore
import GraphiteApple

/// A picture chosen for a folder, before it is applied; each choice is its own sheet.
final class PickedFolderPicture: Identifiable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}

/// Chooses a picture of the vault by name; recent pictures are listed until something is typed.
struct VaultPicturePicker: View {
    let findPictures: (String) async -> [VaultPath]
    let choose: (VaultPath) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var paths: [VaultPath] = []
    /// The text `paths` were found for, so a query whose answer has not come is not shown as one that found nothing.
    @State private var searchedQuery: String?

    /// What the list says while it is empty.
    enum EmptyState: Equatable {
        /// Nothing typed and no recent picture.
        case promptToType
        /// Something typed, and nothing of that name found.
        case noMatch(String)
        /// Something typed, whose answer has not come yet.
        case searching
    }

    static func emptyState(forQuery query: String, searchedQuery: String?) -> EmptyState {
        guard !query.isEmpty else { return .promptToType }
        return searchedQuery == query ? .noMatch(query) : .searching
    }

    var body: some View {
        NavigationStack {
            List(paths) { path in
                Button {
                    choose(path)
                    dismiss()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(path.name)
                            if !path.parent.rawValue.isEmpty { Text(path.parent.rawValue).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: { Image(systemName: "photo") }
                }
            }
            .overlay {
                if paths.isEmpty {
                    switch Self.emptyState(forQuery: trimmedQuery, searchedQuery: searchedQuery) {
                    case .promptToType: ContentUnavailableView("Find a Picture", systemImage: "photo", description: Text("Type part of its name."))
                    case .noMatch(let text): ContentUnavailableView.search(text: text)
                    case .searching: EmptyView()
                    }
                }
            }
            .searchable(text: $query, prompt: "Find a picture in the vault")
            .navigationTitle("Picture from Vault")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                let searchedText = trimmedQuery
                let foundPaths = await findPictures(searchedText)
                guard !Task.isCancelled else { return }
                paths = foundPaths
                searchedQuery = searchedText
            }
        }
        .sheetMinimumSize(width: 340, height: 450)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
}
