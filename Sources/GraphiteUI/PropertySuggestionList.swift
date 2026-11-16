/**
 * File: PropertySuggestionList.swift
 * ----------------------------------
 * Layer: UI
 * Description: The suggestions under a Properties panel field while a name, a value or a tag is typed: rows as the
 *              editor's suggestion list draws them, chosen by a tap or with the arrows, Return or Tab; Escape closes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// What a Properties panel field suggests and which row the keyboard has chosen. Each field has one while it is focused.
@MainActor @Observable
final class PropertySuggestionState {
    private(set) var suggestions: [PropertySuggestions.Suggestion] = []
    private(set) var highlightedIndex = 0
    /// The query the person closed with Escape: nothing is suggested again until the text changes.
    private var dismissedQuery: String?
    /// The query the shown suggestions were found for; an answer for an older one is dropped.
    private var currentQuery: String?

    var isShowing: Bool { !suggestions.isEmpty }
    var highlighted: PropertySuggestions.Suggestion? { suggestions.indices.contains(highlightedIndex) ? suggestions[highlightedIndex] : nil }

    /// Finds the suggestions for `query` with `find`, or clears them when the field is not focused.
    func update(query: String, isFocused: Bool, find: () async -> [PropertySuggestions.Suggestion]) async {
        currentQuery = query
        guard isFocused, query != dismissedQuery else { clear(); return }
        if dismissedQuery != nil { dismissedQuery = nil }
        let found = await find()
        guard currentQuery == query else { return }
        suggestions = Array(found.prefix(Self.maximumShownCount))
        highlightedIndex = 0
    }

    func moveHighlight(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        highlightedIndex = (highlightedIndex + offset + suggestions.count) % suggestions.count
    }

    func dismiss(query: String) {
        dismissedQuery = query
        clear()
    }

    func clear() {
        suggestions = []
        highlightedIndex = 0
    }

    /// The rows listed at most under a field.
    static let maximumShownCount = 8
}

/// The rows under a field: the name or value with the typed letters marked, and how many notes use it.
struct PropertySuggestionList: View {
    let state: PropertySuggestionState
    let query: String
    let choose: (PropertySuggestions.Suggestion) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        if state.isShowing {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { offset, suggestion in
                    Button { choose(suggestion) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.systemImage).foregroundStyle(.secondary).frame(width: 18)
                            Text(highlighted(suggestion.text)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(suggestion.countText).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: Self.rowHeight)
                        .background(offset == state.highlightedIndex ? accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(suggestion.text)
                    .accessibilityValue(suggestion.countText)
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .frame(maxWidth: Self.maximumWidth, alignment: .leading)
            .padding(.top, 4)
        }
    }

    /// The text with the letters typed shown in the accent, as the editor's suggestions show them.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !query.isEmpty, let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
              let attributedRange = Range(range, in: attributed) else { return attributed }
        attributed[attributedRange].foregroundColor = accent
        attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
        return attributed
    }

    /// A row a finger can take: 44 points on a touch screen, a menu row's height on the Mac.
    #if canImport(UIKit)
    static let rowHeight: CGFloat = 44
    #else
    static let rowHeight: CGFloat = 26
    #endif
    static let maximumWidth: CGFloat = 360
}

extension View {
    /// The keys a field with suggestions answers: the arrows move the highlight, Tab chooses it, Escape closes the
    /// suggestions without leaving the field. Return chooses it through the field's own submit (`choosesOnSubmit`).
    func propertySuggestionKeys(_ state: PropertySuggestionState, query: String, choose: @escaping (PropertySuggestions.Suggestion) -> Void) -> some View {
        onKeyPress(.downArrow) {
            guard state.isShowing else { return .ignored }
            state.moveHighlight(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard state.isShowing else { return .ignored }
            state.moveHighlight(by: -1)
            return .handled
        }
        .onKeyPress(.tab) {
            guard let highlighted = state.highlighted else { return .ignored }
            choose(highlighted)
            return .handled
        }
        .onKeyPress(.escape) {
            guard state.isShowing else { return .ignored }
            state.dismiss(query: query)
            return .handled
        }
    }
}
