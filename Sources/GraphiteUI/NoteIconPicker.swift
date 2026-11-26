/**
 * File: NoteIconPicker.swift
 * --------------------------
 * Layer: UI
 * Description: The note's Icon… sheet: the symbols that have a Lucide twin for Obsidian, the system's emoji picker
 *              and Remove Icon, laid out as the folder popover is.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// What the Icon… sheet starts from: the note's icon when the sheet opened.
struct NoteIconPickerRequest: Identifiable {
    let id = UUID()
    let currentIcon: NoteIcon?
}

/// Shows the Icon… sheet for a request, and writes the icon chosen into the note, reporting a note whose frontmatter
/// cannot be rewritten.
struct NoteIconPickerPresentation: ViewModifier {
    @Binding var request: NoteIconPickerRequest?
    let setIcon: (NoteIcon?) throws -> Void
    let report: (any Error) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $request) { shownRequest in
            NoteIconPicker(currentIcon: shownRequest.currentIcon) { icon in
                do { try setIcon(icon) } catch { report(error) }
            }
        }
    }
}

/// A grid of the paired symbols (`NoteIconSymbols`), then Remove Icon and Emoji across the bottom. Choosing writes the
/// icon and closes the sheet.
struct NoteIconPicker: View {
    let currentIcon: NoteIcon?
    let choose: (NoteIcon?) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let symbolCellPoints: CGFloat = 40
    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 12) {
            Text("Icon").font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.symbolCellPoints), spacing: 4)], spacing: 4) {
                    ForEach(NoteIconSymbols.pairings, id: \.systemName) { pairing in symbolButton(pairing) }
                }
            }
            .frame(maxHeight: 260)
            Divider()
            HStack(spacing: 8) {
                Button { pick(nil) } label: {
                    Text("Remove Icon").foregroundStyle(currentIcon == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary)).bottomButtonLabel()
                }
                .disabled(currentIcon == nil)
                EmojiInputButton(currentEmoji: currentEmoji) { emoji in pick(.emoji(emoji)) }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: Self.width)
        .presentationDetents([.medium])
    }

    private var currentEmoji: String? {
        guard case .emoji(let emoji) = currentIcon else { return nil }
        return emoji
    }

    private func symbolButton(_ pairing: NoteIconSymbols.Pairing) -> some View {
        let systemName = pairing.systemName
        let isChosen = currentIcon == .symbol(systemName: systemName)
        return Button { pick(.symbol(systemName: systemName)) } label: {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .frame(width: Self.symbolCellPoints, height: Self.symbolCellPoints)
                .background(isChosen ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.spokenName(ofLucideName: pairing.lucideName))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// A Lucide name in words, as VoiceOver reads it: `GraduationCap` as "Graduation Cap".
    static func spokenName(ofLucideName lucideName: String) -> String {
        var words = ""
        for character in lucideName {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words
    }

    private func pick(_ icon: NoteIcon?) {
        choose(icon)
        dismiss()
    }
}
