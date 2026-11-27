/**
 * File: NotePresentationLauncher.swift
 * ------------------------------------
 * Layer: UI
 * Description: Start Presentation for a window: the action the Mac's View menu, the note's More › File menu, the
 *              file list and the command palette call, and what shows the presentation on each platform until it
 *              ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// Presents a note as slides: the note in front when `path` is nil, otherwise the note at `path`.
struct NotePresentationAction {
    let start: (_ path: VaultPath?) -> Void
}

extension EnvironmentValues {
    /// Set by `NotePresentationLauncher` around a window while a vault is open and the Slides core plugin is on.
    @Entry var notePresentation: NotePresentationAction? = nil
}

extension FocusedValues {
    /// The same action, for the menu bar's View menu (`GraphiteCommands`).
    @Entry var notePresentation: NotePresentationAction?
}

/// Start Presentation in a note's More › File menu, beside Export to PDF; absent while the Slides core plugin is off.
struct NotePresentationButton: View {
    /// Nil presents the note in front; a path presents that note, read from its file unless it is in front.
    var path: VaultPath? = nil
    @Environment(\.notePresentation) private var notePresentation

    var body: some View {
        if let notePresentation {
            Button("Start Presentation", systemImage: "play.rectangle") { notePresentation.start(path) }
        }
    }
}

/// The command palette's Start Presentation, while a note is in front and the Slides core plugin is on; listed with
/// Export to PDF and Print (`NotePDFPaletteCommands`).
@MainActor
enum NotePresentationPaletteCommand {
    static func commands(hasNoteInFront: Bool, action: NotePresentationAction?, shortcuts: VaultKeyboardShortcuts) -> [PaletteCommand] {
        guard hasNoteInFront, let action else { return [] }
        return [PaletteCommand(id: "start-presentation", command: .startPresentation, systemImage: "play.rectangle") { action.start(nil) }
            .showingShortcut(from: shortcuts.builtInTable)]
    }
}

extension ReadingConfiguration {
    /// The vault's reading settings a presented note's slides are built with.
    @MainActor
    static func presentedSlides(usesStrictLineBreaks: Bool, preferences: GraphitePreferences) -> ReadingConfiguration {
        var configuration = ReadingConfiguration()
        configuration.usesStrictLineBreaks = usesStrictLineBreaks
        configuration.colorsEnabled = preferences.isEnabled(.colors)
        configuration.paletteHexByName = preferences.colorPaletteHexByName
        return configuration
    }
}

/// Starts and shows a window's presentation. The note in front is presented as it is now, edits not yet saved
/// included; another note is read from its file. Nothing is written into the vault.
struct NotePresentationLauncher: ViewModifier {
    /// The Slides core plugin's switch: off, the menus offer no Start Presentation.
    let isEnabled: Bool
    let focusedNote: MarkdownSession?
    let vault: ReadingVault?
    /// The vault's reading settings slides are built with (line breaks, colours, property types).
    let readingConfiguration: ReadingConfiguration
    let appearance: PresentationAppearance
    /// Where the Pencil's choices on slides are kept on this device.
    let deviceDefaults: UserDefaults
    /// The clock the presentation's time and the marks' fading are counted on.
    let clock: any ApplicationClock
    /// The presentation on screen; nil while none is.
    @State private var presentation: NotePresentation?
    @State private var failureMessage: String?
    #if canImport(UIKit)
    @State private var externalDisplays: PresentationExternalDisplays?
    #else
    @State private var macWindows: MacPresentationWindows?
    #endif

    func body(content: Content) -> some View {
        let action = isEnabled ? vault.map { _ in NotePresentationAction { path in Task { await start(path) } } } : nil
        content
            .environment(\.notePresentation, action)
            .focusedSceneValue(\.notePresentation, action)
            #if canImport(UIKit)
            .fullScreenCover(item: $presentation, onDismiss: stopExternalDisplays) { presentation in
                NotePresentationScreen(presentation: presentation, end: endPresentation)
                    // The Pencil's choices are kept where the presentation read them from.
                    .defaultAppStorage(deviceDefaults)
            }
            #endif
            .alert("The note could not be presented", isPresented: Binding(get: { failureMessage != nil },
                                                                           set: { isShown in if !isShown { failureMessage = nil } })) {
                Button("OK") { failureMessage = nil }
            } message: {
                Text(failureMessage ?? "")
            }
    }

    private func start(_ path: VaultPath?) async {
        guard let vault, presentation == nil else { return }
        do {
            let note = try await NotePDFExportPresentation.printedNote(at: path, in: vault, focusedNote: focusedNote)
            var configuration = readingConfiguration
            configuration.declaredPropertyTypes = note.declaredPropertyTypes
            let source = NotePresentationSource(text: note.text, path: note.path, vault: vault, configuration: configuration)
            let started = NotePresentation.started(from: source, clock: clock, pencil: .stored(in: deviceDefaults))
            show(started)
        } catch {
            failureMessage.report(error)
        }
    }

    private func show(_ started: NotePresentation) {
        presentation = started
        #if canImport(UIKit)
        let displays = PresentationExternalDisplays(presentation: started, appearance: appearance)
        displays.start(in: UIApplication.shared)
        externalDisplays = displays
        #else
        let windows = MacPresentationWindows(presentation: started, appearance: appearance, end: endPresentation)
        windows.show(mainScreen: NSApp.keyWindow?.screen)
        macWindows = windows
        #endif
    }

    /// Ends the presentation shown, from its keys or its End button: the note is as it was.
    private func endPresentation() {
        presentation?.end()
        presentation = nil
        #if canImport(UIKit)
        stopExternalDisplays()
        #else
        macWindows?.close()
        macWindows = nil
        #endif
    }

    #if canImport(UIKit)
    private func stopExternalDisplays() {
        externalDisplays?.stop()
        externalDisplays = nil
    }
    #endif
}
