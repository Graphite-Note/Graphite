/**
 * File: SidebarSearchEmptyState.swift
 * -----------------------------------
 * Layer: UI
 * Description: What the sidebar's search list says while it has no result to show.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI

/// What the sidebar's search says in place of results: that a query is running, why it cannot
/// run, that the vault is still being read, or that nothing matched. Every other list of the
/// vault (tags, properties, the graph, the maps) already says when the index is still being built.
enum SidebarSearchEmptyState: Equatable {
    case searching
    case problem(String)
    case stillReadingVault
    case noMatches

    /// - Parameters:
    ///   - queryProblem: Why the query cannot run, such as an invalid regular expression.
    ///   - isSearching: Whether the results shown are not yet for the query in the field: the
    ///     typing pause, or the search itself, is still running.
    ///   - isIndexUsable: Whether the index has finished a scan, now or in an earlier launch.
    static func state(queryProblem: String?, isSearching: Bool, isIndexUsable: Bool) -> SidebarSearchEmptyState {
        if let queryProblem { return .problem(queryProblem) }
        if isSearching { return .searching }
        return isIndexUsable ? .noMatches : .stillReadingVault
    }

    var message: String {
        switch self {
        case .searching: "Searching…"
        case .problem(let problem): problem
        case .stillReadingVault: "Still reading the vault; results may be incomplete."
        case .noMatches: "No matches"
        }
    }
}

/// The one row the sidebar's search list shows while it has no result.
struct SidebarSearchEmptyRow: View {
    let state: SidebarSearchEmptyState

    var body: some View {
        HStack(spacing: 8) {
            if state == .searching { ProgressView().controlSize(.small) }
            Text(state.message)
        }
        .foregroundStyle(.secondary)
    }
}
