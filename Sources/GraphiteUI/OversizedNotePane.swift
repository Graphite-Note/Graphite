/**
 * File: OversizedNotePane.swift
 * -----------------------------
 * Layer: UI
 * Description: The read-only view of a note too large to edit: a short notice, and its text as plain text, a page at a time.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import SwiftUI

/// Plain text with no Live Preview, on the iPad, the iPhone and the Mac alike. Only the pages on
/// screen hold their text, so the view takes the same memory for a 9 MB note and a 200 MB one.
struct OversizedNotePane: View {
    let note: OversizedNoteDocument
    let editAnyway: () -> Void
    let reload: () -> Void
    /// The page at the top, kept in `note` for when a tab comes back to it.
    @State private var topPageIndex: Int?

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
                .scrollTargetLayout()
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .scrollPosition(id: $topPageIndex, anchor: .top)
            .onAppear { topPageIndex = note.topPageIndex }
            .onChange(of: topPageIndex) { _, newPageIndex in
                if let newPageIndex { note.topPageIndex = newPageIndex }
            }
        }
        // Another document is another file, with its pages to read.
        .id(ObjectIdentifier(note))
    }

    private var notice: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                symbol
                Text(note.notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                reloadButton
                editAnywayButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    symbol
                    Text(note.notice).font(.callout)
                }
                HStack(spacing: 12) {
                    reloadButton
                    editAnywayButton
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12))
    }

    private var symbol: some View {
        Image(systemName: "lock.doc").foregroundStyle(.orange)
    }

    @ViewBuilder private var reloadButton: some View {
        if note.fileChange == .largeStill { Button("Reload", action: reload) }
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
            // Runs as the row appears, and again for another version of the file.
            .task(id: note.versionShown) {
                let pageText: String
                do { pageText = try await note.text(ofPage: pageIndex) } catch { pageText = "This part of the note could not be read." }
                guard !Task.isCancelled else { return }
                // A page's own last line break would show as an empty line before the next page.
                text = pageText.last?.isNewline == true ? String(pageText.dropLast()) : pageText
            }
            .onDisappear { text = nil }
    }
}
