/**
 * File: OnDemandResourcesAccess.swift
 * -----------------------------------
 * Layer: Apple
 * Description: The files of one On-Demand Resources tag: whether they are on the device, asking the system for them,
 *              where each file is while they are in use, and giving their space back.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// The files of one On-Demand Resources tag of the app. A tag among the App Store's initial install tags is installed
/// with the app, from the App Store and from TestFlight; the system may take its space back once the app no longer
/// uses it, and downloads it again when the app asks. The app uses the files between a successful begin and
/// `endUsingAndAllowPurge`; outside that, `location` is nil even when the files are still on the device.
///
/// The live access is `BundleResourceRequestAccess` on iOS; macOS apps have no On-Demand Resources. Tests give one
/// over a folder of their own.
@MainActor
public protocol OnDemandResourcesAccess: AnyObject {
    /// Whether a begin succeeded and the files are in use.
    var isInUse: Bool { get }
    /// Begins using the files if they are on the device now, downloading nothing; returns whether they are.
    func beginUsingIfOnDevice() async -> Bool
    /// Begins using the files, the system downloading them first if they are not on the device. Throws when it has none
    /// to give: a build without the tag, no connection to the App Store, or no room.
    func beginUsingDownloadingIfNeeded() async throws
    /// Where the file of this name is while the files are in use, or nil.
    func location(ofFileNamed name: String) -> URL?
    /// Ends the use of the files and tells the system that their space may be taken back before any other tag's.
    func endUsingAndAllowPurge()
}

#if os(iOS)
/// The tag's files through `NSBundleResourceRequest`, which iOS 27 deprecates in favour of Background Assets: Apple
/// hosts those asset packs in App Store Connect and they need a download extension, while an initial install tag is
/// part of the app's own upload (`Docs/App-size-todo.md`, section 2). The deprecation is ignored here only.
@diagnose(DeprecatedDeclaration, as: ignored, reason: "On-Demand Resources is chosen over Background Assets in Docs/App-size-todo.md, section 2.")
@MainActor
public final class BundleResourceRequestAccess: OnDemandResourcesAccess {
    private let tag: String
    private let bundle: Bundle
    /// The request of the current use; one request serves one successful begin, so each use after an end makes its own.
    private var request: NSBundleResourceRequest?
    public private(set) var isInUse = false

    /// Most kept of the tags not in use while the person keeps the files; least kept once they removed them.
    private static let keptPreservationPriority = 1.0
    private static let removedPreservationPriority = 0.0

    public init(tag: String, bundle: Bundle = .main) {
        self.tag = tag
        self.bundle = bundle
    }

    public func beginUsingIfOnDevice() async -> Bool {
        guard !isInUse else { return true }
        let request = currentRequest()
        let isOnDevice = await withCheckedContinuation { continuation in
            request.conditionallyBeginAccessingResources { isAvailable in continuation.resume(returning: isAvailable) }
        }
        guard isOnDevice else { return false }
        return markInUse(request)
    }

    public func beginUsingDownloadingIfNeeded() async throws {
        guard !isInUse else { return }
        let request = currentRequest()
        // Asked for by a page on screen, not ahead of time.
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            request.beginAccessingResources { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        guard markInUse(request) else { throw CancellationError() }
    }

    public func location(ofFileNamed name: String) -> URL? {
        guard isInUse, let request else { return nil }
        let file = URL(fileURLWithPath: name)
        return request.bundle.url(forResource: file.deletingPathExtension().lastPathComponent, withExtension: file.pathExtension)
    }

    public func endUsingAndAllowPurge() {
        if isInUse { request?.endAccessingResources() }
        request = nil
        isInUse = false
        bundle.setPreservationPriority(Self.removedPreservationPriority, forTags: [tag])
    }

    private func currentRequest() -> NSBundleResourceRequest {
        if let request { return request }
        let made = NSBundleResourceRequest(tags: [tag], bundle: bundle)
        request = made
        return made
    }

    /// Marks the files in use by `request`, unless the use ended while it waited: that request's access ends at once
    /// and false is returned.
    private func markInUse(_ request: NSBundleResourceRequest) -> Bool {
        guard request === self.request else {
            request.endAccessingResources()
            return false
        }
        isInUse = true
        bundle.setPreservationPriority(Self.keptPreservationPriority, forTags: [tag])
        return true
    }
}
#endif
