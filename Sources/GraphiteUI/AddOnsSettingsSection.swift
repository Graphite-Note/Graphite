/**
 * File: AddOnsSettingsSection.swift
 * ---------------------------------
 * Layer: UI
 * Description: Settings › General › Add-ons: each pack, its size and state, with Download, Open and Delete.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import SwiftUI
import GraphiteCore

/// Settings › General › Add-ons: each pack Graphite can download or that came with it, its size,
/// and whether it is on this device, with Download or Delete. The Graphite Guide vault, once downloaded,
/// also has Open, which opens the reader's copy of it (`openGuideVault`) without going through the Guide.
struct AddOnsSettingsSection: View {
    @Environment(AddOnLibrary.self) private var addOns: AddOnLibrary?
    /// Opens the reader's copy of the Graphite Guide vault and closes Settings.
    let openGuideVault: () -> Void

    var body: some View {
        if let addOns, !addOns.packs.isEmpty {
            Section {
                ForEach(addOns.packs) { pack in
                    AddOnPackRow(pack: pack, state: addOns.state(of: pack), library: addOns,
                                 open: pack.id == GuideVaultPack.pack?.id ? openGuideVault : nil)
                }
            } header: {
                Text("Add-ons")
            } footer: {
                Text("Extras that come with Graphite or that it downloads the first time a feature needs them. "
                     + "They are kept on this device, outside your vaults. Deleting one frees its space; it downloads again when needed.")
                    .formFooterAlignment()
            }
            .onAppear { addOns.refresh() }
        }
    }
}

/// What a pack's row in Settings offers in each state: Download until it is here, a spinner while it comes, then
/// Open (only for a pack that opens, the Graphite Guide vault) and Delete; nothing for a pack included with the app.
enum AddOnPackAction: Hashable {
    case download, waitForDownload, open, delete

    static func actions(for state: AddOnPackState, canOpen: Bool) -> [AddOnPackAction] {
        switch state {
        case .notDownloaded, .failed: [.download]
        case .checking, .downloading: [.waitForDownload]
        case .downloaded: canOpen ? [.open, .delete] : [.delete]
        case .includedWithApp: []
        }
    }
}

/// One pack. A pack with `open` (the Graphite Guide vault) shows Open beside Delete once downloaded, and asks before
/// deleting, saying that the reader's own copy stays.
private struct AddOnPackRow: View {
    let pack: AddOnPack
    let state: AddOnPackState
    let library: AddOnLibrary
    let open: (() -> Void)?
    @State private var asksBeforeDeleting = false

    private var size: String { ByteCountFormatter.string(fromByteCount: pack.byteCount, countStyle: .file) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                ForEach(AddOnPackAction.actions(for: state, canOpen: open != nil), id: \.self) { action in
                    switch action {
                    case .download: Button("Download") { library.download(pack) }
                    case .waitForDownload: ProgressView().controlSize(.small)
                    case .open: Button("Open") { open?() }
                    case .delete: Button("Delete", role: .destructive, action: delete)
                    }
                }
            }
            .buttonStyle(.borderless)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Delete the \(pack.title)?", isPresented: $asksBeforeDeleting, titleVisibility: .visible) {
            Button("Delete \(size)", role: .destructive) { library.remove(pack) }
        } message: {
            Text("This frees the download. Your own copy of the guide, in Graphite's folder, stays with everything you wrote in it. "
                 + "The guide downloads again the next time you open it.")
        }
    }

    /// Only the Graphite Guide vault asks first, as the reader may take its copy for the download.
    private func delete() {
        if open != nil { asksBeforeDeleting = true } else { library.remove(pack) }
    }

    private var detail: String {
        switch state {
        case .notDownloaded: "\(size), not downloaded"
        case .checking: size
        case .downloading: "Downloading \(size)…"
        case .downloaded: "\(size) on this device"
        case .includedWithApp: "\(size), included with Graphite"
        case .failed(let reason): reason.explanation
        }
    }
}
