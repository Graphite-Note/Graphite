/**
 * File: AddOnLibrary.swift
 * ------------------------
 * Layer: UI
 * Description: The add-on packs on this device, those that came with the app included, and their downloads.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 13/11/2026
 */

import Foundation
import Observation
import GraphiteCore
import GraphiteApple

/// Where an add-on pack stands on this device.
enum AddOnPackState: Equatable {
    case notDownloaded
    /// Looking whether the copy that came with the app is still on the device, which downloads nothing.
    case checking
    case downloading
    case downloaded
    /// In the app's own bundle, so always here and never removed.
    case includedWithApp
    /// The last download or removal failed, for this reason.
    case failed(AddOnFailure)
}

/// Why a pack could not be downloaded or removed, in terms the person can act on.
enum AddOnFailure: Equatable {
    case noConnection
    /// A file arrived, but not whole or not the one listed, so nothing was kept.
    case damagedFile
    case serverRefused
    case couldNotSave

    var explanation: String {
        switch self {
        case .noConnection: "Graphite could not connect to the internet."
        case .damagedFile: "A downloaded file was damaged, so nothing was kept."
        case .serverRefused: "The server did not send the files."
        case .couldNotSave: "The files could not be saved on this device."
        }
    }
}

/// The add-on packs on this device and their downloads: what Settings › General › Add-ons
/// lists and what a feature asks for when it needs its pack. A pack can come with the app
/// (`AddOnIncludedCopies`: in its bundle on the Mac, an On-Demand Resources tag installed with it
/// on iOS); otherwise, or when that copy is not there, Graphite downloads it, keeping the files with
/// `AddOnPackStore`, which is the truth on disk. One fetch of a pack runs at a time.
@MainActor @Observable
final class AddOnLibrary {
    /// Every pack this build knows, in the order Settings lists them.
    let packs: [AddOnPack]
    private(set) var states: [AddOnPack.ID: AddOnPackState] = [:]
    @ObservationIgnored private let store: AddOnPackStore?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let includedCopies: AddOnIncludedCopies
    @ObservationIgnored private var fetches: [AddOnPack.ID: Task<Void, Never>] = [:]
    /// Packs a feature asked for while Settings was looking for their tag: fetched once that look finds nothing.
    @ObservationIgnored private var askedForDuringCheck: Set<AddOnPack.ID> = []

    /// A library over the packs in `applicationFolders` and those that came with the app, downloading with `session`.
    /// It reads only what is on disk: whether a tag installed with the app is still there is looked at once a pack is
    /// asked for or Settings lists it, so a launch that needs no pack asks the system nothing.
    init(packs: [AddOnPack], applicationFolders: ApplicationFolders, session: URLSession, includedCopies: AddOnIncludedCopies) {
        self.packs = packs
        self.store = try? AddOnPackStore.inApplicationSupport(applicationFolders.applicationSupportFolder)
        self.session = session
        self.includedCopies = includedCopies
        settleStates()
    }

    /// The packs the app ships definitions of, with a download session that keeps no cookies
    /// or cache of its own; what the person removed is remembered in `defaults`.
    static func standard(applicationFolders: ApplicationFolders, defaults: UserDefaults) -> AddOnLibrary {
        AddOnLibrary(packs: [WelcomeTourScreenshotPack.forThisPlatform].compactMap { pack in pack },
                     applicationFolders: applicationFolders, session: URLSession(configuration: .ephemeral),
                     includedCopies: .live(defaults: defaults))
    }

    func state(of pack: AddOnPack) -> AddOnPackState { states[pack.id] ?? .notDownloaded }

    /// Reads again which packs are complete on the device, and looks whether the tags installed with the app that
    /// the person did not remove are still there.
    func refresh() {
        settleStates()
        for pack in packs where fetches[pack.id] == nil && state(of: pack) == .notDownloaded
            && includedCopies.hasTag(pack) && !includedCopies.wasRemoved(pack) {
            states[pack.id] = .checking
            fetches[pack.id] = Task { [weak self] in
                guard let isOnDevice = await self?.includedCopies.beginUsingIfOnDevice(pack), !Task.isCancelled else { return }
                self?.finishCheck(of: pack, isOnDevice: isOnDevice)
            }
        }
    }

    /// Where the pack keeps the file called `name`, or nil until the pack is here.
    func location(ofFileNamed name: String, in pack: AddOnPack) -> URL? {
        guard let file = pack.file(named: name) else { return nil }
        switch state(of: pack) {
        case .downloaded, .includedWithApp:
            return includedCopies.location(ofFileNamed: name, in: pack) ?? store?.location(of: file, in: pack)
        case .notDownloaded, .checking, .downloading, .failed:
            return nil
        }
    }

    /// Fetches the pack unless it is here or already on its way: from the copy that came with the app when it is
    /// still on the device or the system can download it again, otherwise with Graphite's own download.
    func download(_ pack: AddOnPack) {
        guard fetches[pack.id] == nil else {
            if state(of: pack) == .checking { askedForDuringCheck.insert(pack.id) }
            return
        }
        switch state(of: pack) {
        case .downloaded, .includedWithApp, .checking, .downloading: return
        case .notDownloaded, .failed: break
        }
        states[pack.id] = includedCopies.hasTag(pack) ? .checking : .downloading
        fetches[pack.id] = Task { [weak self] in
            guard let outcome = await self?.fetch(pack), !Task.isCancelled else { return }
            self?.finishFetch(of: pack, with: outcome)
        }
    }

    /// Removes the pack's files from the device; a feature that needs them fetches them again. A pack that came
    /// with the app as a tag is given back to the system, which takes its space when it needs it.
    func remove(_ pack: AddOnPack) {
        fetches[pack.id]?.cancel()
        fetches[pack.id] = nil
        askedForDuringCheck.remove(pack.id)
        includedCopies.remove(pack)
        do {
            try store?.remove(pack)
            states[pack.id] = .notDownloaded
        } catch {
            states[pack.id] = .failed(.couldNotSave)
        }
    }

    private func settleStates() {
        for pack in packs where fetches[pack.id] == nil {
            if includedCopies.isInAppBundle(pack) {
                states[pack.id] = .includedWithApp
            } else if includedCopies.isInUse(pack) || store?.isInstalled(pack) == true {
                states[pack.id] = .downloaded
            } else {
                states[pack.id] = states[pack.id].flatMap(Self.keptFailure) ?? .notDownloaded
            }
        }
    }

    private func fetch(_ pack: AddOnPack) async -> AddOnPackState {
        if includedCopies.hasTag(pack), await includedCopies.beginUsingAskedFor(pack) { return .downloaded }
        guard let store, !Task.isCancelled else { return .notDownloaded }
        states[pack.id] = .downloading
        do {
            try await store.install(pack, using: session)
            return .downloaded
        } catch is CancellationError {
            return .notDownloaded
        } catch let urlError as URLError where urlError.code == .cancelled {
            return .notDownloaded
        } catch {
            return .failed(Self.failure(for: error))
        }
    }

    private func finishCheck(of pack: AddOnPack, isOnDevice: Bool) {
        finishFetch(of: pack, with: isOnDevice ? .downloaded : .notDownloaded)
        if askedForDuringCheck.remove(pack.id) != nil, !isOnDevice { download(pack) }
    }

    private func finishFetch(of pack: AddOnPack, with outcome: AddOnPackState) {
        fetches[pack.id] = nil
        states[pack.id] = outcome
    }

    private static func keptFailure(_ state: AddOnPackState) -> AddOnPackState? {
        if case .failed = state { return state }
        return nil
    }

    /// A network error of any kind (no internet, no cellular data, a host or address that cannot be reached, a failed secure
    /// connection) is a failed connection; "could not save" is for the files on this device.
    static func failure(for error: Error) -> AddOnFailure {
        switch error {
        case is URLError:
            .noConnection
        case AddOnPackStore.InstallError.fileDoesNotMatch:
            .damagedFile
        case AddOnPackStore.InstallError.unexpectedResponse:
            .serverRefused
        default:
            .couldNotSave
        }
    }
}
