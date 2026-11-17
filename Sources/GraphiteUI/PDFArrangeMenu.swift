/**
 * File: PDFArrangeMenu.swift
 * --------------------------
 * Layer: UI
 * Description: The Arrange menu of a selected picture, text box or shape: Bring to Front, Bring Forward, Send
 *              Backward and Send to Back, those that would not move it dimmed; and Ink to Front and Ink to Back
 *              for the page shown, in the PDF's More menu.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore
#if os(macOS)
import AppKit
#endif

/// What an Arrange menu offers for the page of the selected object: Ink to Front and Ink to Back.
struct PDFInkArrangeOptions {
    let possibleArrangements: Set<PDFArrangement>
    let arrange: (PDFArrangement) -> Void

    /// None, for a drawing's pictures or a page without ink.
    static var none: PDFInkArrangeOptions { PDFInkArrangeOptions(possibleArrangements: []) { _ in } }
}

/// The Arrange menu, as a button of a bar; `PDFArrangeMenuItems` are its items, for a menu of its own.
struct PDFArrangeMenu: View {
    let offeredArrangements: [PDFArrangement]
    let possibleArrangements: Set<PDFArrangement>
    /// What the items name ("Bring Item to Front"), or nil for the bare titles ("Bring to Front").
    var objects: PDFArrangement.Objects?
    var ink = PDFInkArrangeOptions.none
    let arrange: (PDFArrangement) -> Void

    var body: some View {
        Menu("Arrange", systemImage: "square.3.layers.3d") {
            PDFArrangeMenuItems(offeredArrangements: offeredArrangements, possibleArrangements: possibleArrangements, objects: objects, ink: ink,
                                arrange: arrange)
        }
        .disabled(possibleArrangements.isEmpty && ink.possibleArrangements.isEmpty)
    }
}

struct PDFArrangeMenuItems: View {
    var offeredArrangements = PDFArrangement.menuArrangements
    let possibleArrangements: Set<PDFArrangement>
    var objects: PDFArrangement.Objects?
    var ink = PDFInkArrangeOptions.none
    let arrange: (PDFArrangement) -> Void

    var body: some View {
        ForEach(offeredArrangements, id: \.self) { arrangement in
            Button(objects.map(arrangement.title(of:)) ?? arrangement.title, systemImage: arrangement.systemImageName) { arrange(arrangement) }
                .disabled(!possibleArrangements.contains(arrangement))
        }
        // The page's ink as one layer, over or under every object (Docs/PDF-annotation-todo.md, section 2).
        if !ink.possibleArrangements.isEmpty {
            Divider()
            ForEach(PDFArrangement.inkMenuArrangements, id: \.self) { arrangement in
                Button(arrangement.inkTitle, systemImage: "scribble") { ink.arrange(arrangement) }
                    .disabled(!ink.possibleArrangements.contains(arrangement))
            }
        }
    }
}

/// Ink to Front and Ink to Back for the page shown, in the PDF's More menu: the ink is the
/// page's, so the menus of its pictures, text boxes and shapes no longer offer it
/// (Docs/PDF-annotation-todo.md, section 8). Nothing shows on a page without ink or objects.
struct PDFPageInkArrangeMenuItems: View {
    let session: PDFSession

    var body: some View {
        // Read again with each edit, as each arrangement is one.
        let _ = session.changeVersion
        if let page = session.document.page(at: session.currentPageIndex) {
            let possibleArrangements = session.possibleInkArrangements(on: page)
            if !possibleArrangements.isEmpty {
                Section("This Page's Ink") {
                    ForEach(PDFArrangement.inkMenuArrangements, id: \.self) { arrangement in
                        Button(arrangement.inkTitle, systemImage: arrangement.systemImageName) {
                            do { try session.arrangeInk(on: page, arrangement) } catch { session.reportFailedChange(error) }
                        }
                        .disabled(!possibleArrangements.contains(arrangement))
                    }
                }
            }
        }
    }
}

#if os(macOS)
/// What Tools › Arrange acts on: the selected picture, text box or shape of the focused PDF pane.
struct PDFArrangeMenuActions {
    let possibleArrangements: Set<PDFArrangement>
    let arrange: (PDFArrangement) -> Void
    /// Ink to Front and Ink to Back for the selected object's page.
    let ink: PDFInkArrangeOptions
}

extension FocusedValues {
    @Entry var pdfArrangeMenuActions: PDFArrangeMenuActions?
}

/// Tools › Arrange, dimmed while nothing that can be arranged is selected.
struct PDFArrangeCommandsMenu: View {
    let actions: PDFArrangeMenuActions?
    let shortcut: (GraphiteCommand) -> KeyboardShortcut?

    var body: some View {
        Menu("Arrange") {
            ForEach(PDFArrangement.menuArrangements, id: \.self) { arrangement in
                Button(arrangement.title) { actions?.arrange(arrangement) }
                    .keyboardShortcut(arrangement.command.flatMap(shortcut))
                    .disabled(actions?.possibleArrangements.contains(arrangement) != true)
            }
            Divider()
            ForEach(PDFArrangement.inkMenuArrangements, id: \.self) { arrangement in
                Button(arrangement.inkTitle) { actions?.ink.arrange(arrangement) }
                    .disabled(actions?.ink.possibleArrangements.contains(arrangement) != true)
            }
        }
    }
}

extension PDFArrangement {
    /// The menu bar's command, which a shortcut can be given in Settings › Hotkeys.
    var command: GraphiteCommand? {
        switch self {
        case .bringToFront: .bringPDFObjectToFront
        case .bringForward: .bringPDFObjectForward
        case .sendBackward: .sendPDFObjectBackward
        case .sendToBack: .sendPDFObjectToBack
        case .position: nil
        }
    }
}

/// The Arrange items of a right-click menu of a PDF page's object on the Mac.
enum MacPDFArrangeMenuItems {
    static func add(to menu: NSMenu, objects: PDFArrangement.Objects? = nil, possibleArrangements: Set<PDFArrangement>,
                    ink: PDFInkArrangeOptions = .none, arrange: @escaping (PDFArrangement) -> Void) {
        menu.autoenablesItems = false
        // Between the object's own items and these; a picture's menu starts with them, and a menu never opens on a line.
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for arrangement in PDFArrangement.menuArrangements {
            let item = MacPDFPageToolMenuItem(title: objects.map(arrangement.title(of:)) ?? arrangement.title) { arrange(arrangement) }
            item.isEnabled = possibleArrangements.contains(arrangement)
            menu.addItem(item)
        }
        guard !ink.possibleArrangements.isEmpty else { return }
        menu.addItem(.separator())
        for arrangement in PDFArrangement.inkMenuArrangements {
            let item = MacPDFPageToolMenuItem(title: arrangement.inkTitle) { ink.arrange(arrangement) }
            item.isEnabled = ink.possibleArrangements.contains(arrangement)
            menu.addItem(item)
        }
    }
}
#endif
