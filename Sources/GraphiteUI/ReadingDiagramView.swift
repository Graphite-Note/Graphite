/**
 * File: ReadingDiagramView.swift
 * ------------------------------
 * Layer: UI
 * Description: A mermaid block in the reading view: the prepared diagram painted and placed in the column, or its source with why.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.20
 * Date: 23/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block in the reading view: a diagram drawn natively, painted in the note's colors and
/// centered, scaled down when the column is narrower; or the block's source with why it could not be drawn.
struct ReadingDiagramView: View {
    let diagram: ReadingDiagram
    let textSize: Double
    let root: URL
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    /// Where a drawn diagram offers Copy as SVG and Save as SVG.
    var svgCommandsPlacement: ReadingDiagramSVGCommandsPlacement = .contextMenu

    var body: some View {
        switch diagram {
        case .drawn(let prepared, let source) where prepared.unappliedStatementCount > 0:
            VStack(alignment: .leading, spacing: 6) {
                ReadingPreparedDiagramDrawing(prepared: prepared, source: source, textSize: textSize, svgCommandsPlacement: svgCommandsPlacement)
                // The diagram has styling or click actions that are read and not applied: it may look different from Obsidian's.
                Label("Some styling or click actions in this diagram are not applied here.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .drawn(let prepared, let source):
            ReadingPreparedDiagramDrawing(prepared: prepared, source: source, textSize: textSize, svgCommandsPlacement: svgCommandsPlacement)
        case .unreadable(let source, let failure):
            VStack(alignment: .leading, spacing: 6) {
                ObsidianMarkdownText(markdown: "```mermaid\n" + source + "\n```", root: root, textSize: textSize, navigate: navigate,
                                     scrollToHeading: scrollToHeading)
                Label(failure.explanation, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// A prepared diagram, whatever its type, in the note's colors (`ReadingDiagramScenePainting`), placed in the column
/// (`ReadingScaledDiagram`, its narrow scene laid out again at the column's width), one image for a screen reader with
/// the package's label and value, and its SVG commands.
private struct ReadingPreparedDiagramDrawing: View {
    let prepared: PreparedMermaidDiagram
    let source: ReadingDiagramSource
    let textSize: Double
    let svgCommandsPlacement: ReadingDiagramSVGCommandsPlacement
    @Environment(\.noteTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = ReadingDiagramColors(theme: theme, colorScheme: colorScheme)
        ReadingScaledDiagram(prepared: prepared, source: source, textSize: textSize) { scene in
            ReadingDiagramScene(scene: scene, colors: colors)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(prepared.accessibility.label)
        .accessibilityValue(prepared.accessibility.value)
        .modifier(ReadingDiagramSVGCommands(prepared: prepared, theme: theme, colorScheme: colorScheme, placement: svgCommandsPlacement))
    }
}

/// A scene painted where it is shown: in the reading view on the iPad's and the iPhone's screen as a picture painted away
/// from the main actor (`ReadingDiagramPictures`); on paper, in Live Preview and on the Mac as SwiftUI shapes and text
/// (`ReadingDiagramScenePainting`), which stay vector in a PDF.
private struct ReadingDiagramScene: View {
    let scene: DiagramScene
    let colors: ReadingDiagramColors
    @Environment(\.readingIsPrinted) private var isPrinted
    #if canImport(UIKit)
    @Environment(\.readingDiagramPictures) private var pictures
    #endif

    var body: some View {
        #if canImport(UIKit)
        if let pictures, !isPrinted {
            ReadingDiagramScenePicture(scene: scene, colors: colors, pictures: pictures)
        } else {
            ReadingDiagramScenePainting(scene: scene, colors: colors)
        }
        #else
        ReadingDiagramScenePainting(scene: scene, colors: colors)
        #endif
    }
}

/// Copy as SVG and Save as SVG on a drawn diagram, in the note's colors at the moment the command is chosen: in the
/// diagram's context menu, or in its Live Preview block's menu.
private struct ReadingDiagramSVGCommands: ViewModifier {
    let prepared: PreparedMermaidDiagram
    let theme: NoteThemeStyle?
    let colorScheme: ColorScheme
    let placement: ReadingDiagramSVGCommandsPlacement
    @Environment(\.readingDiagramNoteName) private var noteName
    @Environment(\.renderedBlockMenuContext) private var blockMenuContext
    @Environment(\.readingIsPrinted) private var isPrinted

    /// What the block's menu is told again when the colors it writes change.
    private struct BlockMenuKey: Equatable {
        let theme: NoteThemeStyle?
        let colorScheme: ColorScheme
        let noteName: String?
    }

    func body(content: Content) -> some View {
        switch placement {
        // A printed page has no menu.
        case .contextMenu where !isPrinted:
            content.contextMenu {
                ForEach(ReadingDiagramSVGCommand.allCases, id: \.self) { command in
                    Button(command.title, systemImage: command.systemImage) { perform(command) }
                }
            }
        case .blockMenu:
            content.onChange(of: BlockMenuKey(theme: theme, colorScheme: colorScheme, noteName: noteName), initial: true) {
                let commands = self
                blockMenuContext?.itemsAtPoint = { _ in
                    ReadingDiagramSVGCommand.allCases.map { command in
                        RenderedBlockMenuItem(title: command.title, symbolName: command.systemImage, action: { commands.perform(command) })
                    }
                }
            }
        case .contextMenu, .none:
            content
        }
    }

    /// The SVG in the colors shown, written off the main actor when the command is chosen (a large diagram's document
    /// is many paths), then copied or offered to save.
    private func perform(_ command: ReadingDiagramSVGCommand) {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let palette = ReadingDiagramColors(theme: theme, colorScheme: colorScheme).palette(in: environment)
        let prepared = prepared
        let noteName = noteName
        Task {
            let export = await Task.detached(priority: .userInitiated) {
                ReadingDiagramSVGExport(prepared: prepared, palette: palette, noteName: noteName)
            }.value
            switch command {
            case .copy: ReadingDiagramSVGSharing.copy(export)
            case .save: ReadingDiagramSVGSharing.save(export)
            }
        }
    }
}
