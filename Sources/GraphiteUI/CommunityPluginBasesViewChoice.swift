/**
 * File: CommunityPluginBasesViewChoice.swift
 * ------------------------------------------
 * Layer: UI
 * Description: What a base shows for a view type Graphite does not draw itself: the plugin's view, a wait while
 *              plugins start, an offer to turn plugins on while they are off, or that the type is unsupported.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import SwiftUI

/// Leads to Settings › Community Plugins, where the person turns plugins on for the vault and is
/// asked first about the plugins that would run; given to bases while plugins are off.
struct CommunityPluginsTurnOnOffer {
    let openCommunityPluginSettings: @MainActor () -> Void
}

extension EnvironmentValues {
    /// Set while community plugins are off for the vault on this device, so a base whose view
    /// a plugin may draw says they are off and offers to turn them on; nil while they are on.
    @Entry var communityPluginsTurnOnOffer: CommunityPluginsTurnOnOffer? = nil
}

extension CommunityPluginHost {
    /// The offer for bases while plugins are off for the open vault; nil while they are on, or
    /// with no vault open.
    var turnOnOfferWhilePluginsAreOff: CommunityPluginsTurnOnOffer? {
        guard hostWhilePluginsAreOn == nil, workspace?.currentVaultIdentifier != nil else { return nil }
        return CommunityPluginsTurnOnOffer { [weak self] in self?.requestedSettingsPlugin = "" }
    }
}

/// What a base shows for a view whose type Graphite does not draw (`BaseViewType.unsupported`).
enum CommunityPluginBasesViewChoice: Equatable {
    /// A running plugin registered the type: it draws the view.
    case drawnByPlugin
    /// Plugins are starting and none has registered the type yet.
    case waitingForPlugins
    /// Plugins are off for the vault, so the plugin that may draw the type is not running.
    case pluginsAreOff
    /// Plugins are running and none draws the type.
    case unsupported

    /// - Parameters:
    ///   - host: The vault's plugins while they are on (`hostWhilePluginsAreOn`).
    ///   - turnOnOffer: Present while they are off (`turnOnOfferWhilePluginsAreOff`).
    @MainActor static func choose(viewType: String, host: CommunityPluginHost?, turnOnOffer: CommunityPluginsTurnOnOffer?) -> Self {
        guard let host else { return turnOnOffer == nil ? .unsupported : .pluginsAreOff }
        if host.pluginBasesViews[viewType] != nil { return .drawnByPlugin }
        return host.viewTypeMayStillArrive(viewType) ? .waitingForPlugins : .unsupported
    }
}

/// A base view of a type a community plugin may draw, while community plugins are off.
struct CommunityPluginsOffForBaseView: View {
    let viewType: String
    let offer: CommunityPluginsTurnOnOffer

    static func explanation(viewType: String) -> String {
        "Graphite draws table, cards, list, Kanban and map views itself. \u{201C}\(viewType)\u{201D} views can come from a community plugin, "
            + "and community plugins are off for this vault on this device."
    }

    var body: some View {
        ContentUnavailableView {
            Label("Community Plugins Are Off", systemImage: "puzzlepiece.extension")
        } description: {
            Text(Self.explanation(viewType: viewType))
        } actions: {
            Button("Turn On Community Plugins…") { offer.openCommunityPluginSettings() }
        }
    }
}
