/**
 * File: AddOnIncludedCopiesTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Add-on packs that come with the app: a tag installed with it is used without a download, a removed one
 *              is reported removed across launches and asked for again, a missing one is downloaded, and a pack in the
 *              app's bundle is included and cannot be removed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import CryptoKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner, 2026-11-12: the welcome tour's pictures are there when Graphite is first installed, and can be deleted
/// later (`Docs/App-size-todo.md`, section 2). On iOS they are an On-Demand Resources tag installed with the app; the
/// Mac package has no On-Demand Resources, so these tests give the library a tag over a folder of their own
/// (`FolderTagAccess`), whose begins and ends they count, and a "server" folder for Graphite's own download.
@MainActor
final class AddOnIncludedCopiesTests: XCTestCase {
    private var device: IsolatedDeviceState!
    private var folders: URL!
    private var server: URL!
    private var tagFolder: URL!
    private var tagAccess: FolderTagAccess!

    override func setUp() async throws {
        device = try IsolatedDeviceState.make(prefix: "AddOnIncludedCopies", for: self)
        folders = try TemporaryVault.make(prefix: "AddOnIncludedCopiesFolders", for: self).root
        server = try TemporaryVault.make(prefix: "AddOnIncludedCopiesServer", for: self).root
        tagFolder = try TemporaryVault.make(prefix: "AddOnIncludedCopiesTag", for: self).root
        tagAccess = FolderTagAccess(folder: tagFolder)
    }

    /// A pack of one picture, served for Graphite's download and, as the tag's file, by the tag.
    private func pack(delivery: AddOnPackDelivery) throws -> AddOnPack {
        let data = Data("tour picture".utf8)
        try data.write(to: server.appendingPathComponent("Picture-light.jpg"))
        try data.write(to: tagFolder.appendingPathComponent("Picture-light.jpg"))
        let hash = SHA256.hash(data: data).map { byte in String(format: "%02x", byte) }.joined()
        return AddOnPack(id: "tour-pictures", title: "Tour Pictures", revision: "first", baseAddress: server,
                         files: [AddOnFile(name: "Picture-light.jpg", byteCount: Int64(data.count), sha256: hash)], delivery: delivery)
    }

    /// A library as one launch of the app makes it: the same device's folders and preferences each time.
    private func launchLibrary(with pack: AddOnPack, appBundle: Bundle = .main) -> AddOnLibrary {
        let access = tagAccess!
        let copies = AddOnIncludedCopies(appBundle: appBundle, defaults: device.preferences) { _ in access }
        return AddOnLibrary(packs: [pack], applicationFolders: .temporary(below: folders), session: URLSession(configuration: .ephemeral),
                            includedCopies: copies)
    }

    private func storeFolder(of pack: AddOnPack) throws -> URL {
        try AddOnPackStore.inApplicationSupport(ApplicationFolders.temporary(below: folders).applicationSupportFolder).folder(of: pack)
    }

    private func waitForState(_ state: AddOnPackState, of pack: AddOnPack, in library: AddOnLibrary) async throws {
        try await waitUntil("the pack is \(state)") { library.state(of: pack) == state }
    }

    func testATagInstalledWithTheAppIsUsedWithoutADownload() async throws {
        let pack = try pack(delivery: .onDemandResourcesTag("TourPictures"))
        let library = launchLibrary(with: pack)
        XCTAssertEqual(library.state(of: pack), .notDownloaded)
        XCTAssertEqual(tagAccess.beginCount, 0, "A launch asks the system nothing until a pack is needed.")

        library.download(pack)
        XCTAssertEqual(library.state(of: pack), .checking, "Looking on the device, not downloading.")
        try await waitForState(.downloaded, of: pack, in: library)

        XCTAssertEqual(library.location(ofFileNamed: "Picture-light.jpg", in: pack), tagFolder.appendingPathComponent("Picture-light.jpg"))
        XCTAssertEqual(tagAccess.downloadCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try storeFolder(of: pack).path), "Graphite downloaded nothing.")
    }

    func testSettingsLooksForTheTagAndShowsItOnTheDevice() async throws {
        let pack = try pack(delivery: .onDemandResourcesTag("TourPictures"))
        let library = launchLibrary(with: pack)

        library.refresh()
        try await waitForState(.downloaded, of: pack, in: library)

        XCTAssertEqual(tagAccess.beginCount, 1)
        XCTAssertNotNil(library.location(ofFileNamed: "Picture-light.jpg", in: pack))
    }

    /// The tour opened from Settings while Settings still looks for the tag: once the look finds nothing, it is fetched.
    func testAPackAskedForWhileSettingsLooksForItsTagIsFetchedOnceTheLookFindsNothing() async throws {
        let pack = try pack(delivery: .onDemandResourcesTag("TourPictures"))
        tagAccess.isOnDevice = false
        let library = launchLibrary(with: pack)

        library.refresh()
        XCTAssertEqual(library.state(of: pack), .checking)
        library.download(pack)
        try await waitForState(.downloaded, of: pack, in: library)

        XCTAssertEqual(tagAccess.downloadCount, 1, "The system downloaded the tag the tour asked for.")
    }

    func testARemovedTagIsReportedRemovedAfterARelaunchAndAskedForAgain() async throws {
        let pack = try pack(delivery: .onDemandResourcesTag("TourPictures"))
        let library = launchLibrary(with: pack)
        library.download(pack)
        try await waitForState(.downloaded, of: pack, in: library)

        library.remove(pack)
        XCTAssertEqual(library.state(of: pack), .notDownloaded)
        XCTAssertEqual(tagAccess.purgeAllowedCount, 1, "The use ends and the system may take the space back.")
        XCTAssertNil(library.location(ofFileNamed: "Picture-light.jpg", in: pack))

        // iOS has not taken the files back yet, but they stay removed: Settings does not show them on the device again.
        let relaunched = launchLibrary(with: pack)
        relaunched.refresh()
        XCTAssertEqual(relaunched.state(of: pack), .notDownloaded)
        XCTAssertEqual(tagAccess.beginCount, 1, "A removed tag is not looked for.")

        relaunched.download(pack)
        try await waitForState(.downloaded, of: pack, in: relaunched)
        XCTAssertEqual(tagAccess.beginCount, 2, "Asked for again, the tag is used again.")
        XCTAssertNotNil(relaunched.location(ofFileNamed: "Picture-light.jpg", in: pack))
        let launchedAfterThat = launchLibrary(with: pack)
        launchedAfterThat.refresh()
        try await waitForState(.downloaded, of: pack, in: launchedAfterThat)
    }

    func testATagTheSystemTookBackIsDownloadedAgainByTheSystem() async throws {
        let pack = try pack(delivery: .onDemandResourcesTag("TourPictures"))
        tagAccess.isOnDevice = false
        let library = launchLibrary(with: pack)

        library.download(pack)
        try await waitForState(.downloaded, of: pack, in: library)

        XCTAssertEqual(tagAccess.downloadCount, 1)
        XCTAssertNotNil(library.location(ofFileNamed: "Picture-light.jpg", in: pack))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try storeFolder(of: pack).path))
    }

    /// A build run from Xcode without its host, or a tag iOS took back and cannot download: Graphite's own download.
    func testWithoutTheTagThePackIsDownloadedFromTheRepository() async throws {
        let pack = try pack(delivery: .onDemandResourcesTag("TourPictures"))
        tagAccess.isOnDevice = false
        tagAccess.systemCanDownload = false
        let library = launchLibrary(with: pack)

        library.download(pack)
        try await waitForState(.downloaded, of: pack, in: library)

        XCTAssertEqual(library.location(ofFileNamed: "Picture-light.jpg", in: pack),
                       try storeFolder(of: pack).appendingPathComponent("Picture-light.jpg"))
        library.remove(pack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try storeFolder(of: pack).path), "Remove takes the downloaded copy too.")
    }

    func testAPackInTheAppBundleIsIncludedAndHasNothingToRemove() throws {
        let pack = try pack(delivery: .inAppBundle)
        let appBundle = try XCTUnwrap(Bundle(url: tagFolder))
        let library = launchLibrary(with: pack, appBundle: appBundle)

        XCTAssertEqual(library.state(of: pack), .includedWithApp)
        XCTAssertEqual(library.location(ofFileNamed: "Picture-light.jpg", in: pack)?.resolvingSymlinksInPath(),
                       tagFolder.appendingPathComponent("Picture-light.jpg").resolvingSymlinksInPath())
        library.download(pack)
        XCTAssertEqual(library.state(of: pack), .includedWithApp, "Nothing to fetch.")
        XCTAssertEqual(tagAccess.beginCount, 0)
    }

    /// The package's tests have no pictures in their bundle: the pack is downloaded as before.
    func testAPackMissingFromTheAppBundleIsDownloaded() async throws {
        let pack = try pack(delivery: .inAppBundle)
        let library = launchLibrary(with: pack)
        XCTAssertEqual(library.state(of: pack), .notDownloaded)

        library.download(pack)
        try await waitForState(.downloaded, of: pack, in: library)
        XCTAssertNotNil(library.location(ofFileNamed: "Picture-light.jpg", in: pack))
    }

    func testTheMacPicturesAreInTheAppBundleAndTheIPadPicturesATagInstalledWithTheApp() throws {
        let pack = try XCTUnwrap(WelcomeTourScreenshotPack.forThisPlatform)
        #if os(macOS)
        XCTAssertEqual(pack.delivery, .inAppBundle)
        #else
        XCTAssertEqual(pack.delivery, .onDemandResourcesTag(WelcomeTourScreenshotPack.onDemandResourcesTag))
        #endif
    }
}

/// An On-Demand Resources tag over a folder: on the device or not, downloadable by the system or not, counting what
/// the library asks of it.
@MainActor
private final class FolderTagAccess: OnDemandResourcesAccess {
    let folder: URL
    var isOnDevice = true
    var systemCanDownload = true
    private(set) var isInUse = false
    private(set) var beginCount = 0
    private(set) var downloadCount = 0
    private(set) var purgeAllowedCount = 0

    init(folder: URL) {
        self.folder = folder
    }

    func beginUsingIfOnDevice() async -> Bool {
        beginCount += 1
        isInUse = isOnDevice
        return isOnDevice
    }

    func beginUsingDownloadingIfNeeded() async throws {
        guard systemCanDownload else { throw CocoaError(.fileReadNoSuchFile) }
        downloadCount += 1
        isOnDevice = true
        isInUse = true
    }

    func location(ofFileNamed name: String) -> URL? {
        isInUse ? folder.appendingPathComponent(name) : nil
    }

    func endUsingAndAllowPurge() {
        isInUse = false
        purgeAllowedCount += 1
    }
}
