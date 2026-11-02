/**
 * File: OpenWindows.swift
 * -----------------------
 * Layer: UI
 * Description: The windows of the process, for what only one may run at a time and for quitting.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 01/11/2026
 */

import Foundation

/// One window's part in what the windows of the process share: its name, and whether it
/// records or reads aloud. Its workspace makes it and keeps it; the registry holds it weakly,
/// so a window let go of leaves the list by itself.
@MainActor
final class OpenWindow {
    /// The window as its title bar names it: the document it shows and its vault.
    let name: () -> String
    let isRecording: () -> Bool
    let isReadingAloud: () -> Bool
    let stopReadingAloud: () -> Void
    /// Saves every document open in the window, and what plugins' views of files hold, as
    /// quitting does.
    let saveOpenDocuments: () async throws -> Void
    /// Whether what could not be saved is safe from quitting, kept outside the vault. The
    /// argument says whether it may also write copies of PDFs into the vault, which is left
    /// out when the vault's files are not answering.
    let keepUnsavedDocuments: (_ writesPDFCopies: Bool) async -> Bool
    /// Shows a problem in the window, as why Graphite did not quit.
    let presentProblem: (String) -> Void

    init(name: @escaping () -> String, isRecording: @escaping () -> Bool, isReadingAloud: @escaping () -> Bool,
         stopReadingAloud: @escaping () -> Void, saveOpenDocuments: @escaping () async throws -> Void,
         keepUnsavedDocuments: @escaping (_ writesPDFCopies: Bool) async -> Bool,
         presentProblem: @escaping (String) -> Void) {
        self.name = name
        self.isRecording = isRecording
        self.isReadingAloud = isReadingAloud
        self.stopReadingAloud = stopReadingAloud
        self.saveOpenDocuments = saveOpenDocuments
        self.keepUnsavedDocuments = keepUnsavedDocuments
        self.presentProblem = presentProblem
    }
}

/// The windows of the process, for what only one window may run at a time, one recording
/// (one microphone and camera) and one Read Aloud (one audio output and one Now Playing
/// entry), and for quitting, which waits for every window's saves.
@MainActor
final class OpenWindows {
    private struct WeakWindow {
        weak var window: OpenWindow?
    }

    private var windows: [WeakWindow] = []

    /// Every open window, in the order they opened.
    var all: [OpenWindow] { windows.compactMap(\.window) }

    func add(_ window: OpenWindow) {
        windows.removeAll { entry in entry.window == nil || entry.window === window }
        windows.append(WeakWindow(window: window))
    }

    func remove(_ window: OpenWindow) {
        windows.removeAll { entry in entry.window == nil || entry.window === window }
    }

    /// The other window recording, if any.
    func windowRecording(besides window: OpenWindow) -> OpenWindow? {
        all.first { otherWindow in otherWindow !== window && otherWindow.isRecording() }
    }

    /// The other window reading aloud, with a passage loaded or being prepared, if any.
    func windowReadingAloud(besides window: OpenWindow) -> OpenWindow? {
        all.first { otherWindow in otherWindow !== window && otherWindow.isReadingAloud() }
    }
}

/// Why a window cannot start what another window runs, naming that window.
enum OtherWindowActivity: LocalizedError, Equatable {
    case recording(windowName: String)
    case readingAloud(windowName: String)

    var errorDescription: String? {
        switch self {
        case .recording(let windowName): "A recording is running in another window (\(windowName)). Stop it there first."
        case .readingAloud(let windowName): "Read Aloud is playing in another window (\(windowName)). Stop it there to read here."
        }
    }
}
