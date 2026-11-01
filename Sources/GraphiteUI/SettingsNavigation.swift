/**
 * File: SettingsNavigation.swift
 * ------------------------------
 * Layer: UI
 * Description: Which page Settings opens on, the remembered page, and small parts of its list and its vault-bound pages.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// A page of Settings.
enum SettingsPage: Hashable {
    case general, editor, filesAndLinks, appearance, keyboardShortcuts, corePlugins, communityPlugins
    case plugin(CorePlugin)
    /// A community plugin's own settings tab, by plugin identifier.
    case communityPlugin(String)
}

/// The page Settings was last left on, for as long as the app runs. Every window and every
/// opening of Settings shares one, so Settings comes back to the page the person used.
@MainActor
final class SettingsPageMemory {
    private(set) var lastPage: SettingsPage?

    func remember(_ page: SettingsPage?) {
        guard let page else { return }
        lastPage = page
    }
}

/// What Settings shows when it opens. Where the list and a page sit side by side (iPad, Mac)
/// the list is there and the page beside it is the one the person used last, General the
/// first time. On a narrow screen (iPhone) the list is all there is until a row is tapped.
enum SettingsOpening {
    /// The page shown beside the list before the person picks one, or nil on a narrow screen.
    static func openingPage(remembered: SettingsPage?, isNarrowScreen: Bool, isAvailable: (SettingsPage) -> Bool) -> SettingsPage? {
        guard !isNarrowScreen else { return nil }
        if let remembered, isAvailable(remembered) { return remembered }
        return .general
    }
}

/// The labels of the Settings list. At accessibility text sizes the icon is left out, so a
/// name such as "Appearance" has the whole row and is not broken in the middle of the word.
struct SettingsRowLabelStyle: LabelStyle {
    let showsIcon: Bool

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if showsIcon { Label(configuration) } else { configuration.title }
    }
}

/// What a vault-bound Settings page says while no vault is open, so nothing typed or chosen
/// there is lost without a word. `what` completes "its …", as "template settings".
struct SettingsNeedAVault: View {
    let what: String

    var body: some View {
        Section { Text("Open a vault to change its \(what).").foregroundStyle(.secondary) }
    }
}
