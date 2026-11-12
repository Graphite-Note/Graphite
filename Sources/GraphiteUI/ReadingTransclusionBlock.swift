/**
 * File: ReadingTransclusionBlock.swift
 * ------------------------------------
 * Layer: UI
 * Description: An embedded note or note section in the reading view: its name, which opens it, above its blocks, with the
 *              accent bar at its left; on paper the name is a label, as a button cannot be drawn into a PDF on the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import SwiftUI
import GraphiteCore

/// An embedded note (`![[Note]]`) or one of its sections (`![[Note#Heading]]`), its blocks
/// drawn as the note's own are.
struct ReadingTransclusionBlock: View {
    let path: VaultPath
    let heading: String?
    let blocks: [RenderedBlock]
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    let openPDF: (VaultPath, Int) -> Void
    @Environment(\.readingTaskContext) private var taskContext
    /// On paper nothing is tapped, and on the Mac a borderless button is an AppKit control,
    /// which a drawing for a PDF shows as a placeholder.
    @Environment(\.readingIsPrinted) private var isPrinted

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPrinted {
                title.foregroundStyle(.tint)
            } else {
                Button { navigate(path.rawValue + (heading.map { "#" + $0 } ?? ""), true) } label: { title }
                    .buttonStyle(.borderless)
            }
            ReadingBlocksView(blocks: blocks, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading, openPDF: openPDF,
                              updateProperties: nil)
                // The embedded note's tasks are ticked in that note.
                .environment(\.readingTaskContext, taskContext.map { context in ReadingTaskContext(note: path, toggle: context.toggle) })
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) { Rectangle().fill(.tint.opacity(0.6)).frame(width: 3) }
    }

    private var title: some View {
        Label(path.stem + (heading.map { " > " + $0 } ?? ""), systemImage: "doc.text").font(.subheadline.weight(.semibold))
    }
}
