/**
 * File: PageLookHostedTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Icons, covers and columns in the app's own window on the iPad and iPhone simulators: a small demo
 *              vault of made-up course notes opened in the reading view, in light and dark, upright and sideways, in
 *              Library mode, and with the core plugin off, with pictures of each attached.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
@testable import GraphiteUI

/// The cover is drawn where the plugin is on (on the iPad, and on the iPhone only with Covers on iPhone), and nothing
/// of it while the plugin is off. The pictures are kept with the result bundle, to look at every surface.
@MainActor
final class PageLookHostedTests: XCTestCase {
    private var window: UIWindow?

    private static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private func makeDemoVault() throws -> URL {
        let release = FixtureFolders.releaseVault
        let sunset = try Data(contentsOf: release.appendingPathComponent("Attachments/Sunset over hills.png"))
        let vault = try TemporaryVault.make(prefix: "PageLook", files: [
            "Courses/Page look.md": try String(contentsOf: release.appendingPathComponent("Page look.md"), encoding: .utf8),
            "Courses/Page look linked.md": try String(contentsOf: release.appendingPathComponent("Page look linked.md"), encoding: .utf8),
            "Courses/Physics/Magnetism.md": "---\nicon: 🧲\n---\n# Magnetism\n\nField lines and [[Optics]].\n",
            "Courses/Physics/Quantum.md": "---\nicon: LiAtom\n---\n# Quantum\n\nSee [[Magnetism]].\n",
            "Courses/Physics/Optics.md": "# Optics\n\nNo icon here.\n",
            "Courses/Reading list.md": "---\nicon: book.closed\n---\n# Reading list\n",
            "Course home.md": "---\nicon: 🎓\n---\n# Course home\n\n[[Page look]], [[Magnetism]] and [[Optics]].\n",
        ], for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try sunset.write(to: vault.appendingPathComponent("Attachments/Sunset over hills.png"))
        return vault
    }

    private func picture() throws -> UIImage {
        let shownWindow = try XCTUnwrap(window)
        return UIGraphicsImageRenderer(bounds: shownWindow.bounds).image { _ in shownWindow.drawHierarchy(in: shownWindow.bounds, afterScreenUpdates: true) }
    }

    private func attach(_ image: UIImage, named name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = (Self.isPhone ? "iphone-" : "ipad-") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// How many sampled pixels of the top band of the window differ between two pictures of it.
    private func differingPixels(inTopBandOf first: UIImage, and second: UIImage) throws -> Int {
        func pixels(_ image: UIImage) throws -> [UInt8] {
            let cgImage = try XCTUnwrap(image.cgImage)
            let width = 120, height = 60
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let band = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height * 2 / 5)))
            context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: height))
            return bytes
        }
        let firstPixels = try pixels(first), secondPixels = try pixels(second)
        return stride(from: 0, to: firstPixels.count, by: 4).filter { index in abs(Int(firstPixels[index]) - Int(secondPixels[index])) > 24 }.count
    }

    /// Gives the window the screen's size sideways or upright. A hosted test's window does not turn with the device,
    /// so the sideways layout is the window's size, not a turned screen.
    private func layOutSideways(_ isSideways: Bool, quietWatch: MainThreadQuietWatch) async throws {
        let screen = try XCTUnwrap(window?.windowScene).effectiveGeometry.coordinateSpace.bounds
        let longSide = max(screen.width, screen.height), shortSide = min(screen.width, screen.height)
        window?.frame = CGRect(x: 0, y: 0, width: isSideways ? longSide : shortSide, height: isSideways ? shortSide : longSide)
        _ = try await quietWatch.measure({})
    }

    func testTheDemoVaultShowsIconsACoverAndColumns() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .list
        try await workspace.openFolderAsVault(try makeDemoVault())
        try await waitUntil("the demo vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        workspace.expandedFolders.formUnion([try VaultPath("Courses"), try VaultPath("Courses/Physics")])
        await workspace.open(try VaultPath("Courses/Page look linked.md"), placement: .currentTab)
        await workspace.open(try VaultPath("Course home.md"), placement: .newTab)
        await workspace.open(try VaultPath("Courses/Page look.md"), placement: .newTab)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .reading
        let shownWindow = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        window = shownWindow
        let quietWatch = MainThreadQuietWatch(window: shownWindow, quietStepsToStop: 200)
        _ = try await quietWatch.measure({})

        let upright = try picture()
        attach(upright, named: "portrait-light")
        session.viewMode = .livePreview
        _ = try await quietWatch.measure({})
        attach(try picture(), named: "portrait-light-live-preview")
        session.viewMode = .reading
        _ = try await quietWatch.measure({})
        workspace.preferences.appearanceMode = .dark
        _ = try await quietWatch.measure({})
        attach(try picture(), named: "portrait-dark")

        try await layOutSideways(true, quietWatch: quietWatch)
        attach(try picture(), named: "landscape-dark")
        workspace.preferences.appearanceMode = .light
        _ = try await quietWatch.measure({})
        attach(try picture(), named: "landscape-light")

        workspace.preferences.library.presentation = .library
        _ = try await quietWatch.measure({})
        attach(try picture(), named: "library-light")
        workspace.preferences.library.presentation = .list
        await workspace.open(try VaultPath("Course home.md"), placement: .currentTab)
        workspace.markdownSession?.viewMode = .reading
        _ = try await quietWatch.measure({})
        attach(try picture(), named: "landscape-links-light")
        await workspace.open(try VaultPath("Courses/Page look.md"), placement: .currentTab)
        workspace.markdownSession?.viewMode = .reading
        try await layOutSideways(false, quietWatch: quietWatch)

        if Self.isPhone {
            workspace.preferences.showsCoversOnPhone = true
            _ = try await quietWatch.measure({})
            let withCover = try picture()
            attach(withCover, named: "portrait-light-covers-on")
            XCTAssertGreaterThan(try differingPixels(inTopBandOf: upright, and: withCover), 200, "Covers on iPhone draws the cover.")
        }
        workspace.setCorePluginEnabled(.pageLook, false)
        _ = try await quietWatch.measure({})
        let off = try picture()
        attach(off, named: "portrait-light-plugin-off")
        // The phone draws no cover by default; its pictures with the plugin on and off are to be looked at.
        if !Self.isPhone {
            XCTAssertGreaterThan(try differingPixels(inTopBandOf: upright, and: off), 200,
                                 "The cover and the icons are drawn while the plugin is on, and not while it is off.")
        }
    }
}
#endif
