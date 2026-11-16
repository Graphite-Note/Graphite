/**
 * File: WelcomeTourPicturesHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: On the iPad, the welcome tour's pictures come through the On-Demand Resources tag installed with the app:
 *              the first page shows its picture with no network, and a removed pack is reported removed and asked for
 *              again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// The owner, 2026-11-12: a first launch showed the tour's first page with "Downloading the pictures…". The iPad and
/// iPhone pictures are now the tag `WelcomeTourPictures` of the app target, an initial install tag, read through
/// `NSBundleResourceRequest` (`BundleResourceRequestAccess`); these tests use the app's own tag in the simulator, with a
/// download session that refuses every request, so Graphite's own download from GitHub cannot stand in for it.
@MainActor
final class WelcomeTourPicturesHostedTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var device: IsolatedDeviceState!
    private var folders: URL!

    override func setUp() async throws {
        device = try IsolatedDeviceState.make(prefix: "WelcomeTourPicturesHosted", for: self)
        folders = try TemporaryVault.make(prefix: "WelcomeTourPicturesHostedFolders", for: self).root
    }

    override func tearDown() async throws {
        for window in windows { window.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private var pack: AddOnPack {
        get throws { try XCTUnwrap(WelcomeTourScreenshotPack.forThisPlatform) }
    }

    /// The library one launch of the app makes, over this test's folders and preferences, with no network.
    private func launchLibrary(includedCopies: AddOnIncludedCopies? = nil) throws -> AddOnLibrary {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingEveryRequestProtocol.self]
        return AddOnLibrary(packs: [try pack], applicationFolders: .temporary(below: folders), session: URLSession(configuration: configuration),
                            includedCopies: includedCopies ?? .live(defaults: device.preferences))
    }

    private var downloadedCopies: URL {
        get throws { try AddOnPackStore.inApplicationSupport(ApplicationFolders.temporary(below: folders).applicationSupportFolder).packsFolder }
    }

    private var firstPictureName: String {
        get throws {
            let screenshot = try XCTUnwrap(WelcomeTourPage.pagesOnThisPlatform.first?.content.screenshots.first)
            return WelcomeTourScreenshotPack.fileName(of: screenshot.assetName, isDark: false)
        }
    }

    private func waitUntilFetched(_ library: AddOnLibrary) async throws {
        let pack = try pack
        try await waitUntil("the pictures are on the device or failed", timeoutSeconds: 60) {
            switch library.state(of: pack) {
            case .downloaded, .failed, .includedWithApp: true
            case .notDownloaded, .checking, .downloading: false
            }
        }
        XCTAssertEqual(library.state(of: pack), .downloaded, "Through the tag, with no network.")
    }

    func testOnAFirstLaunchTheFirstPageShowsItsPictureThroughTheTagWithNoNetwork() async throws {
        let library = try launchLibrary()
        let pack = try pack
        // As `FirstLaunchWelcomeTour` asks at launch.
        library.download(pack)
        try await waitUntilFetched(library)

        let picture = try XCTUnwrap(library.location(ofFileNamed: try firstPictureName, in: pack))
        XCTAssertFalse(picture.path.hasPrefix(try downloadedCopies.path), "Read from the tag, not from a download: \(picture.path)")
        XCTAssertNotNil(UIImage(contentsOfFile: picture.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try downloadedCopies.path), "Graphite downloaded nothing.")

        // The first page as the tour shows it, beside the same page while the pictures are not here.
        let firstPage = try XCTUnwrap(WelcomeTourPage.pagesOnThisPlatform.first)
        let placeholderLibrary = try launchLibrary(includedCopies: AddOnIncludedCopies(appBundle: .main, defaults: device.preferences, makeTagAccess: nil))
        let waiting = try host(WelcomeTourPageView(content: firstPage.content).environment(placeholderLibrary))
        let withPicture = try host(WelcomeTourPageView(content: firstPage.content).environment(library))
        defer {
            attach(screenshot(of: withPicture), named: "First page with its picture")
            attach(screenshot(of: waiting), named: "First page waiting for its picture")
        }
        // The words on the left are the same on both; on the right, a screenshot of a note has hundreds of lines of small
        // text where the placeholder has a spinner and one line.
        try await waitUntil("the picture is drawn", timeoutSeconds: 20, pollingIntervalSeconds: 0.25) {
            let pictureEdges = Self.edgeCount(of: screenshot(of: withPicture)), waitingEdges = Self.edgeCount(of: screenshot(of: waiting))
            return Double(pictureEdges) > Double(waitingEdges) * 2
        }
    }

    func testARemovedPackIsReportedRemovedAndAskedForAgain() async throws {
        let library = try launchLibrary()
        let pack = try pack
        library.download(pack)
        try await waitUntilFetched(library)

        library.remove(pack)
        XCTAssertEqual(library.state(of: pack), .notDownloaded)
        XCTAssertNil(library.location(ofFileNamed: try firstPictureName, in: pack))

        // The next launch, while iOS may not have taken the files back yet: Settings still shows them removed.
        let relaunched = try launchLibrary()
        relaunched.refresh()
        XCTAssertEqual(relaunched.state(of: pack), .notDownloaded, "Not looked for again until asked for.")

        // The tour opened again asks for them.
        relaunched.download(pack)
        try await waitUntilFetched(relaunched)
        let picture = try XCTUnwrap(relaunched.location(ofFileNamed: try firstPictureName, in: pack))
        XCTAssertFalse(picture.path.hasPrefix(try downloadedCopies.path))
    }

    private func host(_ rootView: some View) throws -> UIViewController {
        let controller = UIHostingController(rootView: AnyView(rootView))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func screenshot(of controller: UIViewController) -> UIImage {
        let bounds = controller.view.bounds
        return UIGraphicsImageRenderer(bounds: bounds).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func attach(_ image: UIImage, named name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// How many pixels of the right half differ by more than an eighth of the grey scale from their right-hand
    /// neighbour: the edges of text and lines where the page shows its picture, read at half the screenshot's size.
    private static func edgeCount(of image: UIImage) -> Int {
        guard let source = image.cgImage else { return 0 }
        let width = max(source.width / 2, 2), height = max(source.height / 2, 1)
        guard let grey = pixels(of: source, width: width, height: height) else { return 0 }
        return grey.indices.filter { position in
            position % width >= width / 2 && position % width != width - 1 && abs(Int(grey[position]) - Int(grey[position + 1])) > 32
        }.count
    }

    /// The image's grey levels, drawn at this width and height.
    private static func pixels(of source: CGImage, width: Int, height: Int) -> [UInt8]? {
        var grey = [UInt8](repeating: 0, count: width * height)
        let drawn = grey.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? grey : nil
    }
}

/// Fails every request as a device with no network does.
private final class RefusingEveryRequestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif
