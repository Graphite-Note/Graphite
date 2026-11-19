/**
 * File: ReadingDiagramSVGExport.swift
 * -----------------------------------
 * Layer: UI
 * Description: A drawn diagram as an SVG file in the note's colors, copied to the pasteboard or saved.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import MermaidDiagrams
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A drawn diagram as a standalone SVG document (`DiagramSVGWriter`, Pele's structure) and the name its file is given.
/// Its colors are written out as the note shows them now, the vault theme's or the system's in the appearance shown, its
/// page filled in the note's background, so it looks the same in Obsidian, a browser or another app; its text escaped,
/// nothing in it a script or a reference outside it. The regular scene is written, whatever the column showed.
struct ReadingDiagramSVGExport: Sendable {
    let document: String
    let fileName: String

    init(prepared: PreparedMermaidDiagram, palette: DiagramPalette, noteName: String?) {
        let writer = DiagramSVGWriter(colors: .palette(palette), identifierPrefix: "graphite-diagram", paintsBackground: true)
        document = writer.document(of: prepared.scene, diagramType: prepared.kind.peleName, title: prepared.accessibility.title,
                                   description: prepared.accessibility.description)
        fileName = Self.fileName(title: prepared.accessibility.title, noteName: noteName)
    }

    var data: Data { Data(document.utf8) }

    /// The longest name kept, in characters, before ".svg": most file systems take 255 bytes.
    static let longestNameLength = 100

    /// The diagram's title (`accTitle`, else its title), else the note's name, else "Diagram", with ".svg"; the
    /// characters a file name cannot hold on the Mac, the iPad or Windows (a folder separator, a colon, control
    /// characters) are dashes, and a name that starts with a dot does not hide the file.
    static func fileName(title: String?, noteName: String?) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let candidates = [title, noteName].compactMap { name in name?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = candidates.first { name in !name.isEmpty } ?? "Diagram"
        var cleaned = String(String.UnicodeScalarView(name.unicodeScalars.map { scalar in forbidden.contains(scalar) ? "-" : scalar }))
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = String(cleaned.prefix(longestNameLength)).trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Diagram" : cleaned) + ".svg"
    }
}

/// What a diagram's menu offers to do with its SVG.
enum ReadingDiagramSVGCommand: CaseIterable, Equatable {
    case copy
    case save

    var title: String {
        switch self {
        case .copy: "Copy as SVG"
        case .save: "Save as SVG…"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        }
    }

    /// The commands a block offers: both for a drawn diagram, none for a source shown with why.
    static func offered(for diagram: ReadingDiagram) -> [ReadingDiagramSVGCommand] {
        guard case .drawn = diagram else { return [] }
        return allCases
    }
}

/// Where a drawn diagram offers its SVG commands.
enum ReadingDiagramSVGCommandsPlacement: Equatable {
    /// In its own context menu (a long press on the iPad, a secondary click on the Mac): the reading view.
    case contextMenu
    /// In the menu of the Live Preview block it is (`RenderedBlockMenuContext`), above Edit Source: a block's own menu
    /// takes the long press and the secondary click from the views inside it.
    case blockMenu
    /// Nowhere: a diagram inside another Live Preview block, whose menu belongs to that block.
    case none
}

extension EnvironmentValues {
    /// The name of the note the reading view or Live Preview shows, which a diagram's SVG file is named after when the
    /// diagram has no title; nil where there is no note.
    @Entry var readingDiagramNoteName: String? = nil
}

extension ReadingDiagramColors {
    /// The colors as a palette of the package, each resolved as `environment` shows it (its appearance), for an SVG
    /// written in the note's colors.
    func palette(in environment: EnvironmentValues) -> DiagramPalette {
        func resolved(_ color: Color) -> CGColor { color.resolve(in: environment).cgColor }
        return DiagramPalette(background: resolved(background), foreground: resolved(foreground), line: resolved(line), surface: resolved(surface),
                              border: resolved(border), series: series.map(resolved), accent: resolved(accent), critical: resolved(critical),
                              muted: resolved(muted), alternateSurface: resolved(alternateSurface))
    }
}

/// Puts a diagram's SVG on the pasteboard and offers its file to save.
@MainActor
enum ReadingDiagramSVGSharing {
    static let svgType = UTType.svg

    #if canImport(UIKit)
    /// On the pasteboard as an SVG image and as its text, so an app that takes pictures and one that takes text both paste it.
    static func copy(_ export: ReadingDiagramSVGExport, to pasteboard: UIPasteboard = .general) {
        pasteboard.setItems([[svgType.identifier: export.data, UTType.utf8PlainText.identifier: export.document]])
    }

    /// The share sheet with the SVG file, whose Save to Files saves it where the person chooses. It is presented from the
    /// window's topmost view controller, as a Live Preview block's view is in no view controller of its own; its file is
    /// written in a folder of its own in the temporary folder and removed once the sheet closes.
    static func save(_ export: ReadingDiagramSVGExport) {
        guard let window = keyWindow, var presenter = window.rootViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Diagram SVG \(UUID().uuidString)", directoryHint: .isDirectory)
        let file = folder.appending(path: export.fileName, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try export.data.write(to: file, options: .atomic)
        } catch {
            let alert = UIAlertController(title: "The SVG could not be made",
                                          message: "Graphite could not write the diagram's file to share. Check that the device has free space.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter.present(alert, animated: !GraphiteMotion.isReduced)
            return
        }
        let shareSheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        shareSheet.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: folder) // Best-effort removal of a temporary copy; the system clears the folder too.
        }
        shareSheet.popoverPresentationController?.sourceView = window
        shareSheet.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        shareSheet.popoverPresentationController?.permittedArrowDirections = []
        presenter.present(shareSheet, animated: !GraphiteMotion.isReduced)
    }

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
    #else
    /// On the pasteboard as an SVG image and as its text, so an app that takes pictures and one that takes text both paste it.
    static func copy(_ export: ReadingDiagramSVGExport, to pasteboard: NSPasteboard = .general) {
        let svgPasteboardType = NSPasteboard.PasteboardType(svgType.identifier)
        pasteboard.clearContents()
        pasteboard.declareTypes([svgPasteboardType, .string], owner: nil)
        pasteboard.setData(export.data, forType: svgPasteboardType)
        pasteboard.setString(export.document, forType: .string)
    }

    /// The save panel, over the key window when there is one, named after the diagram.
    static func save(_ export: ReadingDiagramSVGExport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [svgType]
        panel.nameFieldStringValue = export.fileName
        panel.canCreateDirectories = true
        let window = NSApp.keyWindow
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let location = panel.url else { return }
            do {
                try export.data.write(to: location, options: .atomic)
            } catch {
                // A failed save is said, never passed over.
                let alert = NSAlert(error: error)
                if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }
    #endif
}
