/**
 * File: ColorsSettingsPage.swift
 * ------------------------------
 * Layer: UI
 * Description: Settings > Colors: the palette notes and the Pencil tools offer, and the highlighter colors.
 *
 * Authors: Félix Chevalier
 * Version: 0.4
 * Date: 02/11/2026
 */

import SwiftUI
import GraphiteCore

struct ColorsSettingsPage: View {
    @Bindable var preferences: GraphitePreferences
    @State private var palettePendingRestore: RestorablePalette?

    /// A palette that "Restore Default" replaces, after the person agrees.
    private enum RestorablePalette: Identifiable {
        case notes, highlighter
        var id: Self { self }
        var title: String { self == .notes ? "Replace your palette with the default colors?" : "Replace your highlighter colors with the default ones?" }
        var buttonTitle: String { self == .notes ? "Restore Default Palette" : "Restore Default Highlighter Colors" }
        var message: String {
            switch self {
            case .notes: "The colors you added, renamed or changed are removed from this device, also from the Pencil's Favorite Colors. A note that names one "
                + "of them, as in ~={name}text=~, then shows the default color of that name, or none. This cannot be undone."
            case .highlighter: "The colors you added, renamed or changed are removed from this device. This cannot be undone."
            }
        }
    }

    private func isDefault(_ palette: [PaletteColor], _ defaultPalette: [PaletteColor]) -> Bool {
        palette.map { color in [color.name, color.hex] } == defaultPalette.map { color in [color.name, color.hex] }
    }

    /// A visible way to remove a color, since a swipe is the only other and a Mac row has none.
    private func removeButton(for color: PaletteColor, from palette: Binding<[PaletteColor]>) -> some View {
        Button("Remove \(color.name.isEmpty ? "Color" : color.name)", systemImage: "minus.circle") {
            palette.wrappedValue.removeAll { paletteColor in paletteColor.id == color.id }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
        #if canImport(UIKit)
        .frame(minWidth: 44, minHeight: 44)
        #endif
    }

    /// Moves a color one place, for people who cannot drag rows (the Mac's Form, VoiceOver).
    @ViewBuilder private func moveButtons(for color: PaletteColor, in palette: Binding<[PaletteColor]>) -> some View {
        if let index = palette.wrappedValue.firstIndex(where: { paletteColor in paletteColor.id == color.id }) {
            Button("Move Up", systemImage: "arrow.up") { palette.wrappedValue.move(fromOffsets: [index], toOffset: index - 1) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "arrow.down") { palette.wrappedValue.move(fromOffsets: [index], toOffset: index + 2) }
                .disabled(index == palette.wrappedValue.count - 1)
        }
    }

    var body: some View {
        Form {
            notesPaletteSection
            highlighterPaletteSection
        }
        .navigationTitle("Colors")
        #if canImport(UIKit)
        // Rows are dragged to a new place only in edit mode, which nothing else enters. On the
        // bar itself: a secondary action hides in the "…" menu, and on the leading side its
        // "Done" is not beside the one that closes Settings.
        .toolbar { ToolbarItem(placement: .topBarLeading) { EditButton() } }
        #endif
        .confirmationDialog(palettePendingRestore?.title ?? "", isPresented: Binding(get: { palettePendingRestore != nil }, set: { isPresented in
            if !isPresented { palettePendingRestore = nil }
        }), titleVisibility: .visible, presenting: palettePendingRestore) { palette in
            Button(palette.buttonTitle, role: .destructive) {
                switch palette {
                case .notes: preferences.colorPalette = PaletteColor.defaultPalette
                case .highlighter: preferences.highlighterPalette = PaletteColor.defaultHighlighterPalette
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { palette in
            Text(palette.message)
        }
    }

    private var notesPaletteSection: some View {
        Section {
            ForEach($preferences.colorPalette) { $color in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        ColorPicker("Color", selection: Binding(get: { Color(graphiteHex: color.hex) ?? .red }, set: { newColor in
                            if let hex = newColor.sRGBHex { color.hex = hex }
                        }), supportsOpacity: false)
                        .labelsHidden()
                        TextField("Name", text: $color.name)
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                        Text(color.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                        removeButton(for: color, from: $preferences.colorPalette)
                    }
                    if let problem = PaletteColorNames.problem(with: color, in: preferences.colorPalette) {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                }
                .contextMenu { moveButtons(for: color, in: $preferences.colorPalette) }
            }
            .onDelete { offsets in preferences.colorPalette.remove(atOffsets: offsets) }
            .onMove { offsets, destination in preferences.colorPalette.move(fromOffsets: offsets, toOffset: destination) }
            Button("Add Color", systemImage: "plus") {
                preferences.colorPalette.append(PaletteColor(name: PaletteColorNames.unusedName(in: preferences.colorPalette), hex: "#888888"))
            }
            Button("Restore Default Palette", systemImage: "arrow.counterclockwise") { palettePendingRestore = .notes }
                .disabled(isDefault(preferences.colorPalette, PaletteColor.defaultPalette))
        } header: {
            Text("Palette")
        } footer: {
            Text("Format › Color writes the hex color, as the Colors plugin for Obsidian does (`~={#e93147}text=~`), so notes look the same in both "
                + "apps. A note written with a name, as in `~={red}text=~`, takes the color of that name here, so renaming or removing a color "
                + "changes it.\n\nThe same colors are the Favorite Colors of the Pencil tools, for drawings and PDFs. A highlighter has its own, "
                + "below.")
                .formFooterAlignment()
        }
    }

    private var highlighterPaletteSection: some View {
        Section {
            ForEach($preferences.highlighterPalette) { $color in
                HStack(spacing: 12) {
                    ColorPicker("Color", selection: Binding(get: { Color(graphiteHex: color.hex) ?? .yellow }, set: { newColor in
                        if let hex = newColor.sRGBHex { color.hex = hex }
                    }), supportsOpacity: false)
                    .labelsHidden()
                    TextField("Name", text: $color.name)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    Text(color.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                    removeButton(for: color, from: $preferences.highlighterPalette)
                }
                .contextMenu { moveButtons(for: color, in: $preferences.highlighterPalette) }
            }
            .onDelete { offsets in preferences.highlighterPalette.remove(atOffsets: offsets) }
            .onMove { offsets, destination in preferences.highlighterPalette.move(fromOffsets: offsets, toOffset: destination) }
            Button("Add Color", systemImage: "plus") {
                preferences.highlighterPalette.append(PaletteColor(name: PaletteColorNames.unusedName(in: preferences.highlighterPalette), hex: "#f6d743"))
            }
            Button("Restore Default Highlighter Colors", systemImage: "arrow.counterclockwise") { palettePendingRestore = .highlighter }
                .disabled(isDefault(preferences.highlighterPalette, PaletteColor.defaultHighlighterPalette))
        } header: {
            Text("Highlighter")
        } footer: {
            Text("The colors the Pencil tools offer while a highlighter is in use, in place of the palette above. On a PDF page, a highlighter "
                + "stroke covers the text under it: to keep the text readable, lower the highlighter's opacity in its options, or select the text and "
                + "choose Highlight. Notes do not use these colors.")
                .formFooterAlignment()
        }
    }
}

/// Which palette names a note can refer to, as in `~={red}text=~`.
enum PaletteColorNames {
    /// Why notes cannot use this color's name, or nil when they can.
    static func problem(with color: PaletteColor, in palette: [PaletteColor]) -> String? {
        let name = color.name
        if name.isEmpty { return "Name this color to use it in notes and menus." }
        if name.contains(where: { character in character.isWhitespace || character == "}" }) { return "Notes cannot use a name with spaces or “}”." }
        if TextColorMarkup.canonicalHex(name) != nil { return "Notes read this name as a hex color, not as this color." }
        if palette.first(where: { paletteColor in paletteColor.name == name })?.id != color.id { return "Another color above has this name, and notes use that one." }
        return nil
    }

    /// A name no color in the palette has yet.
    static func unusedName(in palette: [PaletteColor]) -> String {
        let usedNames = Set(palette.map(\.name))
        var number = palette.count + 1
        while usedNames.contains("color-\(number)") { number += 1 }
        return "color-\(number)"
    }
}
