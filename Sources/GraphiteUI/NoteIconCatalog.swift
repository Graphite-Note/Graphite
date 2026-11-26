/**
 * File: NoteIconCatalog.swift
 * ---------------------------
 * Layer: UI
 * Description: The icons of a window's vault by note path, read from the index while the Icons, Covers and Columns
 *              core plugin is on, for the file list, tabs, the quick switcher, links and Library mode.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import Observation
import os
import GraphiteCore
import GraphiteIndex

/// The notes of the open vault that have an icon. Empty in a vault without `icon` properties, where drawing a row
/// costs one empty-dictionary test.
@MainActor @Observable
final class NoteIconCatalog {
    private(set) var iconsByPath: [VaultPath: NoteIcon] = [:]
    /// The emoji icons, for the reading view's links (`NoteIconLinkPrefixes`), made when the icons change.
    private(set) var linkPrefixes = NoteIconLinkPrefixes.none
    private var changeCount = 0

    func icon(of path: VaultPath) -> NoteIcon? {
        iconsByPath.isEmpty ? nil : iconsByPath[path]
    }

    /// Reads the icons again from `index`, or forgets them all without one. Observers are told only when an icon
    /// changed, so an index change that touched no `icon` property redraws nothing.
    func reload(from index: VaultIndex?) async {
        guard let index else { replaceIcons(with: [:]); return }
        do {
            let icons = try await index.noteIcons()
            guard !Task.isCancelled else { return }
            replaceIcons(with: icons)
        } catch {
            // The icons already shown stay: a failed read is not a vault without icons.
            Self.logger.error("Note icons could not be read: \(String(describing: error), privacy: .private)")
        }
    }

    private func replaceIcons(with icons: [VaultPath: NoteIcon]) {
        guard icons != iconsByPath else { return }
        iconsByPath = icons
        changeCount += 1
        linkPrefixes = NoteIconLinkPrefixes(icons: icons, version: changeCount)
    }

    private static let logger = Logger(subsystem: "com.graphite.study", category: "NoteIcons")
}

/// The emoji of the notes whose icon is one, which the reading view puts before the text of links to them. A link's
/// text is drawn as text, so an SF Symbol icon is not shown there.
///
/// Two values are equal when their versions are: a version names one set of icons of one catalog, so comparing it
/// stands for comparing every entry, which a reading configuration is compared by at every update of its pane.
struct NoteIconLinkPrefixes: Equatable, Sendable {
    let emojiByPath: [VaultPath: String]
    let version: Int

    static let none = NoteIconLinkPrefixes(emojiByPath: [:], version: 0)

    init(emojiByPath: [VaultPath: String], version: Int) {
        self.emojiByPath = emojiByPath
        self.version = version
    }

    init(icons: [VaultPath: NoteIcon], version: Int) {
        self.init(emojiByPath: icons.compactMapValues { icon in
            guard case .emoji(let emoji) = icon else { return nil }
            return emoji
        }, version: version)
    }

    nonisolated static func ==(leftPrefixes: NoteIconLinkPrefixes, rightPrefixes: NoteIconLinkPrefixes) -> Bool {
        leftPrefixes.version == rightPrefixes.version
    }
}

extension EnvironmentValues {
    /// The window's note icons; nil while the Icons, Covers and Columns core plugin is off.
    @Entry var noteIcons: NoteIconCatalog? = nil
}

/// The open vault's index and a key that changes whenever its icons may have: another vault, or a change of the
/// index's properties (`WorkspaceModel.structureVersion`).
struct NoteIconSource {
    let index: VaultIndex?
    let reloadKey: String
}

/// The Icons, Covers and Columns core plugin's part of a window: owns the window's `NoteIconCatalog` while the plugin is
/// on and reads it again when `source` says the icons may have changed, and tells the notes to lay callouts out as the
/// plugin does. Off, there is no catalog and no query. `source` is read here rather than by the window's root view,
/// which then does not draw again each time the index changes.
struct PageLookLayer: ViewModifier {
    let isEnabled: Bool
    let source: () -> NoteIconSource
    @State private var catalog: NoteIconCatalog?

    func body(content: Content) -> some View {
        let currentSource = source()
        content
            .environment(\.noteIcons, catalog)
            .environment(\.drawsCalloutLayouts, isEnabled)
            .task(id: "\(isEnabled)|\(currentSource.reloadKey)") {
                guard isEnabled else { catalog = nil; return }
                let shownCatalog = catalog ?? NoteIconCatalog()
                catalog = shownCatalog
                await shownCatalog.reload(from: currentSource.index)
            }
    }
}
