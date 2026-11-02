/**
 * File: OversizedNotePane.swift
 * -----------------------------
 * Layer: UI
 * Description: The read-only view of a note too large to edit: a short notice, and its text as plain text, a page at a time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import SwiftUI

/// Plain text with no Live Preview, on the iPad, the iPhone and the Mac alike. Only the pages on
/// screen hold their text, so the view takes the same memory for a 9 MB note and a 200 MB one.
struct OversizedNotePane: View {
    let note: OversizedNoteDocument
    let editAnyway: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            notice
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<note.pageCount, id: \.self) { pageIndex in
                        OversizedNotePageRow(note: note, pageIndex: pageIndex)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        // Another version of the file is another document, with its pages to read again.
        .id(ObjectIdentifier(note))
    }

    private var notice: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                symbol
                Text(note.notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                editAnywayButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    symbol
                    Text(note.notice).font(.callout)
                }
                editAnywayButton
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12))
    }

    private var symbol: some View {
        Image(systemName: "lock.doc").foregroundStyle(.orange)
    }

    @ViewBuilder private var editAnywayButton: some View {
        if note.canEditAnyway { Button("Edit Anyway", action: editAnyway) }
    }
}

/// One page of the note, which holds its text only while it is on screen and keeps its height
/// when it is not, so the note does not jump as it is scrolled back.
private struct OversizedNotePageRow: View {
    let note: OversizedNoteDocument
    let pageIndex: Int
    /// Not read yet, or scrolled away.
    @State private var text: String?
    /// A row not read yet takes some room, or the lazy stack would make every row at once.
    @State private var height: CGFloat = 44

    var body: some View {
        Text(text ?? "")
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { newHeight in
                if text != nil { height = newHeight }
            }
            .task {
                let pageText: String
                do { pageText = try await note.text(ofPage: pageIndex) } catch {
                    pageText = "This part of the note could not be read. " + error.localizedDescription
                }
                guard !Task.isCancelled else { return }
                // A page's own last line break would show as an empty line before the next page.
                text = pageText.last?.isNewline == true ? String(pageText.dropLast()) : pageText
            }
            .onDisappear { text = nil }
    }
}
