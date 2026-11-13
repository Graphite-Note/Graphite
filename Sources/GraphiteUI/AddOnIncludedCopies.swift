/**
 * File: AddOnIncludedCopies.swift
 * -------------------------------
 * Layer: UI
 * Description: The add-on packs that come with the app: files in its bundle on the Mac, an On-Demand Resources tag
 *              installed with it on the iPad and the iPhone, and which of those the person removed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// The copies of add-on packs that come with the app (`AddOnPackDelivery`), beside the ones Graphite downloads itself
/// (`AddOnPackStore`). A pack in the app's bundle is always there. A pack of an On-Demand Resources tag is used once
/// asked for, and the person can remove it: the use ends, iOS may take the space back, and the removal is remembered
/// on the device, so a pack iOS has not yet taken back is still reported as removed until it is asked for again.
@MainActor
final class AddOnIncludedCopies {
    private let appBundle: Bundle
    /// Nil where the platform has no On-Demand Resources.
    private let makeTagAccess: (@MainActor (String) -> any OnDemandResourcesAccess)?
    private let defaults: UserDefaults
    /// One access per tag, made the first time its pack is asked for.
    private var tagAccesses: [String: any OnDemandResourcesAccess] = [:]

    private static let removedPacksKey = "GraphiteRemovedAddOnPacks"

    /// - Parameter makeTagAccess: Makes the access to a tag's files; nil where the platform has no On-Demand Resources.
    init(appBundle: Bundle, defaults: UserDefaults, makeTagAccess: (@MainActor (String) -> any OnDemandResourcesAccess)?) {
        self.appBundle = appBundle
        self.defaults = defaults
        self.makeTagAccess = makeTagAccess
    }

    /// The app's own: its main bundle, and On-Demand Resources on iOS.
    static func live(defaults: UserDefaults) -> AddOnIncludedCopies {
        #if os(iOS)
        AddOnIncludedCopies(appBundle: .main, defaults: defaults) { tag in BundleResourceRequestAccess(tag: tag) }
        #else
        AddOnIncludedCopies(appBundle: .main, defaults: defaults, makeTagAccess: nil)
        #endif
    }

    /// Whether every file of the pack is in the app's bundle. False for a build without them, such as the package's
    /// tests, which then download the pack as before.
    func isInAppBundle(_ pack: AddOnPack) -> Bool {
        guard pack.delivery.isInAppBundle else { return false }
        return pack.files.allSatisfy { file in bundledLocation(ofFileNamed: file.name) != nil }
    }

    /// Whether the pack comes as an On-Demand Resources tag this platform can ask for.
    func hasTag(_ pack: AddOnPack) -> Bool { tag(of: pack) != nil }

    /// Whether the pack's tag is in use, its files readable.
    func isInUse(_ pack: AddOnPack) -> Bool {
        guard let tag = tag(of: pack) else { return false }
        return tagAccesses[tag]?.isInUse == true
    }

    /// Whether the person removed the pack and has not asked for it since.
    func wasRemoved(_ pack: AddOnPack) -> Bool { removedPackIdentifiers.contains(pack.id) }

    /// Where the pack's file of this name is in the app's bundle or in its tag in use, or nil.
    func location(ofFileNamed name: String, in pack: AddOnPack) -> URL? {
        switch pack.delivery {
        case .downloadOnly: nil
        case .inAppBundle: bundledLocation(ofFileNamed: name)
        case .onDemandResourcesTag(let tag): tagAccesses[tag]?.location(ofFileNamed: name)
        }
    }

    /// Begins using the pack's tag if its files are on the device; returns whether they are. Not for a removed pack:
    /// its files are only used again once it is asked for (`beginUsingAskedFor`).
    func beginUsingIfOnDevice(_ pack: AddOnPack) async -> Bool {
        guard !wasRemoved(pack), let access = access(for: pack) else { return false }
        return await access.beginUsingIfOnDevice()
    }

    /// The pack asked for: it is no longer removed, and its tag is used, the system downloading it when it is not on the
    /// device. Returns false when the system has no copy to give (a build run from Xcode without its host, no
    /// connection to the App Store), and Graphite's own download is what is left.
    func beginUsingAskedFor(_ pack: AddOnPack) async -> Bool {
        setRemoved(false, pack)
        guard let access = access(for: pack) else { return false }
        if await access.beginUsingIfOnDevice() { return true }
        do {
            try await access.beginUsingDownloadingIfNeeded()
            return true
        } catch {
            return false
        }
    }

    /// The person removed the pack: the use of its tag ends, iOS may take the space back, and the removal is kept.
    func remove(_ pack: AddOnPack) {
        guard let access = access(for: pack) else { return }
        access.endUsingAndAllowPurge()
        setRemoved(true, pack)
    }

    private func tag(of pack: AddOnPack) -> String? {
        makeTagAccess == nil ? nil : pack.delivery.onDemandResourcesTag
    }

    private func access(for pack: AddOnPack) -> (any OnDemandResourcesAccess)? {
        guard let tag = tag(of: pack), let makeTagAccess else { return nil }
        if let access = tagAccesses[tag] { return access }
        let made = makeTagAccess(tag)
        tagAccesses[tag] = made
        return made
    }

    private func bundledLocation(ofFileNamed name: String) -> URL? {
        let file = URL(fileURLWithPath: name)
        return appBundle.url(forResource: file.deletingPathExtension().lastPathComponent, withExtension: file.pathExtension)
    }

    private var removedPackIdentifiers: Set<String> { Set(defaults.stringArray(forKey: Self.removedPacksKey) ?? []) }

    private func setRemoved(_ isRemoved: Bool, _ pack: AddOnPack) {
        var identifiers = removedPackIdentifiers
        guard identifiers.contains(pack.id) != isRemoved else { return }
        if isRemoved { identifiers.insert(pack.id) } else { identifiers.remove(pack.id) }
        defaults.set(identifiers.sorted(), forKey: Self.removedPacksKey)
    }
}
