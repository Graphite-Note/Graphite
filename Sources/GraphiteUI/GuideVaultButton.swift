/**
 * File: GuideVaultButton.swift
 * ----------------------------
 * Layer: UI
 * Description: The Guide's buttons that open the Graphite Guide vault at a note, downloading it first if it is not here.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import SwiftUI
import GraphiteCore

/// Opens the Graphite Guide vault at `note` (`Start here` when nil). The vault is an add-on pack: the first press
/// downloads it, showing its progress here, and opens it once it is here; a failed download says why and offers to try
/// again. Only the pressed button shows the download. The vault opens through its `graphite://guide` link, which reaches a window of notes from the Guide's sheet
/// and from the Mac's Guide window alike; `didOpen` then closes the sheet.
struct GuideVaultButton: View {
    let title: String
    let note: String?
    var freshCopy = false
    var didOpen: () -> Void = {}
    @Environment(AddOnLibrary.self) private var addOns: AddOnLibrary?
    @Environment(\.openURL) private var openURL
    /// Set by a press while the pack downloads, so the vault opens when it arrives.
    @State private var opensWhenDownloaded = false

    private var pack: AddOnPack? { GuideVaultPack.pack }
    private var state: AddOnPackState { pack.flatMap { pack in addOns?.state(of: pack) } ?? .notDownloaded }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: press) {
                Label {
                    Text(showsDownload ? "Downloading the Guide Vault…" : title)
                } icon: {
                    if showsDownload { ProgressView().controlSize(.small) } else { Image(systemName: "books.vertical") }
                }
            }
            .disabled(isFetching || pack == nil || addOns == nil)
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: state) { _, newState in
            guard opensWhenDownloaded, newState == .downloaded else { return }
            opensWhenDownloaded = false
            open()
        }
    }

    private var isFetching: Bool { state == .downloading || state == .checking }
    /// Only the pressed button says the vault is downloading: the Guide shows two of these buttons, and both
    /// saying so read as two downloads. The other keeps its title, disabled, until the vault is here.
    private var showsDownload: Bool { isFetching && opensWhenDownloaded }

    private var footnote: String? {
        guard !freshCopy else { return nil }
        return switch state {
        case .notDownloaded: pack.map { pack in "Downloads \(ByteCountFormatter.string(fromByteCount: pack.byteCount, countStyle: .file)) the first time." }
        case .failed(let failure): failure.explanation + " Try again when you are online."
        case .checking, .downloading, .downloaded: nil
        }
    }

    private func press() {
        guard let pack, let addOns else { return }
        if addOns.downloadedFolder(of: pack) != nil { return open() }
        opensWhenDownloaded = true
        addOns.download(pack)
    }

    private func open() {
        guard let link = VaultURI.guideLink(to: note, freshCopy: freshCopy) else { return }
        didOpen()
        openURL(link)
    }
}
